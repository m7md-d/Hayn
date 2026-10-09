//! The source's bit depth from its container (`Facts::bit_depth`, Hayn
//! IMG-23): what "match the source" means when the user picks a depth.
//! Expected values from pillow-heif 1.x (libheif 1.23) and the PNG IHDR as
//! Pillow reads it, not from DarkLib.

use std::path::Path;

use darklib::engine::codec::{self, Decoded, Target};
use darklib::engine::inspect::inspect;

fn fixture(name: &str) -> Vec<u8> {
    std::fs::read(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name),
    )
    .unwrap()
}

#[test]
fn fixtures_report_their_depth() {
    for (name, depth) in [
        ("apple_heic_10bit_p3.heic", 10),
        ("apple_heic_hlg.heic", 10),
        ("apple_heic_alpha_grid.heic", 8),
        ("android_heifwriter_grid.heic", 8),
        ("libheif_p3_icc.heic", 8),
        ("seine_hdr_rec2020.avif", 10),
        ("color_grid_alpha_grid_gainmap_nogrid.avif", 10),
        ("sofa_grid1x5_420.avif", 8),
        ("abc_color_irot_alpha_irot.avif", 8),
        ("apple_png_p3_icc.png", 8),
        ("apple_gainmap_new.jpg", 8),
        ("pillow_webp_lossy_opaque.webp", 8),
    ] {
        assert_eq!(inspect(&fixture(name)).bit_depth, depth, "{name}");
    }
}

#[test]
fn darklib_avif_reports_the_depth_it_wrote() {
    let img = Decoded {
        width: 16,
        height: 16,
        rgba: [30u8, 160, 90, 255].repeat(256),
    };
    for (depth, want) in [(None, 10), (Some(8), 8), (Some(10), 10)] {
        let avif = codec::encode(&img, Target::Avif { quality: 80, depth }).unwrap();
        assert_eq!(inspect(&avif).bit_depth, want, "{depth:?}");
    }
}

#[test]
fn unreadable_is_zero() {
    assert_eq!(inspect(b"not an image at all").bit_depth, 0);
}
