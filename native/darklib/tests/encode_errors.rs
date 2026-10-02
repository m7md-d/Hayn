//! An image an encoder refuses is an error, never a panic (Hayn IMG-20). The
//! webp crate's simple calls unwrap libwebp's error: a 195 MP lossy WebP
//! (`VP8_ENC_ERROR_PARTITION0_OVERFLOW`) panicked after 87 s on a desktop and
//! failed only because the FFI layer caught it. A width past WebP's 16383
//! limit reaches the same unwrap cheaply.

use darklib::engine::codec::{encode, Decoded, Target};

#[test]
fn webp_past_its_size_limit_is_an_error() {
    let img = Decoded {
        width: 16384,
        height: 1,
        rgba: vec![128; 16384 * 4],
    };
    for lossless in [false, true] {
        let out = std::panic::catch_unwind(|| {
            encode(
                &img,
                Target::Webp {
                    quality: 80,
                    lossless,
                },
            )
        });
        assert!(out.expect("no panic").is_err(), "lossless {lossless}");
    }
}

#[test]
fn webp_still_encodes_what_fits() {
    let img = Decoded {
        width: 64,
        height: 48,
        rgba: vec![128; 64 * 48 * 4],
    };
    let out = encode(
        &img,
        Target::Webp {
            quality: 80,
            lossless: false,
        },
    )
    .unwrap();
    assert_eq!(&out[..4], b"RIFF");
}
