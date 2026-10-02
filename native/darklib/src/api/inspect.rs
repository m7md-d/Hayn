//! FFI surface for source inspection: the facts a conversion plan reads from
//! the ORIGINAL bytes before any engine (platform or Rust) touches them.
//! Container scan only, no pixel decode; runs off the Dart isolate.

use crate::engine::inspect::{self, Facts};

/// HDR facts of `bytes`: the primary image's transfer (PQ/HLG) and whether a
/// gain map is present. Unreadable containers answer `Unknown`.
pub fn inspect_image(bytes: Vec<u8>) -> Facts {
    inspect::inspect(&bytes)
}

/// The source's colour profile as an RGB space (D50 RGB→XYZ, column-major,
/// and the transfer `[a, b, c, d, e, f, g]` of Android's
/// `ColorSpace.Rgb.TransferParameters`): an embedded ICC, or one built from
/// HEIF/AVIF `nclx` or PNG `cICP`. `None` without a profile, or when it is
/// not a matrix/TRC one. Android's HEIF decoder ignores a HEIC's profile
/// (Hayn IMG-21), so the display bridge names the pixels with this.
pub struct ProfileSpace {
    pub to_xyz_d50: Vec<f32>,
    pub transfer: Vec<f32>,
}

pub fn profile_space(bytes: Vec<u8>) -> Option<ProfileSpace> {
    let icc = crate::engine::metadata::extract(&bytes).icc?;
    let s = crate::engine::color::rgb_space(&icc)?;
    Some(ProfileSpace {
        to_xyz_d50: s.to_xyz_d50.to_vec(),
        transfer: s.transfer.to_vec(),
    })
}
