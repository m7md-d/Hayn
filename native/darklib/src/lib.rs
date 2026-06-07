//! # DarkLib
//!
//! An offline, royalty-free image core: lossless metadata surgery, colour
//! management, and modern-codec decode/encode behind one engine. Everything runs
//! on-device — no network, no telemetry — and codecs are patent-clean (AV1, WebP,
//! JPEG, PNG); patent-encumbered formats (HEVC) are never software-encoded.
//!
//! Two layers:
//! - [`engine`] — the portable, pure-Rust core. No FFI, no platform assumptions;
//!   `cargo test` exercises it directly. Rust reusers depend on this.
//! - [`api`] (+ the generated FRB glue) — a thin `flutter_rust_bridge` adapter
//!   that wraps `engine` for the Flutter app. Not needed for Rust-only reuse.
//!
//! See `README.md` and `docs/` for the architecture, the format decision tree,
//! supported targets, and build instructions.

pub mod api;
pub mod engine;
mod frb_generated;
