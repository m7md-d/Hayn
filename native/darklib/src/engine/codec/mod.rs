//! ImageCodec — pixel work (decode / encode / transcode) behind one interface.
//!
//! Stage 3a uses pure-Rust codecs (the `image` crate: PNG + JPEG) to prove the
//! interface end-to-end; they cross-compile trivially (no C). libwebp (3b) and
//! libavif/AV1 (3c) slot in behind THESE functions. Nothing here is wired into
//! the live compress flow yet — the quality-sensitive encoder choices land
//! before any migration (goal 6: never worse than today).

use std::io::Cursor;

use image::{
    codecs::jpeg::JpegEncoder, DynamicImage, ExtendedColorType, ImageEncoder, ImageFormat as ImgFmt,
};

use crate::engine::error::{DarkError, Result};

mod avif_dav1d;

/// A decoded image as 8-bit RGBA.
pub struct Decoded {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

/// What to encode to.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Target {
    /// JPEG at the given quality (1..=100); opaque (alpha dropped).
    Jpeg(u8),
    /// PNG (lossless).
    Png,
    /// WebP — lossy at the given quality (1..=100), or lossless.
    Webp { quality: u8, lossless: bool },
    /// AVIF at the given quality (1..=100), software (rav1e).
    Avif { quality: u8 },
}

/// Decode any supported container to RGBA, optionally downscaling so the long
/// edge is at most `max_edge` (for previews). The rule against downscaling the
/// SAVED output lives at the call site — this is a primitive.
pub fn decode(bytes: &[u8], max_edge: Option<u32>) -> Result<Decoded> {
    // Unified orientation: bake the source's EXIF orientation into the pixels so
    // every re-encode is upright (the encoders write no orientation tag),
    // preventing the classic flip. Single source of truth — never applied twice.
    let orientation = crate::engine::metadata::extract(bytes).orientation;

    // WebP isn't enabled in the `image` crate (lossy encode needs libwebp
    // anyway), so route WebP through libwebp.
    if crate::engine::format::detect(bytes) == crate::engine::format::ImageFormat::Webp {
        let img = webp::Decoder::new(bytes)
            .decode()
            .ok_or(DarkError::Malformed("webp decode failed"))?;
        // libwebp decodes opaque images as RGB (3 ch) and images with alpha as
        // RGBA (4 ch) — handle both, then let `finish` flatten to RGBA.
        let (w, h) = (img.width(), img.height());
        let data = img.to_vec();
        let px = (w as usize) * (h as usize);
        let dynimg = if px > 0 && data.len() == px * 4 {
            DynamicImage::ImageRgba8(
                image::RgbaImage::from_raw(w, h, data).ok_or(DarkError::Malformed("webp rgba"))?,
            )
        } else if px > 0 && data.len() == px * 3 {
            DynamicImage::ImageRgb8(
                image::RgbImage::from_raw(w, h, data).ok_or(DarkError::Malformed("webp rgb"))?,
            )
        } else {
            return Err(DarkError::Malformed("webp unexpected layout"));
        };
        return finish(dynimg, orientation, max_edge);
    }
    // AVIF: software AV1 decode via rav1d (royalty-free, pure Rust). HEIC stays a
    // hardware path — HEVC patents bar a bundled software decoder (CLAUDE.md §5).
    match crate::engine::format::detect(bytes) {
        crate::engine::format::ImageFormat::Avif => {
            let (w, h, rgba) = avif_dav1d::decode(bytes)?;
            let buf = image::RgbaImage::from_raw(w, h, rgba)
                .ok_or(DarkError::Malformed("avif rgba size mismatch"))?;
            return finish(DynamicImage::ImageRgba8(buf), orientation, max_edge);
        }
        crate::engine::format::ImageFormat::Heic => {
            return Err(DarkError::Malformed(
                "heic decode is hardware-only (HEVC patents)",
            ));
        }
        _ => {}
    }
    let img = image::load_from_memory(bytes).map_err(|_| DarkError::Malformed("decode failed"))?;
    finish(img, orientation, max_edge)
}

/// Bake EXIF orientation, apply the optional preview downscale, flatten to RGBA.
fn finish(mut img: DynamicImage, orientation: u16, max_edge: Option<u32>) -> Result<Decoded> {
    if let Some(o) = image::metadata::Orientation::from_exif(orientation as u8) {
        img.apply_orientation(o);
    }
    if let Some(m) = max_edge {
        if m > 0 && img.width().max(img.height()) > m {
            img = img.resize(m, m, image::imageops::FilterType::Lanczos3);
        }
    }
    let rgba = img.into_rgba8();
    Ok(Decoded {
        width: rgba.width(),
        height: rgba.height(),
        rgba: rgba.into_raw(),
    })
}

