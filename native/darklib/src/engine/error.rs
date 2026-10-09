//! Result + error type for DarkLib engine operations.

use std::fmt;

/// Errors from engine operations. Deliberately small and `Clone` so it can
/// cross the FFI boundary as a plain string (see `crate::api`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DarkError {
    /// The container isn't supported for the requested operation (yet).
    UnsupportedFormat,
    /// The bytes are malformed for their detected container.
    Malformed(&'static str),
    /// A supported pixel path would violate a source preservation requirement.
    PreservationRequired(&'static str),
    /// Decoding would need more pixels than the decode budget; refused before
    /// any pixel buffer is allocated.
    TooLarge,
    /// A valid image this path does not take (a progressive or CMYK JPEG for
    /// the streaming re-encode): the caller uses another path.
    Unsupported(&'static str),
}

impl fmt::Display for DarkError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DarkError::PreservationRequired(why) => write!(f, "preservation_required:{why}"),
            DarkError::UnsupportedFormat => write!(f, "unsupported image format"),
            DarkError::Malformed(why) => write!(f, "malformed image: {why}"),
            DarkError::TooLarge => write!(f, "too_large"),
            DarkError::Unsupported(why) => write!(f, "unsupported:{why}"),
        }
    }
}

impl std::error::Error for DarkError {}

pub type Result<T> = std::result::Result<T, DarkError>;
