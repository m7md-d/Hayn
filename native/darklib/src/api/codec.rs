//! FFI surface for the ImageCodec (pixel work). Heavy → async (runs off the
//! Dart isolate on the FRB worker pool — CLAUDE.md §4).
//!
//! Stage 3a: PNG/JPEG transcode (pure-Rust). More formats slot in behind the
//! same call as the codec layer grows.

use crate::engine::codec::heif_alpha::{self, AlphaStream};
use crate::engine::codec::{self, Transcoded};

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

/// Opaque, upright PNG of `bytes` over white, for a JPEG of a transparent
/// source. Throws on a container the codec cannot decode, or past the budget.
pub fn flatten_on_white(bytes: Vec<u8>) -> Result<Vec<u8>, String> {
    codec::flatten_on_white(&bytes).map_err(|e| e.to_string())
}

/// Decode → optional downscale → encode at `quality` (1..=100; PNG ignores it).
/// `keep_metadata` carries EXIF/XMP/ICC. The result says what happened to an
/// HDR gain map. Throws `preservation_required:…` for PQ/HLG, which this
/// engine cannot render correctly as SDR, and a plain message for containers
/// the codec layer can't handle.
pub fn transcode(
    bytes: Vec<u8>,
    format: CodecFormat,
    quality: u32,
    max_edge: u32,
    keep_metadata: bool,
) -> Result<Transcoded, String> {
    let edge = if max_edge == 0 { None } else { Some(max_edge) };
    codec::transcode(&bytes, target_of(format, quality), edge, keep_metadata)
        .map_err(|e| e.to_string())
}

/// The alpha plane of a HEIF image's primary item as an Annex-B HEVC stream,
/// one frame per tile, for an HEVC decoder outside DarkLib; `None` when the
/// image has no alpha. Throws on HEIF whose alpha it cannot lay out (Hayn
/// IMG-15: Android's HEIF decoder drops the plane).
pub fn heif_alpha_stream(bytes: Vec<u8>) -> Result<Option<AlphaStream>, String> {
    heif_alpha::alpha_stream(&bytes).map_err(|e| e.to_string())
}

/// `base` (the platform's upright decode of `source`) with `grey`, the
/// stream's frames decoded to 8-bit full-range grey, as its alpha: an RGBA
/// PNG. Throws when the plane does not fit the image.
pub fn heif_attach_alpha(source: Vec<u8>, base: Vec<u8>, grey: Vec<u8>) -> Result<Vec<u8>, String> {
    heif_alpha::attach_alpha(&source, &base, &grey).map_err(|e| e.to_string())
}
