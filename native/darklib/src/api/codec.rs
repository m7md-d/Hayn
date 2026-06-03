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
}

/// Decode → optional downscale (long edge ≤ `max_edge`; 0 = keep original size)
/// → encode to `format` at `quality` (1..=100; ignored for PNG). Throws on a
/// container the codec layer can't handle yet.
pub fn transcode(
    bytes: Vec<u8>,
    format: CodecFormat,
    quality: u32,
    max_edge: u32,
) -> Result<Vec<u8>, String> {
    let q = quality.clamp(1, 100) as u8;
    let target = match format {
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
    };
    let edge = if max_edge == 0 { None } else { Some(max_edge) };
    codec::transcode(&bytes, target, edge).map_err(|e| e.to_string())
}
