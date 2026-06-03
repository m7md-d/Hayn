//! Lossless JPEG metadata surgery.
//!
//! Drop APP1 (EXIF/XMP), APP13 (IPTC/Photoshop), APP14 (Adobe) and COM; keep
//! APP0 (JFIF) and every coding segment. APP2 (ICC) is kept unless the policy
//! strips colour. The entropy-coded scan is copied byte-for-byte, so the pixels
//! are identical. On ANY malformation we return the input untouched — never
//! risk corrupting the image.

use super::{IccPolicy, StripPolicy};
use crate::engine::error::Result;

pub fn strip(b: &[u8], policy: StripPolicy) -> Result<Vec<u8>> {
    Ok(strip_bytes(b, policy))
}

fn strip_bytes(b: &[u8], policy: StripPolicy) -> Vec<u8> {
    if b.len() < 4 || b[0] != 0xFF || b[1] != 0xD8 {
        return b.to_vec();
    }
    let strip_icc = policy.icc == IccPolicy::Strip;

    let mut out: Vec<u8> = Vec::with_capacity(b.len());
    out.extend_from_slice(&[0xFF, 0xD8]);
    let mut i = 2usize;
    while i + 1 < b.len() {
        if b[i] != 0xFF {
            return b.to_vec();
        }
        let mut marker = b[i + 1];
        // Skip fill bytes (0xFF padding) before the real marker.
        while marker == 0xFF && i + 2 < b.len() {
            i += 1;
            marker = b[i + 1];
        }
        if marker == 0xDA {
            // Start of scan: entropy-coded data + EOI follow — copy verbatim.
            out.extend_from_slice(&b[i..]);
            return out;
        }
        if marker == 0xD9 {
            out.extend_from_slice(&[0xFF, 0xD9]);
            return out;
        }
        if i + 4 > b.len() {
            return b.to_vec();
        }
        let len = ((b[i + 2] as usize) << 8) | (b[i + 3] as usize);
        let seg_end = i + 2 + len;
        if len < 2 || seg_end > b.len() {
            return b.to_vec();
        }
        // APP1 (E1), APP13 (ED), APP14 (EE), COM (FE) always; APP2/ICC (E2) only
        // when the policy strips colour.
        let drop = matches!(marker, 0xE1 | 0xED | 0xEE | 0xFE) || (marker == 0xE2 && strip_icc);
        if !drop {
            out.extend_from_slice(&b[i..seg_end]);
        }
        i = seg_end;
    }
    b.to_vec()
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

    #[test]
    fn malformed_returns_input_untouched() {
        let junk = vec![0xFF, 0xD8, 0x00, 0x01, 0x02];
        assert_eq!(strip(&junk, StripPolicy::default()).unwrap(), junk);
    }
}