/// Encode a decoded image to `target`.
pub fn encode(img: &Decoded, target: Target) -> Result<Vec<u8>> {
    match target {
        Target::Avif { quality } => {
            use rgb::FromSlice;
            let res = ravif::Encoder::new()
                .with_quality(quality.clamp(1, 100) as f32)
                .with_speed(8)
                .encode_rgba(ravif::Img::new(
                    img.rgba.as_rgba(),
                    img.width as usize,
                    img.height as usize,
                ))
                .map_err(|_| DarkError::Malformed("avif encode failed"))?;
            Ok(res.avif_file)
        }
        Target::Webp { quality, lossless } => {
            // libwebp owns its output buffer; copy it out into a Vec.
            let enc = webp::Encoder::from_rgba(&img.rgba, img.width, img.height);
            let mem = if lossless {
                enc.encode_lossless()
            } else {
                enc.encode(quality.clamp(1, 100) as f32)
            };
            Ok(mem.to_vec())
        }
        Target::Png | Target::Jpeg(_) => {
            let buf = image::RgbaImage::from_raw(img.width, img.height, img.rgba.clone())
                .ok_or(DarkError::Malformed("rgba buffer size mismatch"))?;
            let dynimg = DynamicImage::ImageRgba8(buf);
            let mut out = Cursor::new(Vec::new());
            match target {
                Target::Jpeg(q) => {
                    let rgb = dynimg.to_rgb8();
                    JpegEncoder::new_with_quality(&mut out, q.clamp(1, 100))
                        .write_image(
                            rgb.as_raw(),
                            rgb.width(),
                            rgb.height(),
                            ExtendedColorType::Rgb8,
                        )
                        .map_err(|_| DarkError::Malformed("jpeg encode failed"))?;
                }
                _ => dynimg
                    .write_to(&mut out, ImgFmt::Png)
                    .map_err(|_| DarkError::Malformed("png encode failed"))?,
            }
            Ok(out.into_inner())
        }
    }
}

