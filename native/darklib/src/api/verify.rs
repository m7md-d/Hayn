//! FFI surface for output verification: a conversion's result checked against
//! its source by decoding pixels. Heavy → async, off the Dart isolate.

use crate::engine::verify::{self, AlphaKept};

/// Whether `output` keeps the transparency of `source`, from decoded alpha
/// values rather than channel presence (Hayn IMG-15).
pub fn alpha_kept(source: Vec<u8>, output: Vec<u8>) -> AlphaKept {
    verify::alpha_kept(&source, &output)
}
