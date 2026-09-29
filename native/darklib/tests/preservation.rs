//! HDR policy on independent libavif fixtures (user decision, 2026-09-28):
//! keep a gain map where the path is proven, otherwise encode the SDR base and
//! report it; refuse PQ/HLG, which this engine cannot render as correct SDR.
//! AVIF→AVIF keeps the map; ImageIO proves it on the written outputs
//! (test_native/compare_hdr_rendition.swift). Before that decision these cases
//! were vetoes (910a281).

use darklib::engine::{
    codec::{self, HdrOutcome, Target},
    inspect::{inspect, Presence, Transfer},
    metadata::{self, isobmff},
};

const PQ: &[u8] = include_bytes!("fixtures/seine_hdr_rec2020.avif");
const GAINMAP: &[u8] = include_bytes!("fixtures/seine_sdr_gainmap_srgb.avif");

const WEBP: Target = Target::Webp {
    quality: 90,
    lossless: false,
};

/// Mean absolute RGB difference between two equally sized RGBA buffers.
fn mean_diff(a: &codec::Decoded, b: &codec::Decoded) -> f64 {
    assert_eq!((a.width, a.height), (b.width, b.height));
    let total: u64 = a
        .rgba
        .chunks_exact(4)
        .zip(b.rgba.chunks_exact(4))
        .map(|(p, q)| (0..3).map(|c| p[c].abs_diff(q[c]) as u64).sum::<u64>())
        .sum();
    total as f64 / (a.rgba.len() / 4 * 3) as f64
}

#[test]
fn pq_is_inspected_and_refused() {
    assert_eq!(isobmff::primary_nclx(PQ), Some(Some((9, 16))));
    assert_eq!(inspect(PQ).transfer, Transfer::Pq);
    assert!(codec::transcode(PQ, Target::Avif { quality: 80 }, None, true).is_err());
    assert!(codec::transcode(PQ, Target::Png, None, false).is_err());
}

#[test]
fn gainmap_source_is_inspected_as_sdr_base_with_map() {
    let facts = inspect(GAINMAP);
    assert_eq!(facts.gain_map, Presence::Present);
    assert!(!facts.transfer.is_direct_hdr());
}

#[test]
fn target_without_gainmap_support_gets_the_sdr_base() {
    let out = codec::transcode(GAINMAP, WEBP, None, true).unwrap();
    assert_eq!(out.hdr, HdrOutcome::GainMapDropped);
    assert!(!isobmff::has_gainmap(&out.bytes));
    let base = codec::decode(GAINMAP, None).unwrap();
    let back = codec::decode(&out.bytes, None).unwrap();
    assert!(mean_diff(&base, &back) < 4.0, "WebP is the base image");
}

#[test]
fn resize_gets_the_sdr_base() {
    let out = codec::transcode(GAINMAP, Target::Avif { quality: 80 }, Some(64), true).unwrap();
    assert_eq!(out.hdr, HdrOutcome::GainMapDropped);
    assert!(!isobmff::has_gainmap(&out.bytes));
    let d = codec::decode(&out.bytes, None).unwrap();
    assert_eq!(d.width.max(d.height), 64);
}

/// AVIF→AVIF keeps the map, with or without metadata (it is image data, not
/// private data). The output is written for the independent ImageIO checks.
#[test]
fn avif_to_avif_keeps_the_gainmap() {
    let dir = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join("gainmap");
    std::fs::create_dir_all(&dir).unwrap();
    let src_tmap = isobmff::read_tmap(GAINMAP).unwrap();
    for keep_metadata in [true, false] {
        let out =
            codec::transcode(GAINMAP, Target::Avif { quality: 80 }, None, keep_metadata).unwrap();
        assert_eq!(
            out.hdr,
            HdrOutcome::GainMapKept,
            "keep_metadata={keep_metadata}"
        );
        let kept = isobmff::read_tmap(&out.bytes).unwrap();
        assert_eq!(kept.payload, src_tmap.payload, "tmap metadata verbatim");
        assert_eq!(kept.alt_props, src_tmap.alt_props, "alternate pixi/colr");
        assert_eq!(
            metadata::extract(&out.bytes).exif.is_some(),
            keep_metadata,
            "EXIF follows the privacy choice"
        );
        std::fs::write(
            dir.join(format!("kept-meta{keep_metadata}.avif")),
            &out.bytes,
        )
        .unwrap();
    }
}

