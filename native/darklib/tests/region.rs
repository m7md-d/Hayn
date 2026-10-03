//! AVIF read by regions for display (Hayn PERF-03). Put back together, the
//! tiles must be the image the whole decode gives (itself checked against
//! ImageIO and ffmpeg for these files, IMG-02): orientation, alpha and grid
//! layout included, at full size exactly and sampled as block averages.
//! Colours are converted to sRGB; HDR is refused; the pyramid files go with
//! the reader.

use std::path::{Path, PathBuf};

use darklib::engine::codec::region::{AvifRegion, Tile};
use darklib::engine::codec::{self, Decoded, Target};
use darklib::engine::metadata;

fn fixture(name: &str) -> Vec<u8> {
    std::fs::read(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures")
            .join(name),
    )
    .unwrap()
}

/// A cache directory of the test's own, emptied first.
fn cache(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR"))
        .join("region")
        .join(name);
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn files(dir: &Path) -> usize {
    std::fs::read_dir(dir).unwrap().count()
}

/// The upright image sampled by `s`, from tiles of `tile` full-size pixels
/// asked a row at a time as the app asks them.
fn assemble(region: &AvifRegion, s: u32, tile: u32) -> (u32, u32, Vec<u8>) {
    let (w, h) = (region.width(), region.height());
    let (ow, oh) = (w.div_ceil(s), h.div_ceil(s));
    let mut out = vec![0u8; ow as usize * oh as usize * 4];
    let span = tile * s;
    let mut y = 0;
    while y < h {
        let bottom = (y + span).min(h);
        let cuts: Vec<u32> = (1..w.div_ceil(span)).map(|c| c * span).collect();
        let tiles = region.tiles([0, y, w, bottom], &cuts, s).unwrap();
        assert_eq!(tiles.len(), w.div_ceil(span) as usize);
        let mut x = 0usize;
        for Tile {
            width,
            height,
            rgba,
        } in tiles
        {
            for row in 0..height as usize {
                let dst = (((y / s) as usize + row) * ow as usize + x) * 4;
                let src = row * width as usize * 4;
                out[dst..dst + width as usize * 4]
                    .copy_from_slice(&rgba[src..src + width as usize * 4]);
            }
            x += width as usize;
        }
        assert_eq!(x, ow as usize);
        y = bottom;
    }
    (ow, oh, out)
}

fn premultiplied(mut px: Vec<u8>) -> Vec<u8> {
    for p in px.chunks_exact_mut(4) {
        let a = p[3] as u32;
        for v in &mut p[..3] {
            *v = ((*v as u32 * a + 127) / 255) as u8;
        }
    }
    px
}

/// `img` averaged in `s`×`s` blocks from its corner.
fn box_average(img: &Decoded, s: u32) -> Vec<u8> {
    let (w, h) = (img.width, img.height);
    let (ow, oh) = (w.div_ceil(s), h.div_ceil(s));
    let mut out = vec![0u8; (ow * oh * 4) as usize];
    for oy in 0..oh {
        for ox in 0..ow {
            for c in 0..4 {
                let (mut sum, mut n) = (0u32, 0u32);
                for y in oy * s..((oy + 1) * s).min(h) {
                    for x in ox * s..((ox + 1) * s).min(w) {
                        sum += img.rgba[((y * w + x) * 4) as usize + c] as u32;
                        n += 1;
                    }
                }
                out[((oy * ow + ox) * 4) as usize + c] = ((sum + n / 2) / n) as u8;
            }
        }
    }
    out
}

/// A test picture: smooth colour with fine detail, so a wrong tile shows.
fn picture(w: u32, h: u32) -> Decoded {
    let mut rgba = Vec::with_capacity((w * h * 4) as usize);
    for y in 0..h {
        for x in 0..w {
            let fine = if (x / 3 + y / 3) % 2 == 0 { 40 } else { 0 };
            rgba.extend_from_slice(&[(x * 255 / w) as u8, (y * 255 / h) as u8, 120 + fine, 255]);
        }
    }
    Decoded {
        width: w,
        height: h,
        rgba,
    }
}

#[test]
fn one_item_tiles_are_the_whole_decode() {
    let avif = codec::encode(&picture(700, 450), Target::Avif { quality: 90 }).unwrap();
    let whole = codec::decode(&avif, None).unwrap();
    let dir = cache("one-item");
    let region = AvifRegion::open(avif, &dir).unwrap();
    assert!(files(&dir) >= 2, "a pyramid of files");
    assert_eq!((region.width(), region.height()), (700, 450));
    let (w, h, px) = assemble(&region, 1, 128);
    assert_eq!((w, h), (700, 450));
    assert!(px == whole.rgba, "full size: the same pixels");
    for s in [2, 4, 8] {
        let (_, _, px) = assemble(&region, s, 64);
        let want = box_average(&whole, s);
        let off = px
            .iter()
            .zip(&want)
            .filter(|(a, b)| a.abs_diff(**b) > 1)
            .count();
        assert_eq!(off, 0, "sampled by {s}: block averages");
    }
    drop(region);
    assert_eq!(files(&dir), 0, "the pyramid goes with the reader");
}

#[test]
fn grid_tiles_are_the_whole_decode() {
    for name in ["sofa_grid1x5_420.avif", "color_grid_alpha_nogrid.avif"] {
        let avif = fixture(name);
        let whole = codec::decode(&avif, None).unwrap();
        let dir = cache(name);
        let region = AvifRegion::open(avif, &dir).unwrap();
        assert_eq!(files(&dir), 0, "{name}: a grid writes no file");
        assert_eq!(
            (region.width(), region.height()),
            (whole.width, whole.height)
        );
        for tile in [16, 100] {
            let (_, _, px) = assemble(&region, 1, tile);
            assert!(
                px == premultiplied(whole.rgba.clone()),
                "{name}: tiles of {tile}"
            );
        }
        let (_, _, px) = assemble(&region, 2, 32);
        let want = premultiplied(box_average(&whole, 2));
        let off = px
            .iter()
            .zip(&want)
            .filter(|(a, b)| a.abs_diff(**b) > 2)
            .count();
        assert_eq!(off, 0, "{name}: sampled by 2");
    }
}

#[test]
fn turned_image_with_alpha_comes_upright() {
    // irot on the colour and on the alpha (libavif's sample).
    let avif = fixture("abc_color_irot_alpha_irot.avif");
    let whole = codec::decode(&avif, None).unwrap();
    let region = AvifRegion::open(avif, &cache("irot")).unwrap();
    assert_eq!(
        (region.width(), region.height()),
        (whole.width, whole.height)
    );
    let (_, _, px) = assemble(&region, 1, 48);
    assert!(px == premultiplied(whole.rgba));
}

#[test]
fn a_profile_converts_to_srgb() {
    // P3 quadrants named P3 by Apple's profile; LittleCMS's sRGB for them at
    // the quadrant centres (fixtures/README, libheif_p3_icc.heic).
    let mut px = Vec::new();
    for y in 0..48u32 {
        for x in 0..64u32 {
            let q = (y >= 24) as usize * 2 + (x >= 32) as usize;
            let c = [[220, 40, 40], [40, 200, 60], [40, 60, 220], [230, 210, 40]][q];
            px.extend_from_slice(&[c[0], c[1], c[2], 255]);
        }
    }
    let avif = codec::encode(
        &Decoded {
            width: 64,
            height: 48,
            rgba: px,
        },
        Target::Avif { quality: 100 },
    )
    .unwrap();
    let p3 = metadata::extract(&fixture("apple_png_p3_icc.png"));
    assert!(p3.icc.is_some());
    let tagged = metadata::inject(
        &avif,
        &metadata::Canonical {
            icc: p3.icc,
            ..Default::default()
        },
    );
    let region = AvifRegion::open(tagged, &cache("p3")).unwrap();
    let t = &region.tiles([0, 0, 64, 48], &[], 1).unwrap()[0];
    let want = [[240, 0, 23], [0, 204, 12], [34, 61, 228], [235, 209, 0]];
    for (q, (x, y)) in [(16, 12), (48, 12), (16, 36), (48, 36)]
        .into_iter()
        .enumerate()
    {
        let p = &t.rgba[((y * 64 + x) * 4) as usize..][..3];
        for c in 0..3 {
            assert!(
                p[c].abs_diff(want[q][c]) <= 6,
                "quadrant {q}: {p:?} vs {:?}",
                want[q]
            );
        }
    }
}

#[test]
fn hdr_and_other_formats_are_refused() {
    // The last two: a PQ primary with a gain map to SDR, and not an AVIF.
    for name in [
        "seine_hdr_rec2020.avif",
        "colors_wcg_hdr_rec2020.avif",
        "color_grid_alpha_grid_gainmap_nogrid.avif",
        "apple_png_p3_icc.png",
    ] {
        let dir = cache(&format!("refused-{name}"));
        assert!(AvifRegion::open(fixture(name), &dir).is_err(), "{name}");
        assert_eq!(files(&dir), 0, "{name}: nothing left behind");
    }
}
