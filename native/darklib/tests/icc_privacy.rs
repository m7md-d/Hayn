//! Converting without metadata must keep what the pixel values mean (Hayn
//! IMG-08): the private metadata (EXIF/XMP/IPTC) goes, the colour profile
//! stays. Pairs are written to CARGO_TARGET_TMPDIR/icc-privacy for the
//! colour-managed comparison (test_native/compare_colour_privacy.swift),
//! with a control that drops the profile, as the old code did.

use darklib::engine::{
    codec::{self, Target},
    metadata::{self, IccPolicy, OrientationPolicy, StripPolicy},
};

const P3_PNG: &[u8] = include_bytes!("fixtures/apple_png_p3_icc.png");
const P3_JPEG_EXIF: &[u8] = include_bytes!("fixtures/apple_gainmap_new.jpg");
const LOSSLESS_WEBP: Target = Target::Webp {
    quality: 100,
    lossless: true,
};

fn contains(hay: &[u8], needle: &[u8]) -> bool {
    hay.windows(needle.len()).any(|w| w == needle)
}

#[test]
fn private_metadata_goes_colour_stays() {
    let dir = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join("icc-privacy");
    std::fs::create_dir_all(&dir).unwrap();
    let write = |name: &str, bytes: &[u8]| std::fs::write(dir.join(name), bytes).unwrap();

    // A P3 PNG described by cICP alone: the fixture with its iCCP removed.
    let cicp_only = metadata::strip(
        P3_PNG,
        StripPolicy {
            icc: IccPolicy::Strip,
            orientation: OrientationPolicy::Keep,
        },
    )
    .unwrap();
    assert!(contains(&cicp_only, b"cICP") && !contains(&cicp_only, b"iCCP"));
    write("cicp_only.png", &cicp_only);
    write("icc_p3.png", P3_PNG);
    write("exif_p3.jpg", P3_JPEG_EXIF);

    for (source, from, target, name) in [
        (P3_PNG, "icc_p3.png", LOSSLESS_WEBP, "icc_p3-to.webp"),
        (
            &cicp_only[..],
            "cicp_only.png",
            LOSSLESS_WEBP,
            "cicp_only-to.webp",
        ),
        (P3_JPEG_EXIF, "exif_p3.jpg", Target::Png, "exif_p3-to.png"),
    ] {
        let out = codec::transcode(source, target, None, false).unwrap().bytes;
        assert!(
            metadata::extract(&out).icc.is_some(),
            "{from}: profile lost"
        );
        let kept = metadata::extract(&out);
        assert!(
            kept.exif.is_none() && kept.xmp.is_none(),
            "{from}: private data kept"
        );
        write(name, &out);
    }

    // The old behaviour, for the comparison to tell right from wrong.
    let control = codec::encode(&codec::decode(P3_PNG, None).unwrap(), LOSSLESS_WEBP).unwrap();
    assert!(metadata::extract(&control).icc.is_none());
    write("control_no_profile.webp", &control);
    let control = codec::encode(&codec::decode(P3_JPEG_EXIF, None).unwrap(), Target::Png).unwrap();
    assert!(metadata::extract(&control).icc.is_none());
    write("control_jpeg_no_profile.png", &control);
}