/// Entity group ids share the item id space (ISOBMFF); a clash made ImageIO
/// ignore the whole tmap graph (IMG-10, 2026-09-29).
#[test]
fn altr_group_id_is_not_an_item_id() {
    let out = codec::transcode(GAINMAP, Target::Avif { quality: 80 }, None, true).unwrap();
    let b = &out.bytes;
    let at = b.windows(4).position(|w| w == b"altr").unwrap();
    let group_id = u32::from_be_bytes(b[at + 8..at + 12].try_into().unwrap());
    let items = 1..=5; // base, gain map, tmap, Exif, XMP
    assert!(!items.contains(&group_id), "group id {group_id}");
}

/// pixi must state the depth the AV1 stream actually has (IMG-09).
#[test]
fn pixi_matches_av1c_in_hdr_and_grid_writers() {
    let pixi_bodies = |b: &[u8]| -> Vec<Vec<u8>> {
        b.windows(4)
            .enumerate()
            .filter(|(_, w)| *w == b"pixi")
            .map(|(i, _)| {
                let n = b[i + 8] as usize; // after type + FullBox header
                b[i + 8..i + 9 + n].to_vec()
            })
            .collect()
    };
    let out = codec::transcode(GAINMAP, Target::Avif { quality: 80 }, None, true).unwrap();
    let base_av1c = isobmff::av1c_raw(&out.bytes).unwrap();
    let want = isobmff::pixi_for_av1c(&base_av1c).unwrap();
    assert_eq!(pixi_bodies(&out.bytes)[0], want, "base pixi");

    let tile = codec::Decoded {
        width: 8,
        height: 8,
        rgba: vec![120; 8 * 8 * 4],
    };
    let one = codec::encode(&tile, Target::Avif { quality: 80 }).unwrap();
    let av1c = isobmff::av1c_raw(&one).unwrap();
    let payload = isobmff::extract_primary_av1(&one).unwrap();
    let spec = isobmff::GridSpec {
        rows: 1,
        cols: 2,
        tile_w: 8,
        tile_h: 8,
        width: 16,
        height: 8,
    };
    let grid = isobmff::build_grid_avif(&spec, &av1c, &[payload.clone(), payload]).unwrap();
    assert_eq!(
        pixi_bodies(&grid)[0],
        isobmff::pixi_for_av1c(&av1c).unwrap()
    );
}

#[test]
fn unreadable_gainmap_graph_reports_keep_failure() {
    let mut broken = GAINMAP.to_vec();
    let at = broken.windows(4).position(|b| b == b"dimg").unwrap();
    broken[at..at + 4].copy_from_slice(b"zzzz");
    assert!(isobmff::has_gainmap(&broken));
    assert!(isobmff::read_tmap(&broken).is_none());
    let out = codec::transcode(&broken, Target::Avif { quality: 80 }, None, true).unwrap();
    assert_eq!(out.hdr, HdrOutcome::GainMapKeepFailed);
    assert!(!isobmff::has_gainmap(&out.bytes));
}

#[test]
fn exif_rotation_drops_the_map_instead_of_misaligning_it() {
    // Replace one IFD0 entry without shifting any container offsets. The
    // original libavif fixture has no Orientation entry; inject() would keep
    // its existing Exif item unchanged and would not create the test condition.
    let exif = metadata::extract(GAINMAP).exif.unwrap();
    assert_eq!(&exif[..4], b"II\x2a\0");
    let start = GAINMAP.windows(exif.len()).position(|w| w == exif).unwrap();
    let ifd = u32::from_le_bytes(exif[4..8].try_into().unwrap()) as usize;
    assert!(u16::from_le_bytes(exif[ifd..ifd + 2].try_into().unwrap()) > 0);
    let entry = start + ifd + 2;
    let mut source = GAINMAP.to_vec();
    source[entry..entry + 12].copy_from_slice(&[0x12, 1, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0]);
    assert_eq!(metadata::extract(&source).orientation, 6);
    let out = codec::transcode(&source, Target::Avif { quality: 80 }, None, true).unwrap();
    assert_eq!(out.hdr, HdrOutcome::GainMapDropped);
    let upright = codec::decode(&source, None).unwrap();
    let back = codec::decode(&out.bytes, None).unwrap();
    assert_eq!((back.width, back.height), (upright.width, upright.height));
}
