//! Lossless JPEG metadata surgery.
//!
//! Drop APP1 EXIF, APP13 (IPTC/Photoshop) and COM; keep APP0 (JFIF), APP14
//! (Adobe: the colour transform the scan was coded with) and every coding
//! segment. APP2 keeps the MPF index that locates an Ultra-HDR gain map, and
//! ICC unless the policy strips colour. APP1 XMP is surgically filtered (not
//! dropped): the gain-map metadata survives while privacy properties are
//! removed, so HDR isn't silently lost. The entropy-coded scan and whatever
//! follows it (the gain-map image MPF points at) are copied byte-for-byte, so
//! the pixels are identical. EXIF is replaced by a minimal block holding only a
//! non-upright Orientation, so the image still displays upright (IMG-07).
//!
//! Removing segments moves everything after them, so the MPF entries are
//! rewritten: the primary's size and each other image's offset (Hayn IMG-06).
//! Any malformation, an MPF entry that no longer lands on an image, or a
//! secondary image carrying EXIF/IPTC (which this cannot clean) is an error:
//! returning the input would hand back the private data as "clean".

use super::{exif, xmp, IccPolicy, StripPolicy};
use crate::engine::error::{DarkError, Result};

const XMP_SIG: &[u8] = b"http://ns.adobe.com/xap/1.0/\0";

pub fn strip(b: &[u8], policy: StripPolicy) -> Result<Vec<u8>> {
    strip_bytes(b, policy).ok_or(DarkError::Malformed("jpeg: cannot strip safely"))
}

fn strip_bytes(b: &[u8], policy: StripPolicy) -> Option<Vec<u8>> {
    if b.len() < 4 || b[0] != 0xFF || b[1] != 0xD8 {
        return None;
    }
    let strip_icc = policy.icc == IccPolicy::Strip;
    // Written in place of the first EXIF segment; OrientationPolicy::Keep.
    let mut orientation = exif::orientation_only(super::extract(b).orientation);

    let mut out: Vec<u8> = Vec::with_capacity(b.len());
    out.extend_from_slice(&[0xFF, 0xD8]);
    // Where the MPF TIFF header sat in the input and sits in the output.
    let mut mpf: Option<(usize, usize)> = None;
    let mut i = 2usize;
    while i + 1 < b.len() {
        if b[i] != 0xFF {
            return None;
        }
        let mut marker = b[i + 1];
        // Skip fill bytes (0xFF padding) before the real marker.
        while marker == 0xFF && i + 2 < b.len() {
            i += 1;
            marker = b[i + 1];
        }
        if marker == 0xDA {
            // Start of scan: entropy-coded data + EOI (+ any MPF images) follow
            // — copy verbatim, then move the MPF entries by what was removed.
            let removed = i - out.len();
            out.extend_from_slice(&b[i..]);
            if let Some((old_tiff, new_tiff)) = mpf {
                patch_mpf(&mut out, new_tiff, old_tiff - new_tiff, removed)?;
            }
            return Some(out);
        }
        if marker == 0xD9 {
            out.extend_from_slice(&[0xFF, 0xD9]);
            return Some(out);
        }
        if i + 4 > b.len() {
            return None;
        }
        let len = ((b[i + 2] as usize) << 8) | (b[i + 3] as usize);
        let seg_end = i + 2 + len;
        if len < 2 || seg_end > b.len() {
            return None;
        }
        let payload = &b[i + 4..seg_end];

        // APP1 splits two ways: EXIF is dropped; XMP is surgically filtered so an
        // Ultra-HDR gain map survives while privacy properties go.
        if marker == 0xE1 {
            if let Some(xmp_body) = payload.strip_prefix(XMP_SIG) {
                if let Some(filtered) = xmp::strip_privacy_keeping_hdr(xmp_body) {
                    let mut seg = XMP_SIG.to_vec();
                    seg.extend_from_slice(&filtered);
                    if seg.len() + 2 <= 0xFFFF {
                        out.push(0xFF);
                        out.push(0xE1);
                        out.extend_from_slice(&((seg.len() + 2) as u16).to_be_bytes());
                        out.extend_from_slice(&seg);
                    } // too big for one APP1 → drop (gain-map XMP is small in practice)
                }
                // else: no gain map → drop the XMP entirely (privacy).
            } else if payload.starts_with(b"Exif\0\0") {
                if let Some(tiff) = orientation.take() {
                    out.extend_from_slice(&[0xFF, 0xE1]);
                    out.extend_from_slice(&((tiff.len() + 8) as u16).to_be_bytes());
                    out.extend_from_slice(b"Exif\0\0");
                    out.extend_from_slice(&tiff);
                }
            }
            // EXIF (or any other APP1) → drop.
            i = seg_end;
            continue;
        }

        // APP13 (ED) and COM (FE) always; APP2 ICC only when the policy strips
        // colour. The MPF index (also APP2) stays and is rewritten at the scan.
        let icc = marker == 0xE2 && payload.starts_with(b"ICC_PROFILE\0");
        let drop = matches!(marker, 0xED | 0xFE) || (icc && strip_icc);
        if !drop {
            if marker == 0xE2 && payload.starts_with(b"MPF\0") {
                if mpf.is_some() {
                    return None; // two MPF indexes: not a layout to guess at
                }
                mpf = Some((i + 8, out.len() + 8));
            }
            out.extend_from_slice(&b[i..seg_end]);
        }
        i = seg_end;
    }
    None
}

