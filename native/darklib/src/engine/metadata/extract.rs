//! Metadata EXTRACTION — locate the raw EXIF / XMP / ICC / IPTC blobs in each
//! container and assemble a [`Canonical`]. Best-effort and fully bounds-safe: a
//! blob that's absent or unparseable is simply `None`. The blobs are kept
//! verbatim (no parse→reserialize) so a later `transplant`/`inject` can't drop
//! MakerNotes or private boxes.

use super::{exif, isobmff, Canonical};
use crate::engine::format::{detect, ImageFormat};

const XMP_SIG: &[u8] = b"http://ns.adobe.com/xap/1.0/\0";

/// Extract the canonical metadata from any supported container.
pub fn extract(b: &[u8]) -> Canonical {
    let mut c = match detect(b) {
        ImageFormat::Jpeg => jpeg(b),
        ImageFormat::Png => png(b),
        ImageFormat::Webp => webp(b),
        ImageFormat::Avif | ImageFormat::Heic => {
            let (exif, xmp) = isobmff::extract_exif_xmp(b);
            // Prefer an embedded profile; otherwise synthesise one from the nclx
            // code points so a profile-less P3 HEIC keeps its gamut on convert.
            let icc = isobmff::extract_icc(b).or_else(|| {
                isobmff::extract_nclx(b)
                    .and_then(|(p, t)| crate::engine::color::synthesize_from_cicp(p, t))
            });
            Canonical {
                exif,
                xmp,
                icc,
                ..Default::default()
            }
        }
        _ => Canonical::default(),
    };
    c.orientation = c
        .exif
        .as_deref()
        .and_then(exif::summarize)
        .map(|s| s.orientation)
        .unwrap_or(1);
    c
}

fn jpeg(b: &[u8]) -> Canonical {
    let mut c = Canonical::default();
    if b.len() < 4 || b[0] != 0xFF || b[1] != 0xD8 {
        return c;
    }
    let mut icc: Vec<u8> = Vec::new();
    let mut i = 2usize;
    while i + 4 <= b.len() {
        if b[i] != 0xFF {
            break;
        }
        let mut marker = b[i + 1];
        while marker == 0xFF && i + 2 < b.len() {
            i += 1;
            marker = b[i + 1];
        }
        if marker == 0xDA || marker == 0xD9 {
            break; // start of scan / end of image
        }
        if i + 4 > b.len() {
            break;
        }
        let len = ((b[i + 2] as usize) << 8) | (b[i + 3] as usize);
        let seg_end = i + 2 + len;
        if len < 2 || seg_end > b.len() {
            break;
        }
        let payload = &b[i + 4..seg_end];
        match marker {
            0xE1 => {
                if let Some(rest) = payload.strip_prefix(b"Exif\0\0".as_slice()) {
                    c.exif.get_or_insert_with(|| rest.to_vec());
                } else if let Some(rest) = payload.strip_prefix(XMP_SIG) {
                    c.xmp.get_or_insert_with(|| rest.to_vec());
                }
            }
            0xE2 => {
                // ICC_PROFILE\0 + seq(1) + count(1) + chunk; concatenate chunks.
                if payload.len() > 14 && payload.starts_with(b"ICC_PROFILE\0".as_slice()) {
                    icc.extend_from_slice(&payload[14..]);
                }
            }
            0xED => {
                c.iptc.get_or_insert_with(|| payload.to_vec());
            }
            _ => {}
        }
        i = seg_end;
    }
    if !icc.is_empty() {
        c.icc = Some(icc);
    }
    c
}

fn png(b: &[u8]) -> Canonical {
    let mut c = Canonical::default();
    const SIG: [u8; 8] = [137, 80, 78, 71, 13, 10, 26, 10];
    if b.len() < 8 || b[..8] != SIG {
        return c;
    }
    let mut i = 8usize;
    while i + 8 <= b.len() {
        let len = ((b[i] as usize) << 24)
            | ((b[i + 1] as usize) << 16)
            | ((b[i + 2] as usize) << 8)
            | (b[i + 3] as usize);
        let kind = &b[i + 4..i + 8];
        let chunk_end = i + 12 + len;
        if chunk_end > b.len() {
            break;
        }
        let data = &b[i + 8..i + 8 + len];
        if kind == b"eXIf" {
            c.exif.get_or_insert_with(|| data.to_vec());
        } else if kind == b"iCCP" {
            // Decompress to the raw ICC so Canonical.icc is the uniform
            // uncompressed profile across every container (JPEG/WebP store it
            // raw; only PNG's iCCP is zlib-compressed).
            if let Some(profile) = decode_iccp(data) {
                c.icc.get_or_insert(profile);
            }
        } else if kind == b"iTXt" && data.starts_with(b"XML:com.adobe.xmp\0".as_slice()) {
            c.xmp.get_or_insert_with(|| data.to_vec());
        }
        if kind == b"IEND" {
            break;
        }
        i = chunk_end;
    }
    c
}

