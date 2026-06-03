//! FFI surface for metadata operations — a thin wrapper over `crate::engine`.
//!
//! `detect_format` / `describe_format` / `can_strip_lossless` are trivial, so
//! they're `sync`. `strip_metadata` does the byte surgery off the Dart isolate
//! (FRB runs non-`sync` functions on a worker pool — CLAUDE.md §4).
//!
//! `ImageFormat` is reused straight from the engine (no FFI mirror) so the
//! generated Dart enum has a single source of truth.

use crate::engine::format::{detect, FormatDescriptor, ImageFormat};
use crate::engine::metadata as em;

/// What a container can carry + whether DarkLib can strip it losslessly today
/// (`can_strip` drives UI capability gating without a second call).
pub struct FormatInfo {
    pub format: ImageFormat,
    pub supports_exif: bool,
    pub supports_xmp: bool,
    pub supports_icc: bool,
    pub supports_iptc: bool,
    pub hdr_capable: bool,
    pub can_strip: bool,
}

/// Detect the container from leading bytes. Pure + fast → sync.
#[flutter_rust_bridge::frb(sync)]
pub fn detect_format(bytes: Vec<u8>) -> ImageFormat {
    detect(&bytes)
}

/// Describe the container's metadata abilities (capability matrix for the UI).
#[flutter_rust_bridge::frb(sync)]
pub fn describe_format(bytes: Vec<u8>) -> FormatInfo {
    let f = detect(&bytes);
    let d = FormatDescriptor::of(f);
    FormatInfo {
        format: f,
        supports_exif: d.supports_exif,
        supports_xmp: d.supports_xmp,
        supports_icc: d.supports_icc,
        supports_iptc: d.supports_iptc,
        hdr_capable: d.hdr_capable,
        can_strip: can_strip_format(f),
    }
}

/// Whether DarkLib can strip this container's metadata losslessly today.
#[flutter_rust_bridge::frb(sync)]
pub fn can_strip_lossless(bytes: Vec<u8>) -> bool {
    can_strip_format(detect(&bytes))
}

fn can_strip_format(f: ImageFormat) -> bool {
    matches!(
        f,
        ImageFormat::Jpeg
            | ImageFormat::Png
            | ImageFormat::Webp
            | ImageFormat::Avif
            | ImageFormat::Heic
    )
}

/// Strip metadata losslessly (no re-encode). `strip_icc` also removes the ICC
/// colour profile (default false = colour-safe); the orientation tag is always
/// kept so the image can't flip. Throws on an unsupported container. Runs off
/// the Dart isolate.
pub fn strip_metadata(bytes: Vec<u8>, strip_icc: bool) -> Result<Vec<u8>, String> {
    let policy = em::StripPolicy {
        icc: if strip_icc {
            em::IccPolicy::Strip
        } else {
            em::IccPolicy::Keep
        },
        orientation: em::OrientationPolicy::Keep,
    };
    em::strip(&bytes, policy).map_err(|e| e.to_string())
}

/// What metadata an image carries — for the "what will be removed" preview.
/// Works cross-platform (incl. HEIC/AVIF), unlike `package:exif` on Android.
pub struct MetadataSummary {
    pub has_exif: bool,
    pub has_xmp: bool,
    pub has_icc: bool,
    pub has_gps: bool,
    pub has_date: bool,
    pub has_camera: bool,
    /// EXIF orientation (1..=8; 1 = upright).
    pub orientation: u16,
    pub tag_count: u32,
}

/// Summarise the metadata present in an image. Cheap container scan → sync.
#[flutter_rust_bridge::frb(sync)]
pub fn read_metadata_summary(bytes: Vec<u8>) -> MetadataSummary {
    let c = em::extract(&bytes);
    let ex = c.exif.as_deref().and_then(em::exif::summarize);
    MetadataSummary {
        has_exif: c.exif.is_some(),
        has_xmp: c.xmp.is_some(),
        has_icc: c.icc.is_some(),
        has_gps: ex.map(|e| e.has_gps).unwrap_or(false),
        has_date: ex.map(|e| e.has_date).unwrap_or(false),
        has_camera: ex.map(|e| e.has_camera).unwrap_or(false),
        orientation: c.orientation,
        tag_count: ex.map(|e| e.tag_count).unwrap_or(0),
    }
}
