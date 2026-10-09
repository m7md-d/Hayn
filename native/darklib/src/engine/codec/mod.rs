//! ImageCodec — pixel work (decode / encode / transcode) behind one interface.
//!
//! Decoders: `image` (PNG/JPEG), libwebp (WebP), rav1d (AVIF — colour, alpha,
//! orientation, ImageGrid). Encoders: `image`, libwebp, rav1e/ravif (AVIF, with
//! automatic ImageGrid tiling for huge opaque images). JPEG → JPEG also goes
//! row by row through libjpeg-turbo's code (`jpeg_stream`, Hayn RUN-01 step 6),
//! with memory near the compressed size. HEIC is never coded in
//! software (HEVC patents) — platform hardware owns it. `transcode` optionally
//! carries EXIF/XMP/ICC and, for AVIF→AVIF, the ISO 21496-1 HDR gain map; it
//! reports what happened to a gain map in [`HdrOutcome`].

use std::io::Cursor;

use image::{
    codecs::jpeg::JpegEncoder, DynamicImage, ExtendedColorType, ImageEncoder, ImageFormat as ImgFmt,
};

use crate::engine::error::{DarkError, Result};

mod avif_dav1d;
pub mod heif_alpha;
mod huffman;
pub(crate) mod jpeg_stream;
pub mod region;

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
    /// AVIF at the given quality (1..=100), software (rav1e). `depth` is the
    /// bit depth the user chose, 8 or 10; `None` keeps the encoder's default,
    /// 10, which the user decided stays (Hayn IMG-23).
    Avif { quality: u8, depth: Option<u8> },
}

/// Largest image DarkLib decodes: 256 MP, about 1 GiB of RGBA8, which every
/// real camera fits (200 MP included). A file claiming more is refused from
/// its header before any pixel buffer is allocated (Hayn RUN-01); the AVIF
/// grid canvas has the same ceiling. It is a fixed ceiling, not a budget for
/// the device's memory, which is not measured yet.
pub const MAX_DECODE_PIXELS: u64 = 256 * 1024 * 1024;

/// Pixel dimensions from the container header, without decoding pixels.
/// `None` when the header does not say.
pub fn header_dimensions(bytes: &[u8]) -> Option<(u32, u32)> {
    use crate::engine::format::{detect, ImageFormat};
    match detect(bytes) {
        ImageFormat::Webp => webp::BitstreamFeatures::new(bytes).map(|f| (f.width(), f.height())),
        ImageFormat::Avif | ImageFormat::Heic => {
            crate::engine::metadata::isobmff::primary_extent(bytes)
        }
        ImageFormat::Jpeg => jpeg_dimensions(bytes),
        _ => image::ImageReader::new(Cursor::new(bytes))
            .with_guessed_format()
            .ok()?
            .into_dimensions()
            .ok(),
    }
}

/// Width and height from a JPEG's frame header (any SOFn), walking the marker
/// segments from SOI. `None` when no frame header precedes the scan.
fn jpeg_dimensions(b: &[u8]) -> Option<(u32, u32)> {
    let mut i = 2usize;
    loop {
        if *b.get(i)? != 0xFF {
            return None;
        }
        let marker = *b.get(i + 1)?;
        if marker == 0xFF {
            i += 1; // fill byte
            continue;
        }
        if marker == 0xDA || marker == 0xD9 {
            return None;
        }
        let len = u16::from_be_bytes([*b.get(i + 2)?, *b.get(i + 3)?]) as usize;
        // SOF0..SOF15, except DHT (C4), JPG (C8) and DAC (CC).
        if (0xC0..=0xCF).contains(&marker) && !matches!(marker, 0xC4 | 0xC8 | 0xCC) {
            let h = u16::from_be_bytes([*b.get(i + 5)?, *b.get(i + 6)?]) as u32;
            let w = u16::from_be_bytes([*b.get(i + 7)?, *b.get(i + 8)?]) as u32;
            return Some((w, h));
        }
        i = i.checked_add(2 + len)?;
    }
}

/// Refuses a decode past [`MAX_DECODE_PIXELS`] from the header alone.
fn check_decode_budget(bytes: &[u8]) -> Result<()> {
    let (w, h) = header_dimensions(bytes).ok_or(DarkError::Malformed("no dimensions"))?;
    if w == 0 || h == 0 {
        return Err(DarkError::Malformed("empty image"));
    }
    if (w as u64) * (h as u64) > MAX_DECODE_PIXELS {
        return Err(DarkError::TooLarge);
    }
    Ok(())
}

