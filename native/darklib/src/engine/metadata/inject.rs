//! Metadata INJECTION — embed EXIF / XMP / ICC from a [`Canonical`] into an
//! encoded image (the inverse of `extract`). Used to CARRY metadata through a
//! re-encode (compress/convert) so it isn't lost.
//!
//! Orientation in the carried EXIF is normalised to 1: the pixels are baked
//! upright on decode, so a non-1 tag would double-rotate (single source of
//! truth — CLAUDE.md / docs/10-DARKLIB.md §5). JPEG + PNG today; AVIF (ISOBMFF
//! add-item) and WebP (mux) come next. Best-effort: a format without an injector
//! yet returns the encoded bytes unchanged.

use super::{exif, Canonical};
use crate::engine::format::{detect, ImageFormat};

const XMP_SIG: &[u8] = b"http://ns.adobe.com/xap/1.0/\0";

/// Embed `meta` into `encoded` (same container).
pub fn inject(encoded: &[u8], meta: &Canonical) -> Vec<u8> {
    match detect(encoded) {
        ImageFormat::Jpeg => inject_jpeg(encoded, meta),
        ImageFormat::Png => inject_png(encoded, meta),
        _ => encoded.to_vec(),
    }
}

fn inject_jpeg(jpeg: &[u8], meta: &Canonical) -> Vec<u8> {
    if jpeg.len() < 2 || jpeg[0] != 0xFF || jpeg[1] != 0xD8 {
        return jpeg.to_vec();
    }
    let mut out = Vec::with_capacity(jpeg.len() + 1024);
    out.extend_from_slice(&[0xFF, 0xD8]);

    if let Some(tiff) = &meta.exif {
        let mut payload = b"Exif\0\0".to_vec();
        payload.extend_from_slice(&exif::with_orientation_1(tiff));
        app_segment(&mut out, 0xE1, &payload);
    }
    if let Some(xmp) = &meta.xmp {
        let mut payload = XMP_SIG.to_vec();
        payload.extend_from_slice(xmp);
        app_segment(&mut out, 0xE1, &payload);
    }
    if let Some(icc) = &meta.icc {
        // Single-chunk ICC (profiles up to ~64 KB; larger would need splitting).
        if icc.len() <= 65515 {
            let mut payload = b"ICC_PROFILE\0".to_vec();
            payload.push(1); // chunk seq
            payload.push(1); // chunk count
            payload.extend_from_slice(icc);
            app_segment(&mut out, 0xE2, &payload);
        }
    }
    out.extend_from_slice(&jpeg[2..]); // the original image after SOI
    out
}

/// Append an `FFxx` APPn segment (skips it if the payload exceeds the u16 limit).
fn app_segment(out: &mut Vec<u8>, marker: u8, payload: &[u8]) {
    if payload.len() + 2 > 0xFFFF {
        return;
    }
    out.push(0xFF);
    out.push(marker);
    out.extend_from_slice(&((payload.len() + 2) as u16).to_be_bytes());
    out.extend_from_slice(payload);
}

fn inject_png(png: &[u8], meta: &Canonical) -> Vec<u8> {
    const SIG: [u8; 8] = [137, 80, 78, 71, 13, 10, 26, 10];
    // Insert right after IHDR (sig 8 + len 4 + "IHDR" 4 + data 13 + crc 4 = 33).
    let ihdr_end = 33usize;
    if png.len() < ihdr_end || png[..8] != SIG || &png[12..16] != b"IHDR" {
        return png.to_vec();
    }
    let mut out = png[..ihdr_end].to_vec();
    if let Some(tiff) = &meta.exif {
        png_chunk(&mut out, b"eXIf", &exif::with_orientation_1(tiff));
    }
    if let Some(xmp) = &meta.xmp {
        if xmp.starts_with(b"XML:com.adobe.xmp\0") {
            png_chunk(&mut out, b"iTXt", xmp); // already an iTXt payload (PNG source)
        } else {
            let mut p = b"XML:com.adobe.xmp\0".to_vec();
            p.extend_from_slice(&[0, 0, 0, 0]); // comp flag, method, empty lang\0, empty transkw\0
            p.extend_from_slice(xmp);
            png_chunk(&mut out, b"iTXt", &p);
        }
    }
    // ICC for PNG (iCCP) needs zlib compression for cross-format profiles — done
    // in a later pass; EXIF/XMP (the privacy-relevant set) carry now.
    out.extend_from_slice(&png[ihdr_end..]);
    out
}

