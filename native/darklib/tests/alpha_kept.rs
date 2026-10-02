//! Transparency checked from decoded alpha values, not channel presence
//! (Hayn IMG-15). On a Galaxy S25 Edge (Android 16) the platform decoder gave
//! `apple_heic_alpha.heic` back as RGBA with every alpha sample 255 and the
//! hidden colour (80,120,158) where the image is transparent; its HEVC
//! decoders take neither the monochrome alpha item as the primary image nor
//! its bitstream directly (probe, 2026-10-02).

use std::io::Cursor;

use darklib::engine::{
    codec::{self, Target},
    verify::{alpha_kept, AlphaKept},
};
use image::{ImageFormat, RgbImage, RgbaImage};

const HEIC_ALPHA: &[u8] = include_bytes!("fixtures/apple_heic_alpha.heic");
const HEIC_OPAQUE: &[u8] = include_bytes!("fixtures/apple_heic_10bit_p3.heic");

fn png_rgba(alpha: u8) -> Vec<u8> {
    let img = RgbaImage::from_pixel(64, 48, image::Rgba([80, 120, 158, alpha]));
    let mut out = Cursor::new(Vec::new());
    img.write_to(&mut out, ImageFormat::Png).unwrap();
    out.into_inner()
}

fn png_rgb() -> Vec<u8> {
    let img = RgbImage::from_pixel(64, 48, image::Rgb([80, 120, 158]));
    let mut out = Cursor::new(Vec::new());
    img.write_to(&mut out, ImageFormat::Png).unwrap();
    out.into_inner()
}

#[test]
fn a_fully_opaque_alpha_channel_from_a_transparent_heic_is_lost() {
    // What Android's decoder returns: the channel is there, its values are not.
    assert_eq!(alpha_kept(HEIC_ALPHA, &png_rgba(255)), AlphaKept::Lost);
    assert_eq!(alpha_kept(HEIC_ALPHA, &png_rgb()), AlphaKept::Lost);
}

#[test]
fn decoded_transparency_is_kept() {
    assert_eq!(alpha_kept(HEIC_ALPHA, &png_rgba(64)), AlphaKept::Kept);
}

#[test]
fn an_opaque_source_has_nothing_to_lose() {
    assert_eq!(alpha_kept(HEIC_OPAQUE, &png_rgb()), AlphaKept::Kept);
    // A channel whose samples are all 255 shows nothing either way.
    let opaque_rgba = png_rgba(255);
    let jpeg = codec::transcode(&opaque_rgba, Target::Jpeg(90), None, false)
        .unwrap()
        .bytes;
    assert_eq!(alpha_kept(&opaque_rgba, &jpeg), AlphaKept::Kept);
}

#[test]
fn a_decodable_source_answers_from_its_samples() {
    let transparent = png_rgba(64);
    let jpeg = codec::transcode(&transparent, Target::Jpeg(90), None, false)
        .unwrap()
        .bytes;
    assert_eq!(alpha_kept(&transparent, &jpeg), AlphaKept::Lost);
    let webp = codec::transcode(
        &transparent,
        Target::Webp {
            quality: 90,
            lossless: false,
        },
        None,
        false,
    )
    .unwrap()
    .bytes;
    assert_eq!(alpha_kept(&transparent, &webp), AlphaKept::Kept);
}

#[test]
fn an_undecodable_output_answers_from_its_container() {
    // HEIC output (ImageIO on iOS): the alpha auxiliary is declared, unread.
    assert_eq!(alpha_kept(&png_rgba(64), HEIC_ALPHA), AlphaKept::Declared);
    assert_eq!(alpha_kept(&png_rgba(64), HEIC_OPAQUE), AlphaKept::Lost);
    assert_eq!(alpha_kept(b"not an image", b"neither"), AlphaKept::Unknown);
}
