//! HEIF alpha for platforms whose decoder drops it (Hayn IMG-15). DarkLib
//! extracts the alpha item as an HEVC stream and attaches the decoded plane;
//! the decode itself is FFmpeg's (`fixtures/apple_heic_alpha.gray`, from an
//! independent decoder), so these tests need no HEVC decoder.

use std::io::Cursor;

use darklib::engine::codec::heif_alpha::{alpha_stream, attach_alpha};
use image::{ImageFormat, RgbaImage};

const HEIC_ALPHA: &[u8] = include_bytes!("fixtures/apple_heic_alpha.heic");
const GREY: &[u8] = include_bytes!("fixtures/apple_heic_alpha.gray");

/// What Android's decoder returns: the hidden colour, opaque everywhere.
fn opaque_base(w: u32, h: u32) -> Vec<u8> {
    let img = RgbaImage::from_pixel(w, h, image::Rgba([80, 120, 158, 255]));
    let mut out = Cursor::new(Vec::new());
    img.write_to(&mut out, ImageFormat::Png).unwrap();
    out.into_inner()
}

fn rgba(png: &[u8]) -> RgbaImage {
    image::load_from_memory(png).unwrap().into_rgba8()
}

/// NAL unit types of an Annex-B stream with 4-byte start codes.
fn nal_types(stream: &[u8]) -> Vec<u8> {
    stream
        .windows(5)
        .filter(|w| w[..4] == [0, 0, 0, 1])
        .map(|w| (w[4] >> 1) & 0x3f)
        .collect()
}

#[test]
fn the_alpha_item_comes_out_as_one_hevc_frame() {
    let s = alpha_stream(HEIC_ALPHA).unwrap().unwrap();
    assert_eq!((s.frames, s.width, s.height), (1, 64, 48));
    // VPS, SPS, PPS from hvcC, then the IDR picture (IDR_N_LP).
    assert_eq!(nal_types(&s.hevc), [32, 33, 34, 20]);
    assert_eq!(s.hevc.len(), 126); // 79 bytes of parameter sets + 47 of picture
}

#[test]
fn an_image_without_alpha_has_no_stream() {
    let opaque = include_bytes!("fixtures/apple_heic_10bit_p3.heic");
    assert_eq!(alpha_stream(opaque).unwrap(), None);
}

#[test]
fn the_decoded_plane_becomes_the_alpha_of_the_platform_decode() {
    let out = rgba(&attach_alpha(HEIC_ALPHA, &opaque_base(64, 48), GREY).unwrap());
    assert_eq!(out.dimensions(), (64, 48));
    assert_eq!(out.get_pixel(6, 6).0, [80, 120, 158, 64]);
    assert_eq!(out.get_pixel(32, 24).0[3], 255);
    for (i, p) in out.pixels().enumerate() {
        assert_eq!(p.0[3], GREY[i]);
    }
}

#[test]
fn the_alpha_item_orientation_is_applied() {
    // Both items share one irot property; turn it 90° counter-clockwise, as
    // the platform's decode of the colour item then is (48×64).
    let mut rotated = HEIC_ALPHA.to_vec();
    let at = rotated.windows(4).position(|w| w == b"irot").unwrap();
    rotated[at + 4] = 1;
    let out = rgba(&attach_alpha(&rotated, &opaque_base(48, 64), GREY).unwrap());
    assert_eq!(out.dimensions(), (48, 64));
    // Counter-clockwise: source (x, y) lands on (y, 63 - x).
    for (x, y) in [(6u32, 6u32), (32, 24), (60, 44), (20, 30)] {
        let want = GREY[(y * 64 + x) as usize];
        assert_eq!(out.get_pixel(y, 63 - x).0[3], want, "source ({x},{y})");
    }
}

#[test]
fn a_preview_sampled_down_gets_the_plane_scaled() {
    let out = rgba(&attach_alpha(HEIC_ALPHA, &opaque_base(32, 24), GREY).unwrap());
    assert_eq!(out.dimensions(), (32, 24));
    assert_eq!(out.get_pixel(3, 3).0[3], 64);
    assert_eq!(out.get_pixel(16, 12).0[3], 255);
}

#[test]
fn mismatches_are_errors_not_a_guessed_plane() {
    assert!(attach_alpha(HEIC_ALPHA, &opaque_base(64, 48), &GREY[1..]).is_err());
    assert!(attach_alpha(HEIC_ALPHA, &opaque_base(40, 40), GREY).is_err());
    let opaque = include_bytes!("fixtures/apple_heic_10bit_p3.heic");
    assert!(attach_alpha(opaque, &opaque_base(64, 48), GREY).is_err());
}
