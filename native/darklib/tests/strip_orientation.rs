//! IMG-07: stripping private metadata must keep the display orientation. The
//! displayed image (orientation applied by `decode`) must be identical before
//! and after, for EXIF orientations 1..=8 on a non-square, asymmetric image,
//! and the GPS data must be gone. Outputs are written to CARGO_TARGET_TMPDIR
//! for the independent ImageIO check (test_native/inspect_strip_orientation.swift).

use darklib::engine::{
    codec::{self, Decoded, Target},
    metadata::{self, exif, StripPolicy},
};

/// 6×4 with a distinct colour per pixel, so any rotation or flip shows.
fn source() -> Decoded {
    let (w, h) = (6u32, 4u32);
    let mut rgba = Vec::new();
    for y in 0..h {
        for x in 0..w {
            rgba.extend_from_slice(&[(x * 40) as u8, (y * 60) as u8, 200, 255]);
        }
    }
    Decoded {
        width: w,
        height: h,
        rgba,
    }
}

/// Little-endian TIFF: IFD0 = Orientation + GPS IFD pointer; GPS IFD = one
/// GPSLatitudeRef entry.
fn tiff(orientation: u16) -> Vec<u8> {
    let mut t = b"II\x2a\x00".to_vec();
    t.extend_from_slice(&8u32.to_le_bytes());
    t.extend_from_slice(&2u16.to_le_bytes());
    t.extend_from_slice(&[0x12, 0x01, 3, 0, 1, 0, 0, 0]);
    t.extend_from_slice(&orientation.to_le_bytes());
    t.extend_from_slice(&[0, 0]);
    let gps_at = 8 + 2 + 2 * 12 + 4;
    t.extend_from_slice(&[0x25, 0x88, 4, 0, 1, 0, 0, 0]);
    t.extend_from_slice(&(gps_at as u32).to_le_bytes());
    t.extend_from_slice(&0u32.to_le_bytes());
    t.extend_from_slice(&1u16.to_le_bytes());
    t.extend_from_slice(&[0x01, 0x00, 2, 0, 2, 0, 0, 0, b'N', 0, 0, 0]);
    t.extend_from_slice(&0u32.to_le_bytes());
    t
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0xEDB8_8320
            } else {
                crc >> 1
            };
        }
    }
    !crc
}

fn jpeg_with(tiff: &[u8]) -> Vec<u8> {
    let plain = codec::encode(&source(), Target::Jpeg(95)).unwrap();
    let mut app1 = b"Exif\0\0".to_vec();
    app1.extend_from_slice(tiff);
    let mut out = vec![0xFF, 0xD8, 0xFF, 0xE1];
    out.extend_from_slice(&((app1.len() + 2) as u16).to_be_bytes());
    out.extend_from_slice(&app1);
    out.extend_from_slice(&plain[2..]);
    out
}

fn png_with(tiff: &[u8]) -> Vec<u8> {
    let plain = codec::encode(&source(), Target::Png).unwrap();
    let ihdr_end = 8 + 12 + 13; // signature + IHDR chunk
    let mut out = plain[..ihdr_end].to_vec();
    out.extend_from_slice(&(tiff.len() as u32).to_be_bytes());
    out.extend_from_slice(b"eXIf");
    out.extend_from_slice(tiff);
    let mut crc_in = b"eXIf".to_vec();
    crc_in.extend_from_slice(tiff);
    out.extend_from_slice(&crc32(&crc_in).to_be_bytes());
    out.extend_from_slice(&plain[ihdr_end..]);
    out
}

fn riff_chunk(out: &mut Vec<u8>, fourcc: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(fourcc);
    out.extend_from_slice(&(data.len() as u32).to_le_bytes());
    out.extend_from_slice(data);
    if data.len() & 1 == 1 {
        out.push(0);
    }
}

fn webp_with(tiff: &[u8]) -> Vec<u8> {
    let src = source();
    let plain = codec::encode(
        &src,
        Target::Webp {
            quality: 100,
            lossless: true,
        },
    )
    .unwrap();
    let image_chunk = &plain[12..]; // the single VP8L chunk of a simple WebP
    let mut vp8x = vec![0x08, 0, 0, 0]; // EXIF flag
    let (w, h) = (src.width - 1, src.height - 1);
    vp8x.extend_from_slice(&w.to_le_bytes()[..3]);
    vp8x.extend_from_slice(&h.to_le_bytes()[..3]);
    let mut body = b"WEBP".to_vec();
    riff_chunk(&mut body, b"VP8X", &vp8x);
    body.extend_from_slice(image_chunk);
    riff_chunk(&mut body, b"EXIF", tiff);
    let mut out = b"RIFF".to_vec();
    out.extend_from_slice(&(body.len() as u32).to_le_bytes());
    out.extend_from_slice(&body);
    out
}

fn check(name: &str, build: fn(&[u8]) -> Vec<u8>) {
    let dir = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join("strip-orientation");
    std::fs::create_dir_all(&dir).unwrap();
    for o in 1..=8u16 {
        let src = build(&tiff(o));
        assert_eq!(
            metadata::extract(&src).orientation,
            o,
            "{name} o{o} fixture"
        );
        let out = metadata::strip(&src, StripPolicy::default()).unwrap();
        let shown = codec::decode(&src, None).unwrap();
        let after = codec::decode(&out, None).unwrap();
        assert_eq!(
            (after.width, after.height),
            (shown.width, shown.height),
            "{name} o{o} display size"
        );
        assert_eq!(after.rgba, shown.rgba, "{name} o{o} displayed pixels");
        let kept = metadata::extract(&out);
        let gps = kept
            .exif
            .as_deref()
            .and_then(exif::summarize)
            .is_some_and(|s| s.has_gps);
        assert!(!gps, "{name} o{o} GPS removed");
        let ext = name;
        std::fs::write(dir.join(format!("{name}-o{o}.{ext}")), &out).unwrap();
    }
}

#[test]
fn jpeg_strip_keeps_display_orientation() {
    check("jpg", jpeg_with);
}

#[test]
fn png_strip_keeps_display_orientation() {
    check("png", png_with);
}

#[test]
fn webp_strip_keeps_display_orientation() {
    check("webp", webp_with);
}
