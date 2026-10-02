//! Source inspection: the facts a conversion plan needs before any engine runs.
//!
//! Read-only and bounded by the input. `Unknown` means the container could not
//! be read far enough to answer. `NoHdrSignal` / `Absent` mean it was read and
//! carries no HDR signalling this inspector knows; that is not proof of SDR
//! (docs/11-HDR-RESEARCH.md), only the absence of a known signal.
//!
//! The stored size comes from the header (`codec::header_dimensions`), so a
//! plan knows a giant image before decoding it (Hayn RUN-01).
//!
//! Alpha is read from the container too, never from pixels: it says whether the
//! image carries an alpha channel (PNG colour type or `tRNS`, WebP alpha,
//! an AVIF/HEIF alpha auxiliary of the primary item). A channel that happens to
//! be fully opaque still counts as present.

use crate::engine::format::{detect, ImageFormat};
use crate::engine::metadata::isobmff;

/// Transfer function of the primary image.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Transfer {
    Unknown,
    NoHdrSignal,
    /// SMPTE ST 2084 (transfer_characteristics 16).
    Pq,
    /// ARIB STD-B67 (transfer_characteristics 18).
    Hlg,
}

impl Transfer {
    /// PQ/HLG samples: an RGBA8 sRGB path would misinterpret them.
    pub fn is_direct_hdr(self) -> bool {
        matches!(self, Transfer::Pq | Transfer::Hlg)
    }

