//! Output verification: checks a conversion's result against its source by
//! decoding pixels, where reading the container cannot answer (Hayn IMG-05).
//!
//! A channel in the container is not transparency. Android's HEIF decoder
//! ignores the alpha plane of an Apple HEIC and still returns RGBA, every
//! sample 255 (Hayn IMG-15); a check on channel presence passed it, and the
//! image's hidden colours were saved as if transparency had survived.

use crate::engine::codec;
use crate::engine::inspect::{inspect, Presence};

/// What became of a source's transparency in a conversion's output.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AlphaKept {
    /// The output's decoded samples show transparency, or the source had none
    /// to keep.
    Kept,
    /// The output cannot be decoded here (HEIC), but its container declares an
    /// alpha plane. Its values are unverified.
    Declared,
    /// The source has transparency the output lacks.
    Lost,
    /// Neither the decoded samples nor the containers answer.
    Unknown,
}

/// Whether `output` keeps the transparency of `source`. The output is decoded
/// in full (within the decode budget); the source only when the output shows
/// none, to tell a lost alpha plane from an opaque one. A source DarkLib cannot
/// decode (HEIC) answers from its container: an alpha auxiliary is taken as
/// transparency.
pub fn alpha_kept(source: &[u8], output: &[u8]) -> AlphaKept {
    match transparency(output) {
        Some(true) => AlphaKept::Kept,
        Some(false) => had_transparency(source),
        None => match inspect(output).alpha {
            Presence::Present => AlphaKept::Declared,
            Presence::Absent => had_transparency(source),
            Presence::Unknown => AlphaKept::Unknown,
        },
    }
}

/// The verdict for an output showing no transparency.
fn had_transparency(source: &[u8]) -> AlphaKept {
    let had = transparency(source).or_else(|| match inspect(source).alpha {
        Presence::Present => Some(true),
        Presence::Absent => Some(false),
        Presence::Unknown => None,
    });
    match had {
        Some(true) => AlphaKept::Lost,
        Some(false) => AlphaKept::Kept,
        None => AlphaKept::Unknown,
    }
}

/// Whether any decoded sample is less than opaque; `None` when the bytes do
/// not decode here.
fn transparency(bytes: &[u8]) -> Option<bool> {
    let img = codec::decode(bytes, None).ok()?;
    Some(img.rgba.as_chunks::<4>().0.iter().any(|p| p[3] < 255))
}
