//! The decode budget is checked from the header, before any pixel buffer
//! (Hayn RUN-01). A header claiming more than MAX_DECODE_PIXELS is refused as
//! TooLarge, not reported as a malformed file, and nothing is allocated for it:
//! these files carry almost no pixel data.

use darklib::engine::{
    codec::{self, header_dimensions, MAX_DECODE_PIXELS},
    error::DarkError,
};

/// CRC-32 (ISO 3309) as PNG chunks carry it; the PNG decoder checks it.
fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &byte in data {
        crc ^= byte as u32;
        for _ in 0..8 {
            crc = if crc & 1 == 1 {
                (crc >> 1) ^ 0xEDB8_8320
            } else {
                crc >> 1
            };
        }
    }
    !crc
}

/// PNG signature + IHDR for `w`×`h` RGBA8 + one tiny IDAT + IEND.
fn png_header(w: u32, h: u32) -> Vec<u8> {
    let mut p = vec![137, 80, 78, 71, 13, 10, 26, 10];
    let chunk = |p: &mut Vec<u8>, kind: &[u8], data: &[u8]| {
        p.extend_from_slice(&(data.len() as u32).to_be_bytes());
        p.extend_from_slice(kind);
        p.extend_from_slice(data);
        let body: Vec<u8> = kind.iter().chain(data).copied().collect();
        p.extend_from_slice(&crc32(&body).to_be_bytes());
    };
    let mut ihdr = w.to_be_bytes().to_vec();
    ihdr.extend_from_slice(&h.to_be_bytes());
    ihdr.extend_from_slice(&[8, 6, 0, 0, 0]);
    chunk(&mut p, b"IHDR", &ihdr);
    chunk(
        &mut p,
        b"IDAT",
        &[0x78, 0x9c, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01],
    );
    chunk(&mut p, b"IEND", &[]);
    p
}

/// A baseline JPEG whose SOF0 claims `w`×`h` (3 components).
fn jpeg_header(w: u16, h: u16) -> Vec<u8> {
    let mut j = vec![0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 8];
    j.extend_from_slice(&h.to_be_bytes());
    j.extend_from_slice(&w.to_be_bytes());
    j.extend_from_slice(&[3, 1, 0x11, 0, 2, 0x11, 1, 3, 0x11, 1]);
    j.extend_from_slice(&[0xFF, 0xD9]);
    j
}

/// A lossless WebP (VP8L) whose header claims `w`×`h`.
fn webp_header(w: u32, h: u32) -> Vec<u8> {
    let bits = (w - 1) | ((h - 1) << 14);
    let mut vp8l = vec![0x2f];
    vp8l.extend_from_slice(&bits.to_le_bytes());
    vp8l.extend_from_slice(&[0; 8]);
    let mut riff = b"RIFF".to_vec();
    riff.extend_from_slice(&((4 + 8 + vp8l.len()) as u32).to_le_bytes());
    riff.extend_from_slice(b"WEBP");
    riff.extend_from_slice(b"VP8L");
    riff.extend_from_slice(&(vp8l.len() as u32).to_le_bytes());
    riff.extend_from_slice(&vp8l);
    riff
}

#[test]
fn oversized_headers_are_refused_as_too_large() {
    for (name, bytes, dims) in [
        ("png", png_header(20_000, 20_000), (20_000, 20_000)),
        ("jpeg", jpeg_header(65_000, 65_000), (65_000, 65_000)),
    ] {
        assert_eq!(header_dimensions(&bytes), Some(dims), "{name}");
        assert!((dims.0 as u64) * (dims.1 as u64) > MAX_DECODE_PIXELS);
        assert_eq!(
            codec::decode(&bytes, None).err(),
            Some(DarkError::TooLarge),
            "{name}"
        );
    }
}

/// A still WebP stores each side in 14 bits, so its largest size, 16384²,
/// equals the budget: the header is read, and the budget lets it through.
#[test]
fn largest_still_webp_is_within_budget() {
    let bytes = webp_header(16_384, 16_384);
    assert_eq!(header_dimensions(&bytes), Some((16_384, 16_384)));
    assert_eq!(16_384u64 * 16_384, MAX_DECODE_PIXELS);
    assert_ne!(codec::decode(&bytes, None).err(), Some(DarkError::TooLarge));
}

#[test]
fn header_dimensions_match_the_decode() {
    for (name, bytes) in [
        (
            "sofa grid",
            &include_bytes!("fixtures/sofa_grid1x5_420.avif")[..],
        ),
        (
            "paris avif",
            include_bytes!("fixtures/paris_icc_exif_xmp.avif"),
        ),
        (
            "paris png",
            include_bytes!("fixtures/paris_icc_exif_xmp.png"),
        ),
        (
            "jpeg",
            include_bytes!("fixtures/seine_sdr_gainmap_srgb.jpg"),
        ),
        (
            "webp",
            include_bytes!("fixtures/pillow_webp_lossy_alpha.webp"),
        ),
    ] {
        let img = codec::decode(bytes, None).unwrap();
        assert_eq!(
            header_dimensions(bytes),
            Some((img.width, img.height)),
            "{name}"
        );
    }
}

/// The plan learns a source's size from `inspect`, before any decode, so a
/// giant image is planned as one (RUN-01: over 64 MP, JPEG and HEIC only).
#[test]
fn inspect_reports_the_header_size() {
    use darklib::engine::inspect::inspect;
    let big = jpeg_header(16_128, 12_096);
    let facts = inspect(&big);
    assert_eq!((facts.width, facts.height), (16_128, 12_096));
    let heic = include_bytes!("fixtures/apple_heic_alpha.heic");
    let facts = inspect(heic);
    assert_eq!((facts.width, facts.height), (64, 48));
    let unknown = inspect(b"not an image at all");
    assert_eq!((unknown.width, unknown.height), (0, 0));
}

/// The orientation the stored pixels need, as an EXIF code: `irot`/`imir`
/// for HEIF/AVIF, the EXIF tag otherwise, 0 when the file names none. The
/// tiled HEIC encoder (RUN-01) reads stored pixels and writes this back.
#[test]
fn inspect_reports_the_orientation() {
    use darklib::engine::inspect::inspect;
    use darklib::engine::metadata::isobmff;
    let rotated = include_bytes!("fixtures/abc_color_irot_alpha_irot.avif");
    let (angle, mirror) = isobmff::read_orientation(rotated).unwrap();
    assert_eq!(
        inspect(rotated).orientation,
        isobmff::exif_orientation(angle, mirror)
    );
    assert_ne!(inspect(rotated).orientation, 1);
    // Apple's JPEG names its orientation in EXIF.
    let jpeg = include_bytes!("fixtures/apple_gainmap_new.jpg");
    let tag = darklib::engine::metadata::extract(jpeg).orientation;
    assert!((1..=8).contains(&tag));
    assert_eq!(inspect(jpeg).orientation as u16, tag);
    assert_eq!(inspect(&jpeg_header(64, 48)).orientation, 0);
    assert_eq!(inspect(b"not an image at all").orientation, 0);
}