/// Rewrite the MP Entry list (tag 0xB002) of the MPF index whose TIFF header
/// starts at `tiff` in `out`. Offsets are relative to that header: `shift` is
/// how far the header moved back, `removed` how far everything after the scan
/// moved back. The primary (offset 0) shrinks by `removed`; every other image
/// must still start with SOI and carry no EXIF/IPTC, or the strip is refused.
fn patch_mpf(out: &mut [u8], tiff: usize, shift: usize, removed: usize) -> Option<()> {
    let le = match out.get(tiff..tiff + 4)? {
        b"II*\0" => true,
        b"MM\0*" => false,
        _ => return None,
    };
    let rd16 = |o: &[u8], at: usize| -> Option<u16> {
        let v: [u8; 2] = o.get(at..at + 2)?.try_into().ok()?;
        Some(if le {
            u16::from_le_bytes(v)
        } else {
            u16::from_be_bytes(v)
        })
    };
    let rd32 = |o: &[u8], at: usize| -> Option<u32> {
        let v: [u8; 4] = o.get(at..at + 4)?.try_into().ok()?;
        Some(if le {
            u32::from_le_bytes(v)
        } else {
            u32::from_be_bytes(v)
        })
    };
    let ifd = tiff.checked_add(rd32(out, tiff + 4)? as usize)?;
    let count = rd16(out, ifd)? as usize;
    let mut entries = None;
    for k in 0..count {
        let e = ifd + 2 + 12 * k;
        if rd16(out, e)? == 0xB002 {
            let len = rd32(out, e + 4)? as usize;
            if !len.is_multiple_of(16) || len <= 4 {
                return None;
            }
            entries = Some((tiff.checked_add(rd32(out, e + 8)? as usize)?, len / 16));
        }
    }
    let (at, n) = entries?;
    for j in 0..n {
        let e = at + 16 * j;
        let (size, offset) = (rd32(out, e + 4)? as usize, rd32(out, e + 8)? as usize);
        let (field, value) = if offset == 0 {
            (e + 4, size.checked_sub(removed)?)
        } else {
            let moved = (offset + shift).checked_sub(removed)?;
            let start = tiff.checked_add(moved)?;
            if out.get(start..start + 2)? != [0xFF, 0xD8] || carries_private(out.get(start..)?)? {
                return None;
            }
            (e + 8, moved)
        };
        let value = u32::try_from(value).ok()?;
        let bytes = if le {
            value.to_le_bytes()
        } else {
            value.to_be_bytes()
        };
        out.get_mut(field..field + 4)?.copy_from_slice(&bytes);
    }
    Some(())
}