fn webp(b: &[u8]) -> Canonical {
    let mut c = Canonical::default();
    if b.len() < 16 || &b[0..4] != b"RIFF" || &b[8..12] != b"WEBP" {
        return c;
    }
    let mut i = 12usize;
    while i + 8 <= b.len() {
        let fourcc = &b[i..i + 4];
        let size = (b[i + 4] as usize)
            | ((b[i + 5] as usize) << 8)
            | ((b[i + 6] as usize) << 16)
            | ((b[i + 7] as usize) << 24);
        let padded = size + (size & 1);
        let chunk_end = i + 8 + padded;
        if chunk_end > b.len() {
            break;
        }
        let data = &b[i + 8..i + 8 + size];
        if fourcc == b"EXIF" {
            let tiff = data.strip_prefix(b"Exif\0\0".as_slice()).unwrap_or(data);
            c.exif.get_or_insert_with(|| tiff.to_vec());
        } else if fourcc == b"XMP " {
            c.xmp.get_or_insert_with(|| data.to_vec());
        } else if fourcc == b"ICCP" {
            c.icc.get_or_insert_with(|| data.to_vec());
        }
        i = chunk_end;
    }
    c
}

/// Decompress a PNG `iCCP` chunk to the raw ICC profile. Layout: profile name
/// (1..=79 bytes, null-terminated) + compression method (1 byte, must be 0 =
/// zlib) + the zlib-compressed profile. Returns `None` on a malformed or
/// non-zlib chunk (best-effort — the profile is then simply absent).
fn decode_iccp(data: &[u8]) -> Option<Vec<u8>> {
    let nul = data.iter().position(|&b| b == 0)?;
    if *data.get(nul + 1)? != 0 {
        return None; // only compression method 0 (zlib) is defined
    }
    let compressed = data.get(nul + 2..)?;
    miniz_oxide::inflate::decompress_to_vec_zlib(compressed).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seg(out: &mut Vec<u8>, marker: u8, payload: &[u8]) {
        out.push(0xFF);
        out.push(marker);
        out.extend_from_slice(&((payload.len() + 2) as u16).to_be_bytes());
        out.extend_from_slice(payload);
    }

    #[test]
    fn extracts_jpeg_exif_xmp_icc() {
        let mut j = vec![0xFF, 0xD8];
        let mut exif = b"Exif\0\0".to_vec();
        exif.extend_from_slice(b"II\x2a\x00\x08\x00\x00\x00"); // tiny TIFF header
        seg(&mut j, 0xE1, &exif);
        let mut xmp = XMP_SIG.to_vec();
        xmp.extend_from_slice(b"<x:xmpmeta/>");
        seg(&mut j, 0xE1, &xmp);
        let mut icc = b"ICC_PROFILE\0\x01\x01".to_vec();
        icc.extend_from_slice(b"icc-bytes");
        seg(&mut j, 0xE2, &icc);
        j.extend_from_slice(&[0xFF, 0xDA, 0x00, 0x02, 0xAA, 0xFF, 0xD9]);

        let c = extract(&j);
        assert!(c.exif.as_deref().unwrap().starts_with(b"II"));
        assert_eq!(c.xmp.as_deref(), Some(b"<x:xmpmeta/>".as_slice()));
        assert_eq!(c.icc.as_deref(), Some(b"icc-bytes".as_slice()));
    }

    #[test]
    fn extracts_webp_exif_strips_prefix() {
        let mut chunks = Vec::new();
        chunks.extend_from_slice(b"VP8X");
        chunks.extend_from_slice(&10u32.to_le_bytes());
        chunks.extend_from_slice(&[0x08, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
        let mut exif_chunk = b"Exif\0\0".to_vec();
        exif_chunk.extend_from_slice(b"MM\x00\x2a\x00\x00\x00\x08");
        chunks.extend_from_slice(b"EXIF");
        chunks.extend_from_slice(&(exif_chunk.len() as u32).to_le_bytes());
        chunks.extend_from_slice(&exif_chunk);
        if exif_chunk.len() & 1 == 1 {
            chunks.push(0);
        }

        let mut f = Vec::new();
        f.extend_from_slice(b"RIFF");
        f.extend_from_slice(&((4 + chunks.len()) as u32).to_le_bytes());
        f.extend_from_slice(b"WEBP");
        f.extend_from_slice(&chunks);

        let c = extract(&f);
        assert_eq!(
            c.exif.as_deref(),
            Some(b"MM\x00\x2a\x00\x00\x00\x08".as_slice())
        );
    }

    #[test]
    fn avif_nclx_gets_a_synthesized_icc() {
        fn boxx(t: &[u8; 4], body: &[u8]) -> Vec<u8> {
            let mut v = ((8 + body.len()) as u32).to_be_bytes().to_vec();
            v.extend_from_slice(t);
            v.extend_from_slice(body);
            v
        }
        let mut nclx = b"nclx".to_vec();
        nclx.extend_from_slice(&12u16.to_be_bytes()); // Display P3 primaries
        nclx.extend_from_slice(&13u16.to_be_bytes()); // sRGB transfer
        nclx.extend_from_slice(&1u16.to_be_bytes()); // matrix
        nclx.push(0x80);
        let iprp = boxx(b"iprp", &boxx(b"ipco", &boxx(b"colr", &nclx)));
        let mut meta_body = vec![0, 0, 0, 0];
        meta_body.extend_from_slice(&iprp);
        let file = [
            boxx(b"ftyp", b"avif\0\0\0\0avif"),
            boxx(b"meta", &meta_body),
        ]
        .concat();

        // No embedded profile, but the nclx code points yield a synthesised ICC.
        let icc = extract(&file).icc.expect("nclx → synthesised ICC");
        assert_eq!(&icc[36..40], b"acsp", "a valid ICC profile");
    }
}