fn png_chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    out.extend_from_slice(kind);
    out.extend_from_slice(data);
    let mut crc_in = kind.to_vec();
    crc_in.extend_from_slice(data);
    out.extend_from_slice(&crc32(&crc_in).to_be_bytes());
}

/// CRC-32 (IEEE) as used by PNG chunks.
fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0xEDB8_8320
            } else {
                crc >> 1
            };
        }
    }
    !crc
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::metadata::extract;

    fn tiff_orientation(o: u16) -> Vec<u8> {
        let mut t = b"II\x2a\x00\x08\x00\x00\x00".to_vec();
        t.extend_from_slice(&1u16.to_le_bytes());
        t.extend_from_slice(&0x0112u16.to_le_bytes()); // Orientation
        t.extend_from_slice(&3u16.to_le_bytes()); // SHORT
        t.extend_from_slice(&1u32.to_le_bytes());
        t.extend_from_slice(&(o as u32).to_le_bytes());
        t.extend_from_slice(&0u32.to_le_bytes());
        t
    }

    fn minimal_jpeg() -> Vec<u8> {
        // >= 12 bytes so `detect` recognises it (real encoded JPEGs always are).
        let mut j = vec![0xFF, 0xD8]; // SOI
        j.extend_from_slice(&[0xFF, 0xDA, 0x00, 0x08, 1, 1, 0, 0, 0, 0]); // SOS header
        j.extend_from_slice(&[0xAA, 0xBB, 0xCC]); // entropy
        j.extend_from_slice(&[0xFF, 0xD9]); // EOI
        j
    }

    fn contains(hay: &[u8], needle: &[u8]) -> bool {
        hay.windows(needle.len()).any(|w| w == needle)
    }

    #[test]
    fn jpeg_inject_carries_exif_xmp_normalising_orientation() {
        let meta = Canonical {
            exif: Some(tiff_orientation(6)),
            xmp: Some(b"<x:xmpmeta>hi</x:xmpmeta>".to_vec()),
            ..Default::default()
        };
        let out = inject(&minimal_jpeg(), &meta);
        // Round-trips through extract: EXIF present, orientation normalised to 1.
        let back = extract(&out);
        assert!(back.exif.is_some());
        assert_eq!(back.orientation, 1, "orientation normalised (pixels baked)");
        assert!(contains(&out, b"<x:xmpmeta>hi</x:xmpmeta>"), "XMP carried");
    }

    #[test]
    fn png_inject_carries_exif() {
        // A minimal valid PNG header (sig + IHDR) + IEND is enough for our parser.
        let mut png = vec![137, 80, 78, 71, 13, 10, 26, 10];
        super::png_chunk(&mut png, b"IHDR", &[0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0]);
        super::png_chunk(&mut png, b"IEND", &[]);
        let meta = Canonical {
            exif: Some(tiff_orientation(8)),
            ..Default::default()
        };
        let out = inject(&png, &meta);
        let back = extract(&out);
        assert!(back.exif.is_some(), "eXIf carried");
        assert_eq!(back.orientation, 1);
    }

    #[test]
    fn unsupported_format_returns_unchanged() {
        let bytes = vec![1u8, 2, 3, 4];
        assert_eq!(inject(&bytes, &Canonical::default()), bytes);
    }
}
