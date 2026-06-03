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
}

impl fmt::Display for DarkError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DarkError::UnsupportedFormat => write!(f, "unsupported image format"),
            DarkError::Malformed(why) => write!(f, "malformed image: {why}"),
        }
    }
}

impl std::error::Error for DarkError {}

pub type Result<T> = std::result::Result<T, DarkError>;
