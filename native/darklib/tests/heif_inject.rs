//! Metadata injection into a grid HEIF whose grid descriptor lives in `idat`
//! (construction method 1), the shape Android's `HeifWriter`/`MediaMuxer`
//! write. Before RUN-01 step 5 the surgery refused any non-method-0 item and
//! returned the file unchanged, so Android HEIC output carried no profile and
//! no EXIF. Outputs go to CARGO_TARGET_TMPDIR/heif-inject for an independent
//! reader (libheif: test_native/check_heif_inject.py).

use darklib::engine::metadata::{self, isobmff};

const GRID: &[u8] = include_bytes!("fixtures/android_heifwriter_grid.heic");
const P3_JPEG_EXIF: &[u8] = include_bytes!("fixtures/apple_gainmap_new.jpg");

fn items(b: &[u8]) -> Vec<(u32, Vec<u8>)> {
    let primary = isobmff::primary_item_id(b).unwrap();
    let mut ids = vec![primary];
    ids.extend(isobmff::iref_targets(b, b"dimg", primary).unwrap());
    ids.into_iter()
        .map(|id| (id, isobmff::read_item_by_id(b, id).unwrap()))
        .collect()
}

#[test]
fn fixture_is_an_idat_grid() {
    let primary = isobmff::primary_item_id(GRID).unwrap();
    assert_eq!(isobmff::item_type(GRID, primary), Some(*b"grid"));
    assert_eq!(isobmff::primary_extent(GRID), Some((16, 12)));
    let src = metadata::extract(GRID);
    assert!(src.exif.is_none() && src.icc.is_none());
}

#[test]
fn source_metadata_lands_in_an_idat_grid() {
    let source = metadata::extract(P3_JPEG_EXIF);
    assert!(source.exif.is_some() && source.icc.is_some());

    let out = metadata::inject(GRID, &source);
    assert!(out != GRID, "inject returned the file unchanged");

    let carried = metadata::extract(&out);
    assert_eq!(carried.icc, source.icc);
    assert!(carried.exif.is_some());
    assert_eq!(carried.orientation, 1);
    // Every image item (the idat grid descriptor and the mdat tiles) reads
    // back byte for byte, and the canvas is unchanged.
    assert_eq!(items(&out), items(GRID));
    assert_eq!(isobmff::primary_extent(&out), Some((16, 12)));
    // The profile is the grid's and every tile's: Android reads a grid's
    // colour from its first tile and showed the P3 output as sRGB before.
    let primary = isobmff::primary_item_id(&out).unwrap();
    let tiles = isobmff::iref_targets(&out, b"dimg", primary).unwrap();
    for id in std::iter::once(primary).chain(tiles) {
        let props = isobmff::item_properties(&out, id).unwrap();
        let colr = props.iter().find(|p| &p[4..8] == b"colr").expect("colr");
        assert_eq!(&colr[8..12], b"prof", "item {id}");
        assert_eq!(&colr[12..], source.icc.as_deref().unwrap(), "item {id}");
    }

    let dir = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join("heif-inject");
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("source.heic"), GRID).unwrap();
    std::fs::write(dir.join("with_metadata.heic"), &out).unwrap();
}
