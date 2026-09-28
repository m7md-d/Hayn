//! Source inspection: the facts a conversion plan needs before any engine runs.
//!
//! Read-only and bounded by the input. `Unknown` means the container could not
//! be read far enough to answer. `NoHdrSignal` / `Absent` mean it was read and
//! carries no HDR signalling this inspector knows; that is not proof of SDR
//! (docs/11-HDR-RESEARCH.md), only the absence of a known signal.

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
}

const UNKNOWN: Facts = Facts {
    transfer: Transfer::Unknown,
    gain_map: Presence::Unknown,
};

pub fn inspect(b: &[u8]) -> Facts {
    match detect(b) {
        ImageFormat::Avif | ImageFormat::Heic => isobmff_facts(b),
        ImageFormat::Png => png_facts(b),
        ImageFormat::Jpeg => jpeg_facts(b),
        // WebP defines no HDR transfer or gain-map signalling.
        ImageFormat::Webp => Facts {
            transfer: Transfer::NoHdrSignal,
            gain_map: Presence::Absent,
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
    let gain_map = match isobmff::gainmap_presence(b) {
        None => Presence::Unknown,
        Some(true) => Presence::Present,
        Some(false) => Presence::Absent,
    };
    Facts { transfer, gain_map }
}

/// PNG signals PQ/HLG with `cICP`, which must precede the first `IDAT`.
fn png_facts(b: &[u8]) -> Facts {
    const SIG: [u8; 8] = [137, 80, 78, 71, 13, 10, 26, 10];
    if b.len() < 8 || b[..8] != SIG {
        return UNKNOWN;
    }
    let mut i = 8usize;
    while i + 8 <= b.len() {
        let len = u32::from_be_bytes([b[i], b[i + 1], b[i + 2], b[i + 3]]) as usize;
        let kind = &b[i + 4..i + 8];
        let Some(data_end) = (i + 8).checked_add(len).filter(|e| e + 4 <= b.len()) else {
            return UNKNOWN;
        };
        if kind == b"cICP" {
            // primaries(1) transfer(1) matrix(1) full_range(1)
            if len < 4 {
                return UNKNOWN;
            }
            return Facts {
                transfer: Transfer::from_code(b[i + 9] as u16),
                gain_map: Presence::Absent,
            };
        }
        if kind == b"IDAT" || kind == b"IEND" {
            break;
        }
        i = data_end + 4;
    }
    Facts {
        transfer: Transfer::NoHdrSignal,
        gain_map: Presence::Absent,
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
