//! DarkLib FFI smoke surface (Stage 0).
//!
//! The real image/metadata API lands in sibling modules under `crate::api`
//! (see docs/10-DARKLIB.md). These two functions exist only to prove the
//! Dart -> Rust -> Dart round-trip and the version handshake build & link on
//! every target.

/// Round-trips a string across the FFI boundary. Used by the smoke test.
#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

/// The DarkLib core version (the crate's Cargo version), so the Dart side can
/// assert the bundled native library matches the bindings it was generated for.
#[flutter_rust_bridge::frb(sync)]
pub fn darklib_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greet_round_trips() {
        assert_eq!(greet("DarkLib".to_string()), "Hello, DarkLib!");
    }

    #[test]
    fn version_matches_cargo() {
        assert_eq!(darklib_version(), env!("CARGO_PKG_VERSION"));
    }
}
