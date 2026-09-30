//! Alpha from the container, without decoding (Hayn IMG-15/IMG-16). Expected
//! values come from ImageIO on the Mac (`sips -g hasAlpha`), except
//! `color_grid_alpha_nogrid.avif`: ImageIO misses its per-tile alpha, which the
//! spec allows and libavif's own description calls a file with alpha.

use darklib::engine::{
    codec::{self, Target},
    inspect::{inspect, Presence},
};

fn alpha(bytes: &[u8]) -> Presence {
    inspect(bytes).alpha
}

#[test]
fn heif_and_avif_fixtures() {
    use Presence::{Absent, Present};
    for (name, bytes, want) in [
        (
            "apple_heic_alpha.heic",
            &include_bytes!("fixtures/apple_heic_alpha.heic")[..],
            Present,
        ),
        (
            "apple_heic_10bit_p3.heic",
            include_bytes!("fixtures/apple_heic_10bit_p3.heic"),
            Absent,
        ),
        (
            "apple_heic_hlg.heic",
            include_bytes!("fixtures/apple_heic_hlg.heic"),
            Absent,
        ),
        (
            "abc_color_irot_alpha_irot.avif",
            include_bytes!("fixtures/abc_color_irot_alpha_irot.avif"),
            Present,
        ),
        (
            "color_grid_alpha_grid_gainmap_nogrid.avif",
            include_bytes!("fixtures/color_grid_alpha_grid_gainmap_nogrid.avif"),
            Present,
        ),
        (
            "color_grid_alpha_nogrid.avif",
            include_bytes!("fixtures/color_grid_alpha_nogrid.avif"),
            Present,
        ),
        (
            "sofa_grid1x5_420.avif",
            include_bytes!("fixtures/sofa_grid1x5_420.avif"),
            Absent,
        ),
        (
            "paris_icc_exif_xmp.avif",
            include_bytes!("fixtures/paris_icc_exif_xmp.avif"),
            Absent,
        ),
        // Gain-map auxiliaries are not alpha.
        (
            "seine_sdr_gainmap_srgb.avif",
            include_bytes!("fixtures/seine_sdr_gainmap_srgb.avif"),
            Absent,
        ),
        (
            "seine_hdr_gainmap_srgb.avif",
            include_bytes!("fixtures/seine_hdr_gainmap_srgb.avif"),
            Absent,
        ),
        (
            "apple_png_p3_icc.png",
            include_bytes!("fixtures/apple_png_p3_icc.png"),
            Absent,
        ),
        (
            "paris_icc_exif_xmp.png",
            include_bytes!("fixtures/paris_icc_exif_xmp.png"),
            Absent,
        ),
        (
            "apple_gainmap_new.jpg",
            include_bytes!("fixtures/apple_gainmap_new.jpg"),
            Absent,
        ),
    ] {
        assert_eq!(alpha(bytes), want, "{name}");
    }
}

/// libwebp through Pillow (test_native/make_webp_fixtures.py), not DarkLib.
#[test]
fn webp_fixtures_from_an_independent_writer() {
    use Presence::{Absent, Present};
    for (name, bytes, want) in [
        (
            "lossy_opaque",
            &include_bytes!("fixtures/pillow_webp_lossy_opaque.webp")[..],
            Absent,
        ),
        (
            "lossy_alpha",
            include_bytes!("fixtures/pillow_webp_lossy_alpha.webp"),
            Present,
        ),
        (
            "lossless_opaque",
            include_bytes!("fixtures/pillow_webp_lossless_opaque.webp"),
            Absent,
        ),
        (
            "lossless_alpha",
            include_bytes!("fixtures/pillow_webp_lossless_alpha.webp"),
            Present,
        ),
    ] {
        assert_eq!(alpha(bytes), want, "{name}");
    }
}

fn png(color_type: image::ExtendedColorType, px: &[u8], w: u32) -> Vec<u8> {
    use image::ImageEncoder;
    let mut out = Vec::new();
    image::codecs::png::PngEncoder::new(&mut out)
        .write_image(px, w, 1, color_type)
        .unwrap();
    out
}

#[test]
fn png_colour_type_and_trns() {
    use image::ExtendedColorType::{La8, Rgb8, Rgba8};
    assert_eq!(alpha(&png(Rgb8, &[1, 2, 3], 1)), Presence::Absent);
    assert_eq!(alpha(&png(Rgba8, &[1, 2, 3, 255], 1)), Presence::Present);
    assert_eq!(alpha(&png(La8, &[9, 0], 1)), Presence::Present);
    // tRNS on an RGB image: inserted after IHDR (8 + 25 bytes).
    let mut p = png(Rgb8, &[1, 2, 3], 1);
    let trns = [
        0, 0, 0, 6, b't', b'R', b'N', b'S', 0, 1, 0, 2, 0, 3, 0, 0, 0, 0,
    ];
    p.splice(33..33, trns);
    assert_eq!(alpha(&p), Presence::Present);
}

/// libwebp output through DarkLib's own writer, with and without metadata
/// (the metadata path rebuilds the file as VP8X).
#[test]
fn webp_from_darklib_opaque_and_translucent() {
    let (w, h) = (16u32, 12u32);
    let opaque: Vec<u8> = (0..w * h).flat_map(|i| [i as u8, 90, 160, 255]).collect();
    let mut translucent = opaque.clone();
    translucent[3] = 64;
    for (px, want) in [(opaque, Presence::Absent), (translucent, Presence::Present)] {
        let source = png(image::ExtendedColorType::Rgba8, &px, w * h);
        for lossless in [false, true] {
            for keep in [false, true] {
                let out = codec::transcode(
                    &source,
                    Target::Webp {
                        quality: 80,
                        lossless,
                    },
                    None,
                    keep,
                )
                .unwrap();
                assert_eq!(alpha(&out.bytes), want, "lossless={lossless} keep={keep}");
            }
        }
    }
}

#[test]
fn truncated_webp_is_unknown() {
    let source = png(image::ExtendedColorType::Rgb8, &[1, 2, 3], 1);
    let out = codec::transcode(
        &source,
        Target::Webp {
            quality: 80,
            lossless: false,
        },
        None,
        false,
    )
    .unwrap();
    assert_eq!(alpha(&out.bytes[..out.bytes.len() - 4]), Presence::Unknown);
}
