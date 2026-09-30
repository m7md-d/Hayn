//! AVIF alpha through the decoder (Hayn IMG-02). Before the fix only the first
//! alpha item in the file was tried; its size had to match the whole image, so
//! per-tile alpha (`color_grid_alpha_nogrid.avif`) decoded opaque, and any alpha
//! decode failure was dropped silently. Decoded PNGs are written to
//! CARGO_TARGET_TMPDIR/avif-alpha for the independent comparison
//! (test_native/compare_avif_alpha.swift: ImageIO, and ffmpeg for the per-tile
//! file, which ImageIO cannot read).

use darklib::engine::{
    codec::{self, Decoded, Target},
    metadata::isobmff::{self, PrimaryAlpha},
};

const PER_TILE: &[u8] = include_bytes!("fixtures/color_grid_alpha_nogrid.avif");
const ALPHA_GRID: &[u8] = include_bytes!("fixtures/color_grid_alpha_grid_gainmap_nogrid.avif");
const ROTATED: &[u8] = include_bytes!("fixtures/abc_color_irot_alpha_irot.avif");
const NO_ALPHA_GRID: &[u8] = include_bytes!("fixtures/sofa_grid1x5_420.avif");

fn alphas(img: &Decoded) -> impl Iterator<Item = u8> + '_ {
    img.rgba.as_chunks::<4>().0.iter().map(|p| p[3])
}

#[test]
fn alpha_layouts_are_found() {
    assert!(
        matches!(isobmff::primary_alpha(PER_TILE), Some(PrimaryAlpha::Tiles(t)) if t.len() == 2)
    );
    assert!(matches!(
        isobmff::primary_alpha(ALPHA_GRID),
        Some(PrimaryAlpha::Item(_))
    ));
    assert!(matches!(
        isobmff::primary_alpha(ROTATED),
        Some(PrimaryAlpha::Item(_))
    ));
    assert_eq!(
        isobmff::primary_alpha(NO_ALPHA_GRID),
        Some(PrimaryAlpha::None)
    );
}

#[test]
fn transparent_fixtures_decode_with_alpha() {
    let dir = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join("avif-alpha");
    std::fs::create_dir_all(&dir).unwrap();
    for (name, bytes) in [
        ("color_grid_alpha_nogrid", PER_TILE),
        ("color_grid_alpha_grid_gainmap_nogrid", ALPHA_GRID),
        ("abc_color_irot_alpha_irot", ROTATED),
    ] {
        let img = codec::decode(bytes, None).unwrap_or_else(|e| panic!("{name}: {e:?}"));
        assert!(alphas(&img).any(|a| a < 255), "{name}: decoded opaque");
        let png = codec::encode(&img, Target::Png).unwrap();
        std::fs::write(dir.join(format!("{name}.png")), png).unwrap();
    }
    let opaque = codec::decode(NO_ALPHA_GRID, None).unwrap();
    assert!(alphas(&opaque).all(|a| a == 255));
}

/// Garbage in place of an alpha item's AV1 data: the decode fails instead of
/// returning the image opaque.
#[test]
fn broken_alpha_is_an_error_not_opacity() {
    for (name, bytes) in [("per-tile", PER_TILE), ("single", ROTATED)] {
        let alpha_id = match isobmff::primary_alpha(bytes).unwrap() {
            PrimaryAlpha::Item(id) => id,
            PrimaryAlpha::Tiles(ids) => ids[0],
            PrimaryAlpha::None => unreachable!(),
        };
        let data = isobmff::extract_item_av1(bytes, alpha_id).unwrap();
        let at = bytes
            .windows(data.len())
            .position(|w| w == data)
            .expect("alpha payload in mdat");
        let mut broken = bytes.to_vec();
        broken[at..at + data.len()].fill(0xFF);
        assert!(
            codec::decode(&broken, None).is_err(),
            "{name}: decoded despite broken alpha"
        );
    }
}