/// Decode any supported container to RGBA, optionally downscaling so the long
/// edge is at most `max_edge` (for previews). The rule against downscaling the
/// SAVED output lives at the call site — this is a primitive. The full image
/// is decoded first (then scaled), so the budget is on the source's size.
pub fn decode(bytes: &[u8], max_edge: Option<u32>) -> Result<Decoded> {
    check_decode_budget(bytes)?;
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
    // The image crate's own default allocation limit (512 MiB) would refuse a
    // 200 MP JPEG as a decode failure; align it with the budget instead.
    let mut limits = image::Limits::default();
    limits.max_alloc = Some(MAX_DECODE_PIXELS * 4);
    let mut reader = image::ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|_| DarkError::Malformed("decode failed"))?;
    reader.limits(limits);
    let img = reader
        .decode()
        .map_err(|_| DarkError::Malformed("decode failed"))?;
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

/// Opaque, upright 8-bit RGB PNG of `bytes` composited over white: what a JPEG
/// shows for a transparent source (user decision, 2026-09-29). The EXIF
/// orientation is baked in by [`decode`]; the budget applies. Replaces the
/// pure-Dart composite, which took seconds per 12 MP image (Hayn PERF-01).
pub fn flatten_on_white(bytes: &[u8]) -> Result<Vec<u8>> {
    let img = decode(bytes, None)?;
    let mut rgb = Vec::with_capacity(img.rgba.len() / 4 * 3);
    for px in img.rgba.as_chunks::<4>().0 {
        let a = px[3] as u32;
        for &c in &px[..3] {
            // c·a + white·(1 − a), rounded, in 0..=255.
            rgb.push(((c as u32 * a + 255 * (255 - a) + 127) / 255) as u8);
        }
    }
    let mut out = Cursor::new(Vec::new());
    image::codecs::png::PngEncoder::new(&mut out)
        .write_image(&rgb, img.width, img.height, ExtendedColorType::Rgb8)
        .map_err(|_| DarkError::Malformed("png encode failed"))?;
    Ok(out.into_inner())
}

/// Above this many pixels an opaque AVIF encode goes tile-by-tile as an
/// ImageGrid: bounded memory at FULL resolution — never a downscale (DarkLib §5).
const AVIF_GRID_THRESHOLD_PX: u64 = 16 * 1024 * 1024;
/// Grid tile edge. 1024² keeps the tile count low (200 MP ≈ 196 tiles) while
/// each tile encode stays small and fast.
const AVIF_GRID_TILE: u32 = 1024;

