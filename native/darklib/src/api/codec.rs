//! FFI surface for the ImageCodec (pixel work). Heavy → async (runs off the
//! Dart isolate on the FRB worker pool — CLAUDE.md §4).
//!
//! Stage 3a: PNG/JPEG transcode (pure-Rust). More formats slot in behind the
//! same call as the codec layer grows.

use crate::engine::codec;

/// Target encode format for [`transcode`].
pub enum CodecFormat {
    Jpeg,
    Png,
    Webp,
    WebpLossless,
    Avif,
}

/// Decode → optional downscale (long edge ≤ `max_edge`; 0 = keep original size)
/// → encode to `format` at `quality` (1..=100; ignored for PNG). Throws on a
/// container the codec layer can't handle yet.
fn target_of(format: CodecFormat, quality: u32) -> codec::Target {
    let q = quality.clamp(1, 100) as u8;
    match format {
        CodecFormat::Jpeg => codec::Target::Jpeg(q),
        CodecFormat::Png => codec::Target::Png,
        CodecFormat::Webp => codec::Target::Webp {
            quality: q,
            lossless: false,
        },
        CodecFormat::WebpLossless => codec::Target::Webp {
            quality: 100,
            lossless: true,
        },
        CodecFormat::Avif => codec::Target::Avif { quality: q },
    }
}

/// Decode → optional downscale → encode at `quality` (1..=100; PNG ignores it).
/// Metadata is NOT carried — use [`transcode_keep_metadata`] for that. Throws on
/// a container the codec layer can't handle yet.
pub fn transcode(
    bytes: Vec<u8>,
    format: CodecFormat,
    quality: u32,
    max_edge: u32,
) -> Result<Vec<u8>, String> {
    let edge = if max_edge == 0 { None } else { Some(max_edge) };
    codec::transcode(&bytes, target_of(format, quality), edge).map_err(|e| e.to_string())
}

/// Like [`transcode`], but carries the source's EXIF/XMP/ICC into the output
/// where supported (orientation normalised — the pixels are baked upright on
/// decode). Formats without an injector yet return the bytes without metadata.
pub fn transcode_keep_metadata(
    bytes: Vec<u8>,
    format: CodecFormat,
    quality: u32,
    max_edge: u32,
) -> Result<Vec<u8>, String> {
    let meta = crate::engine::metadata::extract(&bytes);
    let edge = if max_edge == 0 { None } else { Some(max_edge) };
    let out =
        codec::transcode(&bytes, target_of(format, quality), edge).map_err(|e| e.to_string())?;
    Ok(crate::engine::metadata::inject(&out, &meta))
}
