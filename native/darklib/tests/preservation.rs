use darklib::engine::{
    codec::{self, Target},
    metadata::{self, isobmff},
};

const PQ: &[u8] = include_bytes!("fixtures/seine_hdr_rec2020.avif");
const GAINMAP: &[u8] = include_bytes!("fixtures/seine_sdr_gainmap_srgb.avif");

#[test]
fn pq_must_not_silently_become_sdr() {
    assert_eq!(isobmff::extract_nclx(PQ), Some((9, 16)));
    assert!(codec::transcode_keep_metadata(PQ, Target::Avif { quality: 80 }, None).is_err());
    assert!(codec::transcode(PQ, Target::Png, None).is_err());
}

#[test]
fn gainmap_must_not_be_dropped_by_target_or_resize() {
    assert!(isobmff::has_gainmap(GAINMAP));
    assert!(codec::transcode_keep_metadata(
        GAINMAP,
        Target::Webp {
            quality: 80,
            lossless: false
        },
        None
    )
    .is_err());
    assert!(
        codec::transcode_keep_metadata(GAINMAP, Target::Avif { quality: 80 }, Some(64)).is_err()
    );
}

#[test]
fn removing_private_metadata_does_not_authorize_hdr_loss() {
    assert!(codec::transcode(GAINMAP, Target::Avif { quality: 80 }, None).is_err());
}

#[test]
fn unreadable_gainmap_graph_must_not_trigger_sdr_recovery() {
    let mut broken = GAINMAP.to_vec();
    let at = broken.windows(4).position(|b| b == b"dimg").unwrap();
    broken[at..at + 4].copy_from_slice(b"zzzz");
    assert!(isobmff::has_gainmap(&broken));
    assert!(isobmff::read_tmap(&broken).is_none());
    assert!(codec::transcode_keep_metadata(&broken, Target::Avif { quality: 80 }, None).is_err());
}

#[test]
fn exif_rotation_must_not_desynchronize_base_and_gainmap() {
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
    assert!(isobmff::has_gainmap(&source));
    assert!(codec::transcode_keep_metadata(&source, Target::Avif { quality: 80 }, None).is_err());
}
