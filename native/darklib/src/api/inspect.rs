//! FFI surface for source inspection: the facts a conversion plan reads from
//! the ORIGINAL bytes before any engine (platform or Rust) touches them.
//! Container scan only, no pixel decode; runs off the Dart isolate.

use crate::engine::inspect::{self, Facts};

/// HDR facts of `bytes`: the primary image's transfer (PQ/HLG) and whether a
/// gain map is present. Unreadable containers answer `Unknown`.
pub fn inspect_image(bytes: Vec<u8>) -> Facts {
    inspect::inspect(&bytes)
}
