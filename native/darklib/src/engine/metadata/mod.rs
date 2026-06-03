//! Lossless metadata operations — container surgery, NEVER re-encode (CLAUDE.md
//! §2). Two paths the caller must not confuse (docs/10-DARKLIB.md §4):
//!   • `strip` — remove metadata per a policy (this stage).
//!   • (Stage 1c) `extract` / `inject` / `transplant`.
//!
//! Each format keeps its own surgery in a submodule; this module only sniffs
//! the container and dispatches.

pub mod jpeg;
pub mod png;
pub mod webp;

use crate::engine::error::{DarkError, Result};
use crate::engine::format::{detect, ImageFormat};

/// What to do with the ICC colour profile when stripping. Removing it blind
/// changes the rendered colours, so the default keeps it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IccPolicy {
    /// Preserve the ICC profile (default — colour-safe).
    Keep,
    /// Remove the ICC profile too (the caller accepts the colour shift, or has
    /// already converted to sRGB).
    Strip,
}

/// What to do with the EXIF orientation tag when stripping. Removing the tag
/// without baking the rotation into the pixels would flip the image, so the
/// only option today is `Keep`. Baking needs a pixel pass and lands with the
/// codec stage (Stage 3+).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OrientationPolicy {
    /// Keep the orientation tag so the image stays upright (default).
    Keep,
}

/// Policy for [`strip`]. The default is colour-safe and upright: keep the ICC
/// profile and the orientation tag, drop everything else (EXIF/GPS, XMP, IPTC,
/// comments, timestamps).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StripPolicy {
    pub icc: IccPolicy,
    pub orientation: OrientationPolicy,
}

impl Default for StripPolicy {
    fn default() -> Self {
        Self {
            icc: IccPolicy::Keep,
            orientation: OrientationPolicy::Keep,
        }
    }
}

/// Strip metadata losslessly per [`policy`], dispatching on the detected
/// container. Returns the new bytes (identical pixels, same container).
///
/// Returns [`DarkError::UnsupportedFormat`] for containers without an in-Rust
/// editor yet (AVIF/HEIF land in Stage 1b) — the caller must skip, never
/// degrade by re-encoding.
pub fn strip(bytes: &[u8], policy: StripPolicy) -> Result<Vec<u8>> {
    match detect(bytes) {
        ImageFormat::Jpeg => jpeg::strip(bytes, policy),
        ImageFormat::Png => png::strip(bytes, policy),
        ImageFormat::Webp => webp::strip(bytes, policy),
        _ => Err(DarkError::UnsupportedFormat),
    }
}