/// Decode → (optional resize) → encode to `target`.
pub fn transcode(bytes: &[u8], target: Target, max_edge: Option<u32>) -> Result<Vec<u8>> {
    encode(&decode(bytes, max_edge)?, target)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn solid_png(w: u32, h: u32, rgba: [u8; 4]) -> Vec<u8> {
        let img = image::RgbaImage::from_pixel(w, h, image::Rgba(rgba));
        let mut out = Cursor::new(Vec::new());
        DynamicImage::ImageRgba8(img)
            .write_to(&mut out, ImgFmt::Png)
            .unwrap();
        out.into_inner()
    }

    #[test]
    fn png_roundtrip_preserves_pixels() {
        let png = solid_png(8, 6, [10, 20, 30, 255]);
        let d = decode(&png, None).unwrap();
        assert_eq!((d.width, d.height), (8, 6));
        assert_eq!(&d.rgba[0..4], &[10, 20, 30, 255]);
        // PNG is lossless: re-encode → decode → identical pixels.
        let png2 = encode(&d, Target::Png).unwrap();
        let d2 = decode(&png2, None).unwrap();
        assert_eq!(d.rgba, d2.rgba);
    }

    #[test]
    fn transcode_png_to_jpeg_decodes_back() {
        let png = solid_png(16, 16, [200, 100, 50, 255]);
        let jpg = transcode(&png, Target::Jpeg(90), None).unwrap();
        assert_eq!(
            crate::engine::format::detect(&jpg),
            crate::engine::format::ImageFormat::Jpeg
        );
        let d = decode(&jpg, None).unwrap();
        assert_eq!((d.width, d.height), (16, 16));
        // Lossy, but a solid block stays close to the source colour.
        assert!((d.rgba[0] as i32 - 200).abs() < 12);
    }

    #[test]
    fn decode_resizes_to_max_edge() {
        let png = solid_png(100, 50, [0, 0, 0, 255]);
        let d = decode(&png, Some(20)).unwrap();
        assert!(d.width.max(d.height) <= 20);
        assert!(d.width > 0 && d.height > 0);
    }

    #[test]
    fn webp_lossless_roundtrip_preserves_pixels() {
        let png = solid_png(12, 9, [40, 80, 120, 255]);
        let d = decode(&png, None).unwrap();
        let wp = encode(
            &d,
            Target::Webp {
                quality: 100,
                lossless: true,
            },
        )
        .unwrap();
        assert_eq!(
            crate::engine::format::detect(&wp),
            crate::engine::format::ImageFormat::Webp
        );
        let back = decode(&wp, None).unwrap();
        assert_eq!((back.width, back.height), (12, 9));
        assert_eq!(back.rgba, d.rgba); // lossless WebP preserves pixels
    }

    #[test]
    fn webp_lossy_transcode_decodes_back() {
        let png = solid_png(16, 16, [200, 30, 90, 255]);
        let wp = transcode(
            &png,
            Target::Webp {
                quality: 80,
                lossless: false,
            },
            None,
        )
        .unwrap();
        assert_eq!(
            crate::engine::format::detect(&wp),
            crate::engine::format::ImageFormat::Webp
        );
        let d = decode(&wp, None).unwrap();
        assert_eq!((d.width, d.height), (16, 16));
    }

    #[test]
    fn encodes_valid_avif() {
        let png = solid_png(16, 16, [60, 120, 180, 255]);
        let d = decode(&png, None).unwrap();
        let avif = encode(&d, Target::Avif { quality: 70 }).unwrap();
        assert_eq!(
            crate::engine::format::detect(&avif),
            crate::engine::format::ImageFormat::Avif
        );
        assert!(avif.len() > 32, "produced a real AVIF container");
    }

    /// End-to-end: a real ravif-encoded AVIF decodes back via rav1d to the right
    /// dimensions and (lossily) the right colour — exercising the pure-Rust AV1
    /// decode path plus its YUV→RGB conversion.
    #[test]
    fn avif_roundtrips_through_rav1d_decode() {
        let png = solid_png(32, 24, [180, 60, 90, 255]);
        let d = decode(&png, None).unwrap();
        let avif = encode(&d, Target::Avif { quality: 90 }).unwrap();
        assert_eq!(
            crate::engine::format::detect(&avif),
            crate::engine::format::ImageFormat::Avif
        );

        let back = decode(&avif, None).unwrap();
        assert_eq!((back.width, back.height), (32, 24));
        // Lossy, but a solid block reconstructs close to the source colour.
        assert!(
            (back.rgba[0] as i32 - 180).abs() < 18,
            "R≈180 got {}",
            back.rgba[0]
        );
        assert!(
            (back.rgba[1] as i32 - 60).abs() < 18,
            "G≈60 got {}",
            back.rgba[1]
        );
        assert!(
            (back.rgba[2] as i32 - 90).abs() < 18,
            "B≈90 got {}",
            back.rgba[2]
        );
        assert_eq!(back.rgba[3], 255, "opaque alpha");
    }

    /// AVIF transparency: the alpha auxiliary item decodes back into the RGBA
    /// alpha channel (not silently flattened to opaque).
    #[test]
    fn avif_decode_recovers_alpha() {
        // Two alpha regions (left=64, right=192) so ravif emits a real alpha
        // auxiliary item and the values survive lossy compression.
        let mut rgba = vec![0u8; 16 * 16 * 4];
        for y in 0..16usize {
            for x in 0..16usize {
                let i = y * 16 + x;
                rgba[i * 4] = 200;
                rgba[i * 4 + 1] = 100;
                rgba[i * 4 + 2] = 50;
                rgba[i * 4 + 3] = if x < 8 { 64 } else { 192 };
            }
        }
        let d = Decoded {
            width: 16,
            height: 16,
            rgba,
        };
        let avif = encode(&d, Target::Avif { quality: 90 }).unwrap();

        let back = decode(&avif, None).unwrap();
        assert_eq!((back.width, back.height), (16, 16));
        let a_left = back.rgba[(8 * 16 + 2) * 4 + 3];
        let a_right = back.rgba[(8 * 16 + 13) * 4 + 3];
        assert!(
            (a_left as i32 - 64).abs() < 24,
            "left alpha ~64 got {a_left}"
        );
        assert!(
            (a_right as i32 - 192).abs() < 24,
            "right alpha ~192 got {a_right}"
        );
    }

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

    /// Insert an `eXIf` chunk (a minimal little-endian TIFF carrying just the
    /// Orientation tag) into a freshly-encoded PNG, before its trailing IEND.
    fn png_with_orientation(base_png: &[u8], orientation: u8) -> Vec<u8> {
        let mut tiff = b"II\x2a\x00\x08\x00\x00\x00".to_vec();
        tiff.extend_from_slice(&1u16.to_le_bytes()); // 1 entry
        tiff.extend_from_slice(&0x0112u16.to_le_bytes()); // Orientation
        tiff.extend_from_slice(&3u16.to_le_bytes()); // SHORT
        tiff.extend_from_slice(&1u32.to_le_bytes()); // count
        tiff.extend_from_slice(&(orientation as u32).to_le_bytes()); // value (in field)
        tiff.extend_from_slice(&0u32.to_le_bytes()); // next IFD = 0

        let mut typed = b"eXIf".to_vec();
        typed.extend_from_slice(&tiff);
        let mut chunk = (tiff.len() as u32).to_be_bytes().to_vec();
        chunk.extend_from_slice(&typed);
        chunk.extend_from_slice(&crc32(&typed).to_be_bytes());

        let cut = base_png.len() - 12; // IEND is the final 12 bytes
        let mut out = base_png[..cut].to_vec();
        out.extend_from_slice(&chunk);
        out.extend_from_slice(&base_png[cut..]);
        out
    }

    #[test]
    fn decode_bakes_png_exif_orientation() {
        // 2x1, orientation 6 (rotate 90° CW) → decoded upright as 1x2.
        let png = png_with_orientation(&solid_png(2, 1, [255, 0, 0, 255]), 6);
        let d = decode(&png, None).unwrap();
        assert_eq!((d.width, d.height), (1, 2));
    }

    #[test]
    fn garbage_fails_cleanly() {
        assert!(decode(&[1, 2, 3, 4, 5, 6, 7, 8], None).is_err());
    }

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

    /// End-to-end: a REAL libwebp encode carries EXIF/XMP through the mux and the
    /// muxed output is still a decodable WebP at the original size.
    #[test]
    fn webp_inject_carries_meta_through_a_real_encode() {
        use crate::engine::metadata::{extract, inject, Canonical};
        let png = solid_png(16, 16, [10, 150, 200, 255]);
        let d = decode(&png, None).unwrap();
        let wp = encode(
            &d,
            Target::Webp {
                quality: 80,
                lossless: false,
            },
        )
        .unwrap();
        assert!(extract(&wp).exif.is_none(), "fresh WebP has no metadata");

        let meta = Canonical {
            exif: Some(tiff_orientation(6)),
            xmp: Some(b"<x:xmpmeta>w</x:xmpmeta>".to_vec()),
            ..Default::default()
        };
        let out = inject(&wp, &meta);
        assert_eq!(
            crate::engine::format::detect(&out),
            crate::engine::format::ImageFormat::Webp
        );

        let back = extract(&out);
        assert!(back.exif.is_some(), "EXIF carried into a real WebP");
        assert_eq!(back.orientation, 1, "orientation normalised");
        assert!(back.xmp.is_some(), "XMP carried");

        // Still a valid, decodable WebP at the same dimensions.
        let d2 = decode(&out, None).unwrap();
        assert_eq!((d2.width, d2.height), (16, 16));
    }

    /// End-to-end: a REAL ravif-encoded AVIF gains EXIF + XMP items (ISOBMFF
    /// add-item) that extract cleanly, while staying a valid single-mdat AVIF.
    #[test]
    fn avif_inject_adds_exif_and_xmp_through_a_real_encode() {
        use crate::engine::metadata::{extract, inject, Canonical};
        let png = solid_png(16, 16, [30, 60, 90, 255]);
        let d = decode(&png, None).unwrap();
        let avif = encode(&d, Target::Avif { quality: 70 }).unwrap();
        assert_eq!(
            crate::engine::format::detect(&avif),
            crate::engine::format::ImageFormat::Avif
        );
        let before = extract(&avif);
        assert!(
            before.exif.is_none() && before.xmp.is_none(),
            "ravif emits no metadata"
        );

        let meta = Canonical {
            exif: Some(tiff_orientation(6)),
            xmp: Some(b"<x:xmpmeta>a</x:xmpmeta>".to_vec()),
            ..Default::default()
        };
        let out = inject(&avif, &meta);
        assert!(out.len() > avif.len(), "items added");
        assert_eq!(
            crate::engine::format::detect(&out),
            crate::engine::format::ImageFormat::Avif
        );

        let back = extract(&out);
        assert!(back.exif.is_some(), "EXIF item added to the AVIF");
        assert_eq!(back.orientation, 1, "orientation normalised");
        assert!(back.xmp.is_some(), "XMP item added to the AVIF");
    }

    /// A REAL ravif AVIF (carrying nclx, no ICC) gains an embedded ICC profile
    /// (colr/prof property + ipma association) that extracts back exactly.
    #[test]
    fn avif_inject_carries_icc_through_a_real_encode() {
        use crate::engine::metadata::{extract, inject, Canonical};
        let png = solid_png(16, 16, [70, 30, 120, 255]);
        let d = decode(&png, None).unwrap();
        let avif = encode(&d, Target::Avif { quality: 70 }).unwrap();
        assert!(
            extract(&avif).icc.is_none(),
            "ravif emits nclx, no ICC profile"
        );

        let icc = b"fake-display-p3-profile-bytes-0123456789".to_vec();
        let meta = Canonical {
            icc: Some(icc.clone()),
            ..Default::default()
        };
        let out = inject(&avif, &meta);
        assert!(out.len() > avif.len(), "colr/prof property added");
        assert_eq!(
            crate::engine::format::detect(&out),
            crate::engine::format::ImageFormat::Avif
        );
        assert_eq!(
            extract(&out).icc.as_deref(),
            Some(icc.as_slice()),
            "ICC profile carried into the AVIF"
        );
    }
}