    fn from_code(tc: u16) -> Self {
        match tc {
            16 => Transfer::Pq,
            18 => Transfer::Hlg,
            _ => Transfer::NoHdrSignal,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Presence {
    Unknown,
    Absent,
    Present,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Facts {
    pub transfer: Transfer,
    pub gain_map: Presence,
    pub alpha: Presence,
    /// Stored size from the header (for HEIF/AVIF the primary item or its
    /// grid canvas), before orientation; 0 when the header does not say.
    pub width: u32,
    pub height: u32,
    /// EXIF-style orientation (1..=8) that turns the stored pixels upright:
    /// `irot`/`imir` for HEIF/AVIF (their EXIF tag is not what readers
    /// apply), the EXIF tag otherwise. 0 when the file names none (upright).
    pub orientation: u8,
}

const UNKNOWN: Facts = Facts {
    transfer: Transfer::Unknown,
    gain_map: Presence::Unknown,
    alpha: Presence::Unknown,
    width: 0,
    height: 0,
    orientation: 0,
};

impl Presence {
    fn of(found: Option<bool>) -> Self {
        match found {
            None => Presence::Unknown,
            Some(true) => Presence::Present,
            Some(false) => Presence::Absent,
        }
    }
}

pub fn inspect(b: &[u8]) -> Facts {
    let mut facts = facts_of(b);
    if let Some((w, h)) = crate::engine::codec::header_dimensions(b) {
        (facts.width, facts.height) = (w, h);
    }
    facts.orientation = match detect(b) {
        ImageFormat::Avif | ImageFormat::Heic => {
            isobmff::read_orientation(b).map_or(0, |(a, m)| isobmff::exif_orientation(a, m))
        }
        ImageFormat::Unknown => 0,
        // `extract` answers 1 without EXIF too; only a tag counts here.
        _ => match crate::engine::metadata::extract(b) {
            c if c.exif.is_some() && (1..=8).contains(&c.orientation) => c.orientation as u8,
            _ => 0,
        },
    };
    facts
}

fn facts_of(b: &[u8]) -> Facts {
    match detect(b) {
        ImageFormat::Avif | ImageFormat::Heic => isobmff_facts(b),
        ImageFormat::Png => png_facts(b),
        ImageFormat::Jpeg => jpeg_facts(b),
        // WebP defines no HDR transfer or gain-map signalling.
        ImageFormat::Webp => Facts {
            transfer: Transfer::NoHdrSignal,
            gain_map: Presence::Absent,
            alpha: Presence::of(webp_alpha(b)),
            width: 0,
            height: 0,
            orientation: 0,
        },
        _ => UNKNOWN,
    }
}

fn isobmff_facts(b: &[u8]) -> Facts {
    let transfer = match isobmff::primary_nclx(b) {
        None => Transfer::Unknown,
        Some(None) => Transfer::NoHdrSignal,
        Some(Some((_, tc))) => Transfer::from_code(tc),
    };
    Facts {
        transfer,
        gain_map: Presence::of(isobmff::gainmap_presence(b)),
        alpha: Presence::of(isobmff::alpha_presence(b)),
        width: 0,
        height: 0,
        orientation: 0,
    }
}

/// WebP carries alpha in a lossy file's `ALPH` chunk, in a lossless
/// bitstream's `alpha_is_used` bit, and (extended files) in VP8X's alpha flag.
/// A simple lossy file (`VP8 ` alone) has none.
fn webp_alpha(b: &[u8]) -> Option<bool> {
    if b.len() < 12 || &b[..4] != b"RIFF" || &b[8..12] != b"WEBP" {
        return None;
    }
    let mut alpha = false;
    let mut i = 12usize;
    while i + 8 <= b.len() {
        let kind = &b[i..i + 4];
        let len = u32::from_le_bytes([b[i + 4], b[i + 5], b[i + 6], b[i + 7]]) as usize;
        let data = i + 8;
        let end = data.checked_add(len).filter(|&e| e <= b.len())?;
        match kind {
            b"VP8X" => alpha |= *b.get(data)? & 0x10 != 0,
            b"ALPH" => alpha = true,
            // Signature 0x2f, then width-1 (14 bits), height-1 (14), alpha (1).
            b"VP8L" => {
                if *b.get(data)? != 0x2f {
                    return None;
                }
                let bits = u32::from_le_bytes(b.get(data + 1..data + 5)?.try_into().ok()?);
                alpha |= (bits >> 28) & 1 == 1;
            }
            _ => {}
        }
        i = end + (len & 1); // chunks are padded to an even size
    }
    Some(alpha)
}

/// PNG signals PQ/HLG with `cICP`, which must precede the first `IDAT`. Alpha:
/// colour type 4 or 6 in `IHDR`, or a `tRNS` chunk (also before `IDAT`).
fn png_facts(b: &[u8]) -> Facts {
    const SIG: [u8; 8] = [137, 80, 78, 71, 13, 10, 26, 10];
    if b.len() < 8 || b[..8] != SIG {
        return UNKNOWN;
    }
    let mut transfer = Transfer::NoHdrSignal;
    let mut alpha = None;
    let mut i = 8usize;
    while i + 8 <= b.len() {
        let len = u32::from_be_bytes([b[i], b[i + 1], b[i + 2], b[i + 3]]) as usize;
        let kind = &b[i + 4..i + 8];
        let Some(data_end) = (i + 8).checked_add(len).filter(|e| e + 4 <= b.len()) else {
            return UNKNOWN;
        };
        match kind {
            b"IHDR" if len >= 13 => alpha = Some(matches!(b[i + 8 + 9], 4 | 6)),
            b"tRNS" => alpha = Some(true),
            // primaries(1) transfer(1) matrix(1) full_range(1)
            b"cICP" if len < 4 => return UNKNOWN,
            b"cICP" => transfer = Transfer::from_code(b[i + 9] as u16),
            b"IDAT" | b"IEND" => break,
            _ => {}
        }
        i = data_end + 4;
    }
    Facts {
        transfer,
        gain_map: Presence::Absent,
        alpha: Presence::of(alpha),
        width: 0,
        height: 0,
        orientation: 0,
    }
}

/// JPEG has no PQ/HLG convention; HDR arrives as a gain map located by MPF and
/// described in XMP (`hdrgm`, Apple `HDRGainMap`) or an ISO 21496-1 APP2.
/// MPF alone also serves stereo pairs and previews, so it stays Unknown.
fn jpeg_facts(b: &[u8]) -> Facts {
    const XMP_SIG: &[u8] = b"http://ns.adobe.com/xap/1.0/\0";
    const ISO_SIG: &[u8] = b"urn:iso:std:iso:ts:21496:-1";
    if b.len() < 4 || b[0] != 0xFF || b[1] != 0xD8 {
        return UNKNOWN;
    }
    let (mut marked, mut mpf) = (false, false);
    let mut i = 2usize;
    loop {
        if i + 1 >= b.len() || b[i] != 0xFF {
            return UNKNOWN;
        }
        let mut marker = b[i + 1];
        while marker == 0xFF && i + 2 < b.len() {
            i += 1;
            marker = b[i + 1];
        }
        if marker == 0xDA || marker == 0xD9 {
            break;
        }
        if i + 4 > b.len() {
            return UNKNOWN;
        }
        let len = ((b[i + 2] as usize) << 8) | (b[i + 3] as usize);
        let seg_end = i + 2 + len;
        if len < 2 || seg_end > b.len() {
            return UNKNOWN;
        }
        let payload = &b[i + 4..seg_end];
        match marker {
            0xE1 => {
                if let Some(xmp) = payload.strip_prefix(XMP_SIG) {
                    marked |= contains(xmp, b"hdrgm") || contains(xmp, b"HDRGainMap");
                }
            }
            0xE2 => {
                marked |= payload.starts_with(ISO_SIG);
                mpf |= payload.starts_with(b"MPF\0");
            }
            _ => {}
        }
        i = seg_end;
    }
    let gain_map = if marked {
        Presence::Present
    } else if mpf {
        Presence::Unknown
    } else {
        Presence::Absent
    };
    Facts {
        transfer: Transfer::NoHdrSignal,
        gain_map,
        alpha: Presence::Absent,
        width: 0,
        height: 0,
        orientation: 0,
    }
}

fn contains(hay: &[u8], needle: &[u8]) -> bool {
    hay.windows(needle.len()).any(|w| w == needle)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn png_with(chunks: &[(&[u8; 4], &[u8])]) -> Vec<u8> {
        let mut p = vec![137, 80, 78, 71, 13, 10, 26, 10];
        for (kind, data) in chunks {
            p.extend_from_slice(&(data.len() as u32).to_be_bytes());
            p.extend_from_slice(*kind);
            p.extend_from_slice(data);
            p.extend_from_slice(&[0; 4]); // CRC is not read
        }
        p
    }

    fn jpeg_with(segments: &[(u8, &[u8])]) -> Vec<u8> {
        let mut j = vec![0xFF, 0xD8];
        for (marker, payload) in segments {
            j.extend_from_slice(&[0xFF, *marker]);
            j.extend_from_slice(&((payload.len() + 2) as u16).to_be_bytes());
            j.extend_from_slice(payload);
        }
        j.extend_from_slice(&[0xFF, 0xDA, 0, 2, 0xFF, 0xD9]);
        j
    }

    #[test]
    fn png_cicp_transfer_is_read_before_idat() {
        let ihdr: &[u8] = &[0; 13];
        for (tc, want) in [
            (16u8, Transfer::Pq),
            (18, Transfer::Hlg),
            (13, Transfer::NoHdrSignal),
        ] {
            let p = png_with(&[(b"IHDR", ihdr), (b"cICP", &[9, tc, 0, 1]), (b"IDAT", &[0])]);
            assert_eq!(inspect(&p).transfer, want);
        }
        let late = png_with(&[(b"IHDR", ihdr), (b"IDAT", &[0]), (b"cICP", &[9, 16, 0, 1])]);
        assert_eq!(inspect(&late).transfer, Transfer::NoHdrSignal);
    }

    #[test]
    fn truncated_png_chunk_is_unknown() {
        let mut p = png_with(&[(b"IHDR", &[0; 13])]);
        p.truncate(p.len() - 6);
        assert_eq!(inspect(&p), UNKNOWN);
    }

    #[test]
    fn jpeg_gain_map_markers() {
        let mut xmp = b"http://ns.adobe.com/xap/1.0/\0".to_vec();
        xmp.extend_from_slice(br#"<x xmlns:hdrgm="http://ns.adobe.com/hdr-gain-map/1.0/"/>"#);
        assert_eq!(
            inspect(&jpeg_with(&[(0xE1, &xmp)])).gain_map,
            Presence::Present
        );
        let iso = b"urn:iso:std:iso:ts:21496:-1\0\0\0";
        assert_eq!(
            inspect(&jpeg_with(&[(0xE2, iso)])).gain_map,
            Presence::Present
        );
        let mpf = b"MPF\0II*\0";
        assert_eq!(
            inspect(&jpeg_with(&[(0xE2, mpf)])).gain_map,
            Presence::Unknown
        );
        let plain = inspect(&jpeg_with(&[(0xE0, b"JFIF\0")]));
        assert_eq!(plain.gain_map, Presence::Absent);
        assert_eq!(plain.transfer, Transfer::NoHdrSignal);
    }

    #[test]
    fn broken_jpeg_segment_is_unknown() {
        let mut j = jpeg_with(&[(0xE0, b"JFIF\0")]);
        j[4] = 0xFF; // segment length now runs past the end
        assert_eq!(inspect(&j), UNKNOWN);
    }

    #[test]
    fn unrecognised_bytes_are_unknown() {
        assert_eq!(inspect(&[0u8; 32]), UNKNOWN);
    }
}
