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
        return finish(dynimg, max_edge);
    }
    // AVIF/HEIF decode (AV1/HEVC) isn't bound yet — encode-only for now; the
    // app keeps its existing decoders. dav1d/HW decode land in a later stage.
    if matches!(
        crate::engine::format::detect(bytes),
        crate::engine::format::ImageFormat::Avif | crate::engine::format::ImageFormat::Heic
    ) {
        return Err(DarkError::Malformed("avif/heif decode not supported yet"));
    }
    let img = image::load_from_memory(bytes).map_err(|_| DarkError::Malformed("decode failed"))?;
    finish(img, max_edge)
}

/// Apply the optional preview downscale and flatten to RGBA.
fn finish(mut img: DynamicImage, max_edge: Option<u32>) -> Result<Decoded> {
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

    #[test]
    fn garbage_fails_cleanly() {
        assert!(decode(&[1, 2, 3, 4, 5, 6, 7, 8], None).is_err());
    }
}
