//! The metadata model (Hayn, docs/10-DARKLIB.md, user decision 2026-10-09):
//! metadata goes through one intermediate form, so a conversion between any
//! two containers loses only what the target cannot hold at all. Fixtures
//! written by ExifTool 13.59 and Pillow (tests/fixtures/README.md), every
//! source carried into JPEG, PNG, WebP, AVIF and HEIF.
//!
//! With `DARKLIB_METADATA_OUT` set, the outputs are written there for an
//! independent reader: `test_native/check_metadata_model.py` (ExifTool).

use darklib::engine::codec::{self, Target};
use darklib::engine::metadata::{self, Canonical, MetaKind};

const RICH: &[u8] = include_bytes!("fixtures/meta_rich.jpg");
const EXTENDED: &[u8] = include_bytes!("fixtures/meta_extended_xmp.jpg");
const ZXMP: &[u8] = include_bytes!("fixtures/meta_zxmp.png");
const HEIC: &[u8] = include_bytes!("fixtures/libheif_p3_icc.heic");

fn contains(hay: &[u8], needle: &[u8]) -> bool {
    hay.windows(needle.len()).any(|w| w == needle)
}

/// One encoded image per container, with no metadata of its own beyond a
/// profile.
fn targets() -> Vec<(&'static str, Vec<u8>)> {
    let encode = |t| codec::transcode(RICH, t, None, false).unwrap().bytes;
    vec![
        ("jpg", encode(Target::Jpeg(90))),
        ("png", encode(Target::Png)),
        (
            "webp",
            encode(Target::Webp {
                quality: 90,
                lossless: false,
            }),
        ),
        (
            "avif",
            encode(Target::Avif {
                quality: 60,
                depth: Some(8),
            }),
        ),
        ("heic", HEIC.to_vec()),
    ]
}

/// `meta` into every target: the outputs, each with what was left out.
fn carry(name: &str, meta: &Canonical) -> Vec<(&'static str, Vec<u8>, Vec<MetaKind>)> {
    let out = std::env::var("DARKLIB_METADATA_OUT").ok();
    targets()
        .into_iter()
        .map(|(ext, target)| {
            let r = metadata::inject_reporting(&target, meta);
            if let Some(dir) = &out {
                std::fs::write(format!("{dir}/{name}-to.{ext}"), &r.bytes).unwrap();
            }
            (ext, r.bytes, r.dropped)
        })
        .collect()
}

/// Whether a TIFF block's IFD0 links to an IFD1 (a thumbnail).
fn has_ifd1(tiff: &[u8]) -> bool {
    let le = &tiff[..2] == b"II";
    let u16_at = |o: usize| {
        let b = [tiff[o], tiff[o + 1]];
        if le {
            u16::from_le_bytes(b)
        } else {
            u16::from_be_bytes(b)
        }
    };
    let u32_at = |o: usize| {
        let b = [tiff[o], tiff[o + 1], tiff[o + 2], tiff[o + 3]];
        if le {
            u32::from_le_bytes(b)
        } else {
            u32::from_be_bytes(b)
        }
    };
    let ifd0 = u32_at(4) as usize;
    u32_at(ifd0 + 2 + 12 * u16_at(ifd0) as usize) != 0
}