/// Whether the JPEG at the start of `b` carries EXIF (APP1) or IPTC (APP13)
/// before its scan. `None` when its segments do not parse.
fn carries_private(b: &[u8]) -> Option<bool> {
    let mut i = 2usize;
    loop {
        if *b.get(i)? != 0xFF {
            return None;
        }
        let marker = *b.get(i + 1)?;
        if marker == 0xDA || marker == 0xD9 {
            return Some(false);
        }
        let len = u16::from_be_bytes([*b.get(i + 2)?, *b.get(i + 3)?]) as usize;
        let payload = b.get(i + 4..(i + 2).checked_add(len)?)?;
        if marker == 0xED || (marker == 0xE1 && payload.starts_with(b"Exif\0\0")) {
            return Some(true);
        }
        i += 2 + len;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::metadata::{IccPolicy, OrientationPolicy, StripPolicy};

    /// Append an `FFxx` marker segment (length includes the 2 length bytes).
    fn seg(out: &mut Vec<u8>, marker: u8, payload: &[u8]) {
        out.push(0xFF);
        out.push(marker);
        let len = (payload.len() + 2) as u16;
        out.extend_from_slice(&len.to_be_bytes());
        out.extend_from_slice(payload);
    }

    fn sample() -> Vec<u8> {
        let mut j = vec![0xFF, 0xD8];
        seg(&mut j, 0xE0, b"JFIF\0\x01\x01\0\0\x01\0\x01\0\0"); // APP0 JFIF
        seg(&mut j, 0xE1, b"Exif\0\0secret-gps-here"); // APP1 EXIF/GPS
        seg(&mut j, 0xE2, b"ICC_PROFILE\0fake-icc-data"); // APP2 ICC
        seg(&mut j, 0xFE, b"a private comment"); // COM
        j.extend_from_slice(&[0xFF, 0xDA, 0x00, 0x08, 1, 1, 0, 2, 0x11, 0x00]); // SOS header
        j.extend_from_slice(&[0x12, 0x34, 0x56, 0x78]); // entropy-coded scan
        j.extend_from_slice(&[0xFF, 0xD9]); // EOI
        j
    }

    fn contains(hay: &[u8], needle: &[u8]) -> bool {
        hay.windows(needle.len()).any(|w| w == needle)
    }

    #[test]
    fn drops_exif_and_comment_keeps_jfif_icc_and_scan() {
        let j = sample();
        let out = strip(&j, StripPolicy::default()).unwrap();
        assert!(!contains(&out, b"secret-gps-here"), "EXIF must be gone");
        assert!(!contains(&out, b"a private comment"), "COM must be gone");
        assert!(contains(&out, b"JFIF"), "APP0 kept");
        assert!(contains(&out, b"ICC_PROFILE"), "ICC kept by default");
        // The scan + EOI are byte-identical (lossless).
        assert!(contains(&out, &[0x12, 0x34, 0x56, 0x78]));
        assert_eq!(&out[out.len() - 2..], &[0xFF, 0xD9]);
        assert!(out.len() < j.len());
    }

    #[test]
    fn strip_icc_also_removes_the_profile() {
        let out = strip(
            &sample(),
            StripPolicy {
                icc: IccPolicy::Strip,
                orientation: OrientationPolicy::Keep,
            },
        )
        .unwrap();
        assert!(
            !contains(&out, b"ICC_PROFILE"),
            "ICC removed when policy says so"
        );
        assert!(contains(&out, b"JFIF"));
    }

    /// Returning the input would hand the private data back as "clean".
    #[test]
    fn malformed_is_an_error() {
        let junk = vec![0xFF, 0xD8, 0x00, 0x01, 0x02];
        assert!(strip(&junk, StripPolicy::default()).is_err());
    }

    /// A minimal JPEG: SOI, `segments`, a scan, EOI.
    fn jpeg(segments: &[(u8, &[u8])], scan: &[u8]) -> Vec<u8> {
        let mut j = vec![0xFF, 0xD8];
        for (m, p) in segments {
            seg(&mut j, *m, p);
        }
        j.extend_from_slice(&[0xFF, 0xDA, 0x00, 0x08, 1, 1, 0, 2, 0x11, 0x00]);
        j.extend_from_slice(scan);
        j.extend_from_slice(&[0xFF, 0xD9]);
        j
    }

    /// Big-endian MPF APP2 payload with a two-entry MP Entry list.
    fn mpf(primary_size: u32, second_size: u32, second_offset: u32) -> Vec<u8> {
        let mut p = b"MPF\0MM\0*".to_vec();
        p.extend_from_slice(&8u32.to_be_bytes()); // IFD right after the header
        p.extend_from_slice(&1u16.to_be_bytes()); // one tag
        p.extend_from_slice(&0xB002u16.to_be_bytes());
        p.extend_from_slice(&7u16.to_be_bytes()); // UNDEFINED
        p.extend_from_slice(&32u32.to_be_bytes()); // 2 entries × 16 bytes
        p.extend_from_slice(&26u32.to_be_bytes()); // 8 + 2 + 12 + 4
        p.extend_from_slice(&0u32.to_be_bytes()); // next IFD
        for (size, off) in [(primary_size, 0u32), (second_size, second_offset)] {
            p.extend_from_slice(&0x0003_0000u32.to_be_bytes());
            p.extend_from_slice(&size.to_be_bytes());
            p.extend_from_slice(&off.to_be_bytes());
            p.extend_from_slice(&[0; 4]);
        }
        p
    }

    /// A primary with `before` and `after` segments around a valid MPF index,
    /// followed by the `second` JPEG it points at.
    fn around_mpf(before: &[(u8, &[u8])], after: &[(u8, &[u8])], second: &[u8]) -> Vec<u8> {
        let build = |m: &[u8]| {
            let mut segs = before.to_vec();
            segs.push((0xE2, m));
            segs.extend_from_slice(after);
            jpeg(&segs, &[0x12, 0x34])
        };
        let primary_len = build(&mpf(0, 0, 0)).len();
        // SOI, the segments before, the APP2 header, "MPF\0".
        let tiff = 2 + before.iter().map(|(_, p)| 4 + p.len()).sum::<usize>() + 4 + 4;
        let m = mpf(
            primary_len as u32,
            second.len() as u32,
            (primary_len - tiff) as u32,
        );
        let mut j = build(&m);
        j.extend_from_slice(second);
        j
    }

    /// EXIF before MPF and a COM after it: both go, and move the second image.
    fn with_gain_map(second: &[u8]) -> Vec<u8> {
        around_mpf(
            &[(0xE1, b"Exif\0\0secret-gps")],
            &[(0xFE, b"comment after MPF")],
            second,
        )
    }

    fn entry(out: &[u8], k: usize) -> (u32, u32) {
        let tiff = out.windows(4).position(|w| w == b"MPF\0").unwrap() + 4;
        let e = tiff + 26 + 16 * k;
        let be = |a: usize| u32::from_be_bytes(out[a..a + 4].try_into().unwrap());
        (be(e + 4), be(e + 8))
    }

    #[test]
    fn mpf_entries_follow_the_removed_segments() {
        let second = jpeg(&[(0xE1, b"http://ns.adobe.com/xap/1.0/\0<x/>")], &[0x56]);
        let j = with_gain_map(&second);
        let out = strip(&j, StripPolicy::default()).unwrap();
        assert!(!contains(&out, b"secret-gps") && !contains(&out, b"comment after MPF"));
        let tiff = out.windows(4).position(|w| w == b"MPF\0").unwrap() + 4;
        let (primary_size, _) = entry(&out, 0);
        let (size, offset) = entry(&out, 1);
        let at = tiff + offset as usize;
        assert_eq!(
            &out[at..at + size as usize],
            &second[..],
            "second image found"
        );
        assert_eq!(primary_size as usize, at, "primary ends where it starts");
        assert_eq!(&out[at - 2..at], &[0xFF, 0xD9]);
    }

    #[test]
    fn secondary_image_with_exif_is_refused() {
        let second = jpeg(&[(0xE1, b"Exif\0\0gps-in-the-gain-map")], &[0x56]);
        assert!(strip(&with_gain_map(&second), StripPolicy::default()).is_err());
    }

    #[test]
    fn colour_strip_keeps_mpf_and_the_adobe_transform() {
        let second = jpeg(&[], &[0x56]);
        let j = around_mpf(
            &[(0xE2, b"ICC_PROFILE\0profile")],
            &[(0xEE, b"Adobe\0\x64\0\0\0\0\x01")],
            &second,
        );
        let policy = StripPolicy {
            icc: IccPolicy::Strip,
            orientation: OrientationPolicy::Keep,
        };
        let out = strip(&j, policy).unwrap();
        assert!(!contains(&out, b"ICC_PROFILE"));
        assert!(contains(&out, b"Adobe"));
        let tiff = out.windows(4).position(|w| w == b"MPF\0").unwrap() + 4;
        let (size, offset) = entry(&out, 1);
        let at = tiff + offset as usize;
        assert_eq!(&out[at..at + size as usize], &second[..]);
    }

    #[test]
    fn keeps_hdr_xmp_drops_privacy_and_exif() {
        let xmp = br#"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:hdrgm="http://ns.adobe.com/hdr-gain-map/1.0/" xmlns:exif="http://ns.adobe.com/exif/1.0/" hdrgm:Version="1.0" exif:GPSLatitude="secret-gps"/></rdf:RDF></x:xmpmeta>"#;
        let mut j = vec![0xFF, 0xD8];
        seg(&mut j, 0xE1, b"Exif\0\0exif-gps-data"); // APP1 EXIF → dropped
        let mut xmp_seg = b"http://ns.adobe.com/xap/1.0/\0".to_vec();
        xmp_seg.extend_from_slice(xmp);
        seg(&mut j, 0xE1, &xmp_seg); // APP1 XMP → filtered
        j.extend_from_slice(&[0xFF, 0xDA, 0x00, 0x08, 1, 1, 0, 2, 0x11, 0x00]);
        j.extend_from_slice(&[0x12, 0x34]); // scan
        j.extend_from_slice(&[0xFF, 0xD9]);

        let out = strip(&j, StripPolicy::default()).unwrap();
        assert!(contains(&out, b"hdrgm:Version"), "gain-map XMP kept");
        assert!(!contains(&out, b"exif-gps-data"), "EXIF segment dropped");
        assert!(!contains(&out, b"secret-gps"), "XMP privacy dropped");
        assert!(!contains(&out, b"GPSLatitude"));
        assert!(contains(&out, &[0x12, 0x34]), "scan byte-identical");
    }
}
