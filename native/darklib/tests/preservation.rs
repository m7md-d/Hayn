//! HDR policy on independent libavif fixtures (user decision, 2026-09-28):
//! keep a gain map where the path is proven, otherwise encode the SDR base and
//! report it; refuse PQ/HLG, which this engine cannot render as correct SDR.
//! No keeping path is proven yet (IMG-10). Before that decision these cases
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

/// The rebuilt gain map is not recognised by ImageIO (IMG-10), so AVIF→AVIF
/// is not a proven keeping path yet: the SDR base, with or without metadata.
#[test]
fn avif_to_avif_encodes_the_sdr_base_until_the_writer_is_verified() {
    for keep_metadata in [true, false] {
        let out =
            codec::transcode(GAINMAP, Target::Avif { quality: 80 }, None, keep_metadata).unwrap();
        assert_eq!(out.hdr, HdrOutcome::GainMapDropped);
        assert!(!isobmff::has_gainmap(&out.bytes));
        assert_eq!(
            metadata::extract(&out.bytes).exif.is_some(),
            keep_metadata,
            "EXIF follows the privacy choice"
        );
    }
}

#[test]
fn unreadable_gainmap_graph_still_gets_the_sdr_base() {
    let mut broken = GAINMAP.to_vec();
    let at = broken.windows(4).position(|b| b == b"dimg").unwrap();
    broken[at..at + 4].copy_from_slice(b"zzzz");
    assert!(isobmff::has_gainmap(&broken));
    assert!(isobmff::read_tmap(&broken).is_none());
    let out = codec::transcode(&broken, Target::Avif { quality: 80 }, None, true).unwrap();
    assert_eq!(out.hdr, HdrOutcome::GainMapDropped);
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