/// EXIF, XMP, IPTC and a P3 profile from a JPEG reach every container: EXIF
/// upright and without the old thumbnail, IPTC as JPEG's APP13 or, elsewhere,
/// as the XMP the IPTC standard maps it to, the source's XMP winning.
#[test]
fn a_rich_jpeg_reaches_every_container() {
    let source = metadata::extract(RICH);
    assert_eq!(source.orientation, 6);
    assert!(
        has_ifd1(source.exif.as_ref().unwrap()),
        "the source has one"
    );
    for (ext, bytes, dropped) in carry("rich", &source) {
        assert_eq!(dropped, vec![], "{ext}: {dropped:?}");
        let back = metadata::extract(&bytes);
        let exif = back.exif.as_ref().expect(ext);
        assert_eq!(back.orientation, 1, "{ext}: upright pixels");
        assert!(!has_ifd1(exif), "{ext}: no old thumbnail");
        assert!(contains(exif, b"TestCam"), "{ext}: the camera");
        assert_eq!(back.icc, source.icc, "{ext}: the profile");
        let xmp = back.xmp.as_ref().expect(ext);
        assert!(contains(xmp, b"XMP title"), "{ext}");
        if ext == "jpg" {
            assert_eq!(back.iptc, source.iptc, "APP13 as it was");
        } else {
            // What only the IIM has goes in as XMP.
            assert!(
                contains(xmp, b"IPTC headline") && contains(xmp, b"IPTC credit"),
                "{ext}"
            );
            // What both have stays the XMP's: its IPTCDigest says the XMP is
            // current (ExifTool kept them in step), so nothing is lost.
            assert!(!contains(xmp, b"IPTC byline") && !contains(xmp, b"IPTC city"));
        }
    }
}

/// A JPEG's Extended XMP (80 KB): kept as its segments in a JPEG, one
/// packet elsewhere. It was dropped without a word before.
#[test]
fn extended_xmp_is_carried() {
    let source = metadata::extract(EXTENDED);
    let ext = source.xmp_extended.as_ref().expect("Extended XMP read");
    assert!(ext.len() > 65_000);
    for (name, bytes, dropped) in carry("extended", &source) {
        assert_eq!(dropped, vec![], "{name}");
        let back = metadata::extract(&bytes);
        if name == "jpg" {
            assert_eq!(back.xmp_extended.as_ref(), Some(ext));
        } else {
            assert!(back.xmp_extended.is_none());
            let xmp = back.xmp.unwrap();
            assert!(xmp.len() > 65_000, "{name}: one packet");
            assert!(
                !contains(&xmp, b"HasExtendedXMP"),
                "{name}: no dangling pointer"
            );
        }
    }
}

/// One packet too large for a JPEG segment (a PNG made from the Extended
/// XMP above) is split into a main packet and Extended XMP, and reads back
/// whole.
#[test]
fn a_large_packet_splits_for_jpeg() {
    let one = &carry("extended", &metadata::extract(EXTENDED))[1];
    assert_eq!(one.0, "png");
    let png = metadata::extract(&one.1);
    let jpeg = &carry("split", &png)[0];
    assert_eq!((jpeg.0, &jpeg.2), ("jpg", &vec![]));
    let back = metadata::extract(&jpeg.1);
    assert!(back.xmp.as_ref().unwrap().len() <= 65_504);
    let ext = back.xmp_extended.as_ref().expect("split");
    let description = "Extended XMP ".repeat(100);
    assert!(contains(ext, description.as_bytes()));
}

/// A PNG's compressed `iTXt` XMP is inflated into the model; it went into
/// other containers still compressed before.
#[test]
fn compressed_png_xmp_is_read() {
    let source = metadata::extract(ZXMP);
    let xmp = source.xmp.as_ref().expect("XMP");
    assert!(contains(xmp, b"Compressed XMP title"));
    for (name, bytes, dropped) in carry("zxmp", &source) {
        assert_eq!(dropped, vec![], "{name}");
        assert!(contains(
            &metadata::extract(&bytes).xmp.unwrap(),
            b"Compressed XMP title"
        ));
    }
}

/// DarkLib's own conversion carries through the same step and says what it
/// left out.
#[test]
fn transcode_carries_the_same_way() {
    let out = codec::transcode(
        RICH,
        Target::Webp {
            quality: 90,
            lossless: false,
        },
        None,
        true,
    )
    .unwrap();
    assert_eq!(out.dropped, vec![]);
    let back = metadata::extract(&out.bytes);
    assert!(contains(&back.xmp.unwrap(), b"IPTC headline"));
    assert!(!has_ifd1(&back.exif.unwrap()));
}
