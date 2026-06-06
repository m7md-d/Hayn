//! DarkLib engine — pure, platform-independent image logic.
//!
//! No FFI here and (Stage 1) no codecs: everything is byte/container work that
//! `cargo test` can exercise directly. The FFI surface in `crate::api` is only
//! a thin wrapper that converts to/from FRB-friendly types. See
//! `docs/10-DARKLIB.md`.

pub mod codec;
pub mod color;
pub mod error;
pub mod format;
pub mod metadata;