/// Encode a decoded image to `target`.
pub fn encode(img: &Decoded, target: Target) -> Result<Vec<u8>> {
    match target {
        Target::Avif { quality, depth } => {
            // Huge opaque images: encode as an ImageGrid, one tile at a time
            // (peak memory ≈ source + one tile). Images with transparency keep
            // the single-item path for now (a grid alpha plane is a later step);
            // any grid failure falls back to the proven single-item encode.
            let px = (img.width as u64) * (img.height as u64);
            if px > AVIF_GRID_THRESHOLD_PX
                && img.rgba.as_chunks::<4>().0.iter().all(|p| p[3] == 255)
            {
                if let Ok(out) = encode_avif_grid(img, quality, depth, AVIF_GRID_TILE) {
                    return Ok(out);
                }
            }
            encode_avif_single(img, quality, depth)
        }
        Target::Webp { quality, lossless } => {
            // `encode`/`encode_lossless` of the webp crate unwrap libwebp's
            // error, so an image it refuses panicked (Hayn IMG-20); the
            // advanced call returns it. A very large lossy image overflows
            // the 512 KiB first partition (prediction modes):
            // `partition_limit` lets libwebp lower quality just enough to fit
            // instead of failing, and changes nothing for an image that fits.
            let mut config =
                webp::WebPConfig::new().map_err(|_| DarkError::Malformed("webp config failed"))?;
            config.lossless = lossless as i32;
            config.alpha_compression = (!lossless) as i32;
            config.quality = if lossless {
                75.0
            } else {
                quality.clamp(1, 100) as f32
            };
            config.partition_limit = 100;
            // libwebp owns its output buffer; copy it out into a Vec.
            webp::Encoder::from_rgba(&img.rgba, img.width, img.height)
                .encode_advanced(&config)
                .map(|mem| mem.to_vec())
                .map_err(|_| DarkError::Malformed("webp encode failed"))
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

/// Single-item AVIF encode via ravif (rav1e), at `depth` (8 or 10) or the
/// encoder's default (10) when `None`.
fn encode_avif_single(img: &Decoded, quality: u8, depth: Option<u8>) -> Result<Vec<u8>> {
    use rgb::FromSlice;
    let depth = depth.map(|d| if d >= 10 { 10 } else { 8 });
    let res = ravif::Encoder::new()
        .with_quality(quality.clamp(1, 100) as f32)
        .with_depth(depth)
        .with_speed(8)
        .encode_rgba(ravif::Img::new(
            img.rgba.as_rgba(),
            img.width as usize,
            img.height as usize,
        ))
        .map_err(|_| DarkError::Malformed("avif encode failed"))?;
    Ok(res.avif_file)
}

/// Tiled AVIF encode: split into `tile`×`tile` blocks (edges replicated so every
/// tile is full-size, as the grid spec requires — the canvas crops them back),
/// encode each block independently, and assemble an ImageGrid container. Peak
/// memory ≈ the source buffer + one tile, at full output resolution.
fn encode_avif_grid(img: &Decoded, quality: u8, depth: Option<u8>, tile: u32) -> Result<Vec<u8>> {
    use crate::engine::metadata::isobmff;
    let bad = || DarkError::Malformed("avif grid encode failed");
    let (w, h) = (img.width as usize, img.height as usize);
    let t = tile as usize;
    if t == 0 || w == 0 || h == 0 {
        return Err(bad());
    }
    let (cols, rows) = (w.div_ceil(t), h.div_ceil(t));

    let mut tiles = Vec::with_capacity(rows * cols);
    let mut av1c: Option<Vec<u8>> = None;
    let mut block = vec![0u8; t * t * 4];
    for r in 0..rows {
        for c in 0..cols {
            let (x0, y0) = (c * t, r * t);
            for ty in 0..t {
                let sy = (y0 + ty).min(h - 1); // replicate the bottom edge
                let src_row = sy * w;
                for tx in 0..t {
                    let sx = (x0 + tx).min(w - 1); // replicate the right edge
                    let s = (src_row + sx) * 4;
                    let d = (ty * t + tx) * 4;
                    block[d..d + 4].copy_from_slice(&img.rgba[s..s + 4]);
                }
            }
            let avif = encode_avif_single(
                &Decoded {
                    width: tile,
                    height: tile,
                    rgba: block.clone(),
                },
                quality,
                depth,
            )?;
            if av1c.is_none() {
                av1c = isobmff::av1c_raw(&avif);
            }
            tiles.push(isobmff::extract_primary_av1(&avif).ok_or_else(bad)?);
        }
    }
    let spec = isobmff::GridSpec {
        rows: rows as u32,
        cols: cols as u32,
        tile_w: tile,
        tile_h: tile,
        width: img.width,
        height: img.height,
    };
    isobmff::build_grid_avif(&spec, &av1c.ok_or_else(bad)?, &tiles).ok_or_else(bad)
}

/// What a transcode did with an HDR gain map. The HDR policy (user decision,
/// 2026-09-28): keep HDR where the path is proven, otherwise encode the SDR
/// base without asking. The caller records anything but `None`/`GainMapKept`.
/// Keeping is proven by ImageIO reading the rebuilt ISO gain map (IMG-10).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HdrOutcome {
    /// No gain map was recognised in the source.
    None,
    /// The gain map was rebuilt next to the re-encoded base.
    GainMapKept,
    /// The target, resize or orientation cannot carry it; SDR base only.
    GainMapDropped,
    /// Keeping was attempted and failed; SDR base only.
    GainMapKeepFailed,
}

pub struct Transcoded {
    pub bytes: Vec<u8>,
    pub hdr: HdrOutcome,
    /// The metadata kinds the source held that the output could not (Hayn
    /// RV-04): the caller records them.
    pub dropped: Vec<crate::engine::metadata::MetaKind>,
}

/// Decode → (optional resize) → encode to `target`. With `keep_metadata` the
/// source's EXIF/XMP/ICC are carried (orientation baked into the pixels).
/// Without it the private metadata goes but the ICC profile stays: it says
/// what the pixel values mean, and dropping it would recolour a P3 image as
/// sRGB (Hayn IMG-08). An
/// ISO 21496-1 gain map survives a full-resolution, unrotated AVIF→AVIF
/// convert (with or without metadata: it is image data, not private data);
/// elsewhere the SDR base is encoded and the outcome says so. PQ/HLG is
/// refused: this engine decodes to RGBA8 and has no tone mapper, and
/// sRGB-tagged PQ samples would be a wrong image, not an SDR one.
pub fn transcode(
    bytes: &[u8],
    target: Target,
    max_edge: Option<u32>,
    keep_metadata: bool,
) -> Result<Transcoded> {
    use crate::engine::inspect::{inspect, Presence};
    use crate::engine::metadata::{self, isobmff, Canonical};

    let facts = inspect(bytes);
    if facts.transfer.is_direct_hdr() {
        return Err(DarkError::PreservationRequired("hdr_transfer_unsupported"));
    }
    let meta = metadata::extract(bytes);
    let carried = if keep_metadata {
        meta.clone()
    } else {
        Canonical {
            icc: meta.icc.clone(),
            ..Canonical::default()
        }
    };

    let mut hdr = HdrOutcome::None;
    if facts.gain_map == Presence::Present {
        // irot/imir or EXIF rotation would be baked into the base but not into
        // the gain map, misaligning them.
        let keepable = max_edge.is_none()
            && crate::engine::format::detect(bytes) == crate::engine::format::ImageFormat::Avif
            && matches!(meta.orientation, 0 | 1)
            && isobmff::read_orientation(bytes).is_none();
        hdr = HdrOutcome::GainMapDropped;
        if let (true, Target::Avif { quality, depth }) = (keepable, target) {
            // The container is built here, so the metadata goes through the
            // model's step to a container as an inject's would.
            let metadata::carry::Prepared { ready, dropped, .. } =
                metadata::carry::prepared(&carried, false);
            match transcode_hdr_avif(bytes, quality, depth, &ready) {
                Some(out) => {
                    return Ok(Transcoded {
                        bytes: out,
                        hdr: HdrOutcome::GainMapKept,
                        dropped,
                    })
                }
                None => hdr = HdrOutcome::GainMapKeepFailed,
            }
        }
    }

    let out = encode(&decode(bytes, max_edge)?, target)?;
    let carried = metadata::inject_reporting(&out, &carried);
    Ok(Transcoded {
        bytes: carried.bytes,
        hdr,
        dropped: carried.dropped,
    })
}

/// Carry an ISO 21496-1 gain map through an AVIF→AVIF re-encode: decode + encode
/// the base and the gain-map image separately (same geometry and colour, so the
/// map still describes the base), copy the tmap metadata and its alternate
/// properties verbatim, and build the container from scratch. `None` when the
/// graph is unreadable or any step fails; the caller encodes the base alone.
fn transcode_hdr_avif(
    bytes: &[u8],
    quality: u8,
    depth: Option<u8>,
    meta: &crate::engine::metadata::Canonical,
) -> Option<Vec<u8>> {
    use crate::engine::metadata::isobmff;
    let tmap = isobmff::read_tmap(bytes)?;
    let coded = |rgba_img: &Decoded| -> Option<isobmff::CodedItem> {
        let avif = encode_avif_single(rgba_img, quality, depth).ok()?;
        Some(isobmff::CodedItem {
            payload: isobmff::extract_primary_av1(&avif)?,
            av1c_box: isobmff::av1c_raw(&avif)?,
            width: rgba_img.width,
            height: rgba_img.height,
        })
    };
    let base = coded(&decode(bytes, None).ok()?)?;
    let (gw, gh, grgba) = avif_dav1d::decode_item(bytes, tmap.gainmap_id, 0).ok()?;
    let gm = coded(&Decoded {
        width: gw,
        height: gh,
        rgba: grgba,
    })?;
    let out = isobmff::build_hdr_avif(&base, &gm, &tmap.payload, &tmap.alt_props, meta)?;
    // Self-check only; the independent proof is ImageIO (tests + IMG-10).
    (isobmff::read_tmap(&out)?.payload == tmap.payload).then_some(out)
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

    /// The composite the phone test checks: (80,120,160) at alpha 64 over
    /// white is (211,221,231); an opaque pixel is untouched; no alpha remains.
    #[test]
    fn flatten_on_white_composites_and_drops_alpha() {
        let src = Decoded {
            width: 2,
            height: 1,
            rgba: vec![80, 120, 160, 64, 10, 20, 30, 255],
        };
        let png = encode(&src, Target::Png).unwrap();
        let flat = flatten_on_white(&png).unwrap();
        let out = decode(&flat, None).unwrap();
        assert_eq!(&out.rgba[..4], &[211, 221, 231, 255]);
        assert_eq!(&out.rgba[4..], &[10, 20, 30, 255]);
        assert_eq!(
            crate::engine::inspect::inspect(&flat).alpha,
            crate::engine::inspect::Presence::Absent
        );
    }

    #[test]
    fn transcode_png_to_jpeg_decodes_back() {
        let png = solid_png(16, 16, [200, 100, 50, 255]);
        let jpg = transcode(&png, Target::Jpeg(90), None, false)
            .unwrap()
            .bytes;
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
            false,
        )
        .unwrap()
        .bytes;
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
        let avif = encode(
            &d,
            Target::Avif {
                quality: 70,
                depth: None,
            },
        )
        .unwrap();
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
        let avif = encode(
            &d,
            Target::Avif {
                quality: 90,
                depth: None,
            },
        )
        .unwrap();
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
        let avif = encode(
            &d,
            Target::Avif {
                quality: 90,
                depth: None,
            },
        )
        .unwrap();

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

    /// Tiled (ImageGrid) AVIF encode round-trips through our own grid decoder:
    /// a 40×24 image with 16×16 tiles → 2 rows × 3 cols, right/bottom tiles
    /// edge-padded on encode and cropped back by the canvas on decode.
    #[test]
    fn avif_grid_encode_roundtrips() {
        let (w, h) = (40usize, 24usize);
        let mut rgba = vec![0u8; w * h * 4];
        for y in 0..h {
            for x in 0..w {
                let o = (y * w + x) * 4;
                // Left half red, right half blue — spans tile boundaries.
                let c: [u8; 4] = if x < w / 2 {
                    [220, 30, 30, 255]
                } else {
                    [30, 30, 220, 255]
                };
                rgba[o..o + 4].copy_from_slice(&c);
            }
        }
        let img = Decoded {
            width: w as u32,
            height: h as u32,
            rgba,
        };

        let avif = encode_avif_grid(&img, 90, None, 16).expect("grid encode");
        assert_eq!(
            crate::engine::format::detect(&avif),
            crate::engine::format::ImageFormat::Avif
        );

        let back = decode(&avif, None).expect("own grid decoder reads it");
        assert_eq!((back.width, back.height), (40, 24), "canvas crops padding");
        let px = |x: usize, y: usize| -> [u8; 3] {
            let o = (y * 40 + x) * 4;
            [back.rgba[o], back.rgba[o + 1], back.rgba[o + 2]]
        };
        // Sample inside each region, away from the lossy boundary.
        let left = px(8, 12);
        let right = px(34, 12);
        assert!(left[0] > 150 && left[2] < 110, "left red, got {left:?}");
        assert!(
            right[2] > 150 && right[0] < 110,
            "right blue, got {right:?}"
        );
    }

    /// A synthetic HDR AVIF converted AVIF→AVIF keeps its gain map: the tmap
    /// metadata byte-identical, the gain-map image re-encoded at its own
    /// resolution, EXIF carried. A resize encodes the SDR base. Our own parser
    /// The bit depth the user chose reaches the AV1 stream (`av1C`
    /// high_bitdepth), single item and grid; no choice keeps the encoder's
    /// default, 10 (Hayn IMG-23: the user keeps 10 and offers both).
    #[test]
    fn avif_depth_follows_the_choice() {
        fn high_bitdepth(avif: &[u8]) -> bool {
            let at = avif.windows(4).position(|w| w == b"av1C").unwrap();
            avif[at + 6] & 0x40 != 0
        }
        let img = Decoded {
            width: 24,
            height: 16,
            rgba: [90u8, 140, 200, 255].repeat(24 * 16),
        };
        for (depth, ten) in [(None, true), (Some(8), false), (Some(10), true)] {
            let single = encode(&img, Target::Avif { quality: 80, depth }).unwrap();
            assert_eq!(high_bitdepth(&single), ten, "single item, {depth:?}");
            let grid = encode_avif_grid(&img, 80, depth, 16).unwrap();
            assert_eq!(high_bitdepth(&grid), ten, "grid, {depth:?}");
        }
    }

    /// only; ImageIO checks the real fixture (tests/preservation.rs).
    #[test]
    fn hdr_avif_gainmap_survives_convert() {
        use crate::engine::metadata::{extract, isobmff, Canonical};

        let coded = |w: u32, h: u32, rgba: [u8; 4]| -> isobmff::CodedItem {
            let px: Vec<u8> = std::iter::repeat_n(rgba, (w * h) as usize)
                .flatten()
                .collect();
            let avif = encode_avif_single(
                &Decoded {
                    width: w,
                    height: h,
                    rgba: px,
                },
                90,
                None,
            )
            .unwrap();
            isobmff::CodedItem {
                payload: isobmff::extract_primary_av1(&avif).unwrap(),
                av1c_box: isobmff::av1c_raw(&avif).unwrap(),
                width: w,
                height: h,
            }
        };
        let base = coded(32, 24, [230, 140, 40, 255]); // orange base
        let gm = coded(16, 12, [160, 160, 160, 255]); // half-res grey gain map
        let curve = b"ISO-21496-1-gainmap-curve-params".to_vec();
        let meta = Canonical {
            exif: Some(tiff_orientation(1)),
            ..Default::default()
        };
        let src = isobmff::build_hdr_avif(&base, &gm, &curve, &[], &meta).expect("builds");

        // The source reads back as a well-formed HDR AVIF.
        assert_eq!(
            crate::engine::format::detect(&src),
            crate::engine::format::ImageFormat::Avif
        );
        assert!(isobmff::has_gainmap(&src), "tmap detected");
        let t = isobmff::read_tmap(&src).expect("tmap readable");
        assert_eq!(t.payload, curve);
        let d = decode(&src, None).expect("base decodes");
        assert_eq!((d.width, d.height), (32, 24));
        assert!(extract(&src).exif.is_some(), "EXIF item present");

        let done = transcode(
            &src,
            Target::Avif {
                quality: 85,
                depth: None,
            },
            None,
            true,
        )
        .expect("convert");
        assert_eq!(done.hdr, HdrOutcome::GainMapKept);
        let out = done.bytes;
        let t2 = isobmff::read_tmap(&out).expect("tmap in output");
        assert_eq!(t2.payload, curve, "curve metadata carried verbatim");
        assert!(extract(&out).exif.is_some(), "EXIF carried");
        let d2 = decode(&out, None).expect("output base decodes");
        assert_eq!((d2.width, d2.height), (32, 24));
        assert!(
            (d2.rgba[0] as i32 - 230).abs() < 25,
            "base colour ≈ orange, got {}",
            d2.rgba[0]
        );
        let (gw, gh, grgba) =
            avif_dav1d::decode_item(&out, t2.gainmap_id, 0).expect("gain map decodes");
        assert_eq!((gw, gh), (16, 12), "gain map keeps its own resolution");
        assert!(
            (grgba[0] as i32 - 160).abs() < 25,
            "gain map value ≈ grey, got {}",
            grgba[0]
        );
        let small = transcode(
            &src,
            Target::Avif {
                quality: 85,
                depth: None,
            },
            Some(16),
            true,
        )
        .unwrap();
        assert_eq!(small.hdr, HdrOutcome::GainMapDropped);
        assert_eq!(decode(&small.bytes, None).unwrap().width, 16);
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

    /// `irot`/`imir` named as an EXIF code turn pixels exactly as the `image`
    /// crate turns them for that code (RUN-01: the tiled HEIC encoder hands
    /// the code to Android).
    #[test]
    fn heif_transforms_match_their_exif_codes() {
        use crate::engine::metadata::isobmff::exif_orientation;
        let px: Vec<u8> = (0..6u8).flat_map(|i| [i, 0, 0, 255]).collect();
        for angle in 0..4 {
            for mirror in [None, Some(0), Some(1)] {
                let (w, h, heif) =
                    avif_dav1d::apply_orientation(3, 2, px.clone(), angle, mirror, 4);
                let code = exif_orientation(angle, mirror);
                let mut img =
                    DynamicImage::ImageRgba8(image::RgbaImage::from_raw(3, 2, px.clone()).unwrap());
                img.apply_orientation(image::metadata::Orientation::from_exif(code).unwrap());
                assert_eq!((w, h), (img.width(), img.height()), "{angle} {mirror:?}");
                assert_eq!(
                    heif,
                    img.to_rgba8().into_raw(),
                    "{angle} {mirror:?} -> {code}"
                );
            }
        }
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
        let avif = encode(
            &d,
            Target::Avif {
                quality: 70,
                depth: None,
            },
        )
        .unwrap();
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
        let avif = encode(
            &d,
            Target::Avif {
                quality: 70,
                depth: None,
            },
        )
        .unwrap();
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
