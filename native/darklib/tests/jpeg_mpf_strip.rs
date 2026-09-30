//! Privacy strip of JPEGs that carry a gain map located by MPF (Hayn IMG-06).
//! The strip removes segments before the scan, so every MPF offset and the
//! primary image's size must move with them, or readers lose the gain map.
//! Outputs go to CARGO_TARGET_TMPDIR/jpeg-strip for the independent check
//! (test_native/inspect_jpeg_gainmap.swift: ImageIO must still find the map).

use darklib::engine::metadata::{self, StripPolicy};

const FIXTURES: [(&str, &[u8]); 3] = [
    (
        "seine_sdr_gainmap_srgb",
        include_bytes!("fixtures/seine_sdr_gainmap_srgb.jpg"),
    ),
    (
        "apple_gainmap_new",
        include_bytes!("fixtures/apple_gainmap_new.jpg"),
    ),
    (
        "apple_gainmap_old",
        include_bytes!("fixtures/apple_gainmap_old.jpg"),
    ),
];

#[test]
fn stripped_outputs_for_the_independent_reader() {
    let dir = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join("jpeg-strip");
    std::fs::create_dir_all(&dir).unwrap();
    for (name, bytes) in FIXTURES {
        let out = metadata::strip(bytes, StripPolicy::default())
            .unwrap_or_else(|e| panic!("{name}: {e:?}"));
        assert!(out.len() < bytes.len(), "{name}: nothing stripped");
        std::fs::write(dir.join(format!("{name}.jpg")), out).unwrap();
    }
}
