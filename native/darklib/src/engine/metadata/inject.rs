//! Metadata INJECTION — embed EXIF / XMP / ICC from a [`Canonical`] into an
//! encoded image (the inverse of `extract`). Used to CARRY metadata through a
//! re-encode (compress/convert) so it isn't lost.
//!
//! Orientation in the carried EXIF is normalised to 1: the pixels are baked
//! upright on decode, so a non-1 tag would double-rotate (single source of
//! truth — CLAUDE.md / docs/10-DARKLIB.md §5). JPEG, PNG, WebP and AVIF/HEIF are
//! all covered. Best-effort: a format without an injector returns the encoded
//! bytes unchanged.

use super::{exif, Canonical};
use crate::engine::format::{detect, ImageFormat};

const XMP_SIG: &[u8] = b"http://ns.adobe.com/xap/1.0/\0";

/// Embed `meta` into `encoded` (same container).
pub fn inject(encoded: &[u8], meta: &Canonical) -> Vec<u8> {
    match detect(encoded) {
        ImageFormat::Jpeg => inject_jpeg(encoded, meta),
        ImageFormat::Png => inject_png(encoded, meta),
        ImageFormat::Webp => inject_webp(encoded, meta),
        ImageFormat::Avif | ImageFormat::Heic => inject_isobmff(encoded, meta),
        _ => encoded.to_vec(),
    }
}

/// AVIF / HEIF (ISOBMFF) add-item inject. Normalises the EXIF orientation and the
/// XMP packet here, then hands the clean blobs to the container surgery (which
/// rebuilds `meta` + `mdat` with fresh offsets and self-validates). ICC is added
/// as a `colr`/`prof` property — `Canonical.icc` is already the raw profile.
fn inject_isobmff(b: &[u8], meta: &Canonical) -> Vec<u8> {
    let exif = meta.exif.as_ref().map(|t| exif::with_orientation_1(t));
    let xmp = meta.xmp.as_ref().map(|x| xmp_packet(x).to_vec());
    super::isobmff::inject(b, exif.as_deref(), xmp.as_deref(), meta.icc.as_deref())
}

/// Each kind `meta` carries replaces the target's own (a JPEG from Android's
/// Bitmap.compress already names its bitmap's profile, Hayn IMG-24): two
/// "chunk 1 of 1" profiles make readers drop both. A kind `meta` lacks stays,
/// since the target's may be the only one naming its pixels. A leading JFIF
/// segment stays first; every other segment and the scan stay as they were.
fn inject_jpeg(jpeg: &[u8], meta: &Canonical) -> Vec<u8> {
    if jpeg.len() < 2 || jpeg[0] != 0xFF || jpeg[1] != 0xD8 {
        return jpeg.to_vec();
    }
    let replaced = |marker: u8, payload: &[u8]| match marker {
        0xE1 => {
            (meta.exif.is_some() && payload.starts_with(b"Exif\0\0"))
                || (meta.xmp.is_some() && payload.starts_with(XMP_SIG))
        }
        0xE2 => meta.icc.is_some() && payload.starts_with(b"ICC_PROFILE\0"),
        _ => false,
    };
    // Header segments up to the scan; anything unparsed is copied as it is.
    let mut kept: Vec<&[u8]> = Vec::new();
    let mut i = 2;
    while i + 4 <= jpeg.len() && jpeg[i] == 0xFF {
        let marker = jpeg[i + 1];
        if marker == 0xDA || marker == 0xD9 || marker == 0xFF {
            break;
        }
        let n = u16::from_be_bytes([jpeg[i + 2], jpeg[i + 3]]) as usize;
        if n < 2 || i + 2 + n > jpeg.len() {
            break;
        }
        if !replaced(marker, &jpeg[i + 4..i + 2 + n]) {
            kept.push(&jpeg[i..i + 2 + n]);
        }
        i += 2 + n;
    }
    let jfif = kept
        .first()
        .is_some_and(|s| s[1] == 0xE0 && s[4..].starts_with(b"JFIF\0"));

    let mut out = Vec::with_capacity(jpeg.len() + 1024);
    out.extend_from_slice(&[0xFF, 0xD8]);
    if jfif {
        out.extend_from_slice(kept[0]);
    }

    if let Some(tiff) = &meta.exif {
        let mut payload = b"Exif\0\0".to_vec();
        payload.extend_from_slice(&exif::with_orientation_1(tiff));
        app_segment(&mut out, 0xE1, &payload);
    }
    if let Some(xmp) = &meta.xmp {
        let mut payload = XMP_SIG.to_vec();
        payload.extend_from_slice(xmp);
        app_segment(&mut out, 0xE1, &payload);
    }
    if let Some(icc) = &meta.icc {
        // Single-chunk ICC (profiles up to ~64 KB; larger would need splitting).
        if icc.len() <= 65515 {
            let mut payload = b"ICC_PROFILE\0".to_vec();
            payload.push(1); // chunk seq
            payload.push(1); // chunk count
            payload.extend_from_slice(icc);
            app_segment(&mut out, 0xE2, &payload);
        }
    }
    for segment in &kept[jfif as usize..] {
        out.extend_from_slice(segment);
    }
    out.extend_from_slice(&jpeg[i..]); // the scan and the rest, unchanged
    out
}

/// Append an `FFxx` APPn segment (skips it if the payload exceeds the u16 limit).
fn app_segment(out: &mut Vec<u8>, marker: u8, payload: &[u8]) {
    if payload.len() + 2 > 0xFFFF {
        return;
    }
    out.push(0xFF);
    out.push(marker);
    out.extend_from_slice(&((payload.len() + 2) as u16).to_be_bytes());
    out.extend_from_slice(payload);
}

/// As for JPEG, each kind `meta` carries replaces the target's own chunk (a
/// PNG holds one `iCCP` at most); a kind it lacks stays.
fn inject_png(png: &[u8], meta: &Canonical) -> Vec<u8> {
    const SIG: [u8; 8] = [137, 80, 78, 71, 13, 10, 26, 10];
    // Insert right after IHDR (sig 8 + len 4 + "IHDR" 4 + data 13 + crc 4 = 33).
    let ihdr_end = 33usize;
    if png.len() < ihdr_end || png[..8] != SIG || &png[12..16] != b"IHDR" {
        return png.to_vec();
    }
    let replaced = |kind: &[u8], data: &[u8]| match kind {
        b"iCCP" => meta.icc.is_some(),
        b"eXIf" => meta.exif.is_some(),
        b"iTXt" => meta.xmp.is_some() && data.starts_with(b"XML:com.adobe.xmp\0"),
        _ => false,
    };
    // The chunks after IHDR, less the replaced ones; an unparsed tail stays.
    let mut rest = Vec::with_capacity(png.len() - ihdr_end);
    let mut i = ihdr_end;
    while i + 12 <= png.len() {
        let n = u32::from_be_bytes([png[i], png[i + 1], png[i + 2], png[i + 3]]) as usize;
        let Some(end) = (i + 12).checked_add(n).filter(|&e| e <= png.len()) else {
            break;
        };
        if !replaced(&png[i + 4..i + 8], &png[i + 8..i + 8 + n]) {
            rest.extend_from_slice(&png[i..end]);
        }
        i = end;
    }
    rest.extend_from_slice(&png[i..]);
    let mut out = png[..ihdr_end].to_vec();
    if let Some(tiff) = &meta.exif {
        png_chunk(&mut out, b"eXIf", &exif::with_orientation_1(tiff));
    }
    if let Some(xmp) = &meta.xmp {
        if xmp.starts_with(b"XML:com.adobe.xmp\0") {
            png_chunk(&mut out, b"iTXt", xmp); // already an iTXt payload (PNG source)
        } else {
            let mut p = b"XML:com.adobe.xmp\0".to_vec();
            p.extend_from_slice(&[0, 0, 0, 0]); // comp flag, method, empty lang\0, empty transkw\0
            p.extend_from_slice(xmp);
            png_chunk(&mut out, b"iTXt", &p);
        }
    }
    if let Some(icc) = &meta.icc {
        png_chunk(&mut out, b"iCCP", &build_iccp(icc)); // before PLTE/IDAT
    }
    out.extend_from_slice(&rest);
    out
}

/// Build a PNG `iCCP` chunk body from a raw ICC profile: a short profile name, a
/// null terminator, compression method 0 (zlib), then the zlib-compressed
/// profile (the inverse of `extract`'s `decode_iccp`).
fn build_iccp(icc: &[u8]) -> Vec<u8> {
    let compressed = miniz_oxide::deflate::compress_to_vec_zlib(icc, 6);
    let mut data = Vec::with_capacity(compressed.len() + 5);
    data.extend_from_slice(b"icc"); // profile name (1..=79 Latin-1)
    data.push(0); // name terminator
    data.push(0); // compression method: 0 = zlib/deflate
    data.extend_from_slice(&compressed);
    data
}

pub(super) fn png_chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    out.extend_from_slice(kind);
    out.extend_from_slice(data);
    let mut crc_in = kind.to_vec();
    crc_in.extend_from_slice(data);
    out.extend_from_slice(&crc32(&crc_in).to_be_bytes());
}

/// CRC-32 (IEEE) as used by PNG chunks.
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

// ── WebP (RIFF mux) ────────────────────────────────────────────────────────
// libwebp emits a SIMPLE file (`VP8 `/`VP8L`, or `VP8X`+`ALPH`+`VP8 ` for lossy
// with alpha). To carry metadata we rebuild it as the EXTENDED form: a `VP8X`
// header (canvas size + feature flags), then in spec order `ICCP` (before the
// image), the coded image chunks verbatim, then `EXIF` and `XMP `. Assumes the
// input is freshly encoded (no metadata chunks) — any existing EXIF/XMP/ICCP is
// rewritten from `meta`. A malformed / unrecognised layout is returned as-is.
const VP8X_ICC: u8 = 0x20;
const VP8X_ALPHA: u8 = 0x10;
const VP8X_EXIF: u8 = 0x08;
const VP8X_XMP: u8 = 0x04;
const VP8X_ANIM: u8 = 0x02;

fn inject_webp(webp: &[u8], meta: &Canonical) -> Vec<u8> {
    if meta.exif.is_none() && meta.xmp.is_none() && meta.icc.is_none() {
        return webp.to_vec();
    }
    mux_webp(webp, meta).unwrap_or_else(|| webp.to_vec())
}

fn mux_webp(b: &[u8], meta: &Canonical) -> Option<Vec<u8>> {
    if b.len() < 12 || &b[0..4] != b"RIFF" || &b[8..12] != b"WEBP" {
        return None;
    }
    // Walk the chunks: keep the coded image (+ alpha/anim) verbatim, note the
    // canvas size + features, and drop any existing metadata chunk (re-injected).
    let mut image_chunks: Vec<&[u8]> = Vec::new();
    let mut canvas: Option<(u32, u32)> = None;
    let mut flags: u8 = 0;
    let mut i = 12usize;
    while i + 8 <= b.len() {
        let fourcc = &b[i..i + 4];
        let size = u32::from_le_bytes([b[i + 4], b[i + 5], b[i + 6], b[i + 7]]) as usize;
        let chunk_end = i + 8 + size + (size & 1); // chunks pad to an even length
        if chunk_end > b.len() {
            return None;
        }
        let payload = &b[i + 8..i + 8 + size];
        match fourcc {
            b"VP8X" if size >= 10 => {
                flags |= payload[0] & (VP8X_ALPHA | VP8X_ANIM); // keep alpha/anim
                let w = u32::from(payload[4])
                    | u32::from(payload[5]) << 8
                    | u32::from(payload[6]) << 16;
                let h = u32::from(payload[7])
                    | u32::from(payload[8]) << 8
                    | u32::from(payload[9]) << 16;
                canvas = Some((w + 1, h + 1));
            }
            b"ICCP" | b"EXIF" | b"XMP " => {} // rewritten from `meta` below
            b"ALPH" => {
                flags |= VP8X_ALPHA;
                image_chunks.push(&b[i..chunk_end]);
            }
            b"ANIM" | b"ANMF" => {
                flags |= VP8X_ANIM;
                image_chunks.push(&b[i..chunk_end]);
            }
            b"VP8 " => {
                canvas = canvas.or_else(|| vp8_dimensions(payload));
                image_chunks.push(&b[i..chunk_end]);
            }
            b"VP8L" => {
                canvas = canvas.or_else(|| vp8l_dimensions(payload));
                if vp8l_has_alpha(payload) {
                    flags |= VP8X_ALPHA;
                }
                image_chunks.push(&b[i..chunk_end]);
            }
            _ => image_chunks.push(&b[i..chunk_end]),
        }
        i = chunk_end;
    }
    let (w, h) = canvas?;
    if w == 0 || h == 0 || w > (1 << 24) || h > (1 << 24) {
        return None; // out of the 24-bit VP8X canvas range
    }

    if meta.icc.is_some() {
        flags |= VP8X_ICC;
    }
    if meta.exif.is_some() {
        flags |= VP8X_EXIF;
    }
    if meta.xmp.is_some() {
        flags |= VP8X_XMP;
    }

    let mut body: Vec<u8> = Vec::with_capacity(b.len() + 1024);
    let mut vp8x = Vec::with_capacity(10);
    vp8x.push(flags);
    vp8x.extend_from_slice(&[0, 0, 0]); // reserved
    vp8x.extend_from_slice(&(w - 1).to_le_bytes()[..3]); // 24-bit (canvas w - 1)
    vp8x.extend_from_slice(&(h - 1).to_le_bytes()[..3]); // 24-bit (canvas h - 1)
    riff_chunk(&mut body, b"VP8X", &vp8x);

    if let Some(icc) = &meta.icc {
        riff_chunk(&mut body, b"ICCP", icc); // must precede the image data
    }
    for c in &image_chunks {
        body.extend_from_slice(c);
    }
    if let Some(tiff) = &meta.exif {
        // WebP EXIF chunk is the raw TIFF; orientation normalised (pixels baked).
        riff_chunk(&mut body, b"EXIF", &exif::with_orientation_1(tiff));
    }
    if let Some(xmp) = &meta.xmp {
        riff_chunk(&mut body, b"XMP ", xmp_packet(xmp));
    }

    let riff_size = (4 + body.len()) as u32; // 'WEBP' + chunks
    let mut out = Vec::with_capacity(8 + body.len());
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&riff_size.to_le_bytes());
    out.extend_from_slice(b"WEBP");
    out.extend_from_slice(&body);
    Some(out)
}

/// Append a RIFF chunk: fourcc + LE u32 size + payload + a pad byte to even.
pub(super) fn riff_chunk(out: &mut Vec<u8>, fourcc: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(fourcc);
    out.extend_from_slice(&(data.len() as u32).to_le_bytes());
    out.extend_from_slice(data);
    if data.len() & 1 == 1 {
        out.push(0);
    }
}

/// Canvas size from a VP8 (lossy) keyframe: start code `9d 01 2a` then two
/// 14-bit little-endian dimensions.
fn vp8_dimensions(p: &[u8]) -> Option<(u32, u32)> {
    if p.len() < 10 || p[3] != 0x9d || p[4] != 0x01 || p[5] != 0x2a {
        return None;
    }
    let w = (u32::from(p[6]) | u32::from(p[7]) << 8) & 0x3FFF;
    let h = (u32::from(p[8]) | u32::from(p[9]) << 8) & 0x3FFF;
    Some((w, h))
}

/// Canvas size from a VP8L (lossless) header: `0x2f` then 14-bit (w-1), 14-bit
/// (h-1), read LSB-first.
fn vp8l_dimensions(p: &[u8]) -> Option<(u32, u32)> {
    if p.len() < 5 || p[0] != 0x2f {
        return None;
    }
    let bits = u32::from_le_bytes([p[1], p[2], p[3], p[4]]);
    Some(((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1))
}

/// The VP8L `alpha_is_used` bit (bit 28, right after the two 14-bit dimensions).
fn vp8l_has_alpha(p: &[u8]) -> bool {
    p.len() >= 5 && p[0] == 0x2f && (u32::from_le_bytes([p[1], p[2], p[3], p[4]]) >> 28) & 1 == 1
}

/// Unwrap a PNG `iTXt`-wrapped XMP down to its bare packet. XMP extracted from a
/// PNG keeps the `XML:com.adobe.xmp` keyword plus the compression and language
/// fields inside [`Canonical`]; JPEG and WebP want only the packet. Input that is
/// not so wrapped passes through unchanged.
fn xmp_packet(xmp: &[u8]) -> &[u8] {
    let Some(rest) = xmp.strip_prefix(b"XML:com.adobe.xmp\0".as_slice()) else {
        return xmp;
    };
    if rest.len() < 2 {
        return xmp;
    }
    // Skip comp flag + method, then the language tag + translated keyword
    // (each null-terminated); the remainder is the packet.
    let after = &rest[2..];
    let mut seen = 0;
    for (idx, &byte) in after.iter().enumerate() {
        if byte == 0 {
            seen += 1;
            if seen == 2 {
                return &after[idx + 1..];
            }
        }
    }
    xmp
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::metadata::extract;

    fn tiff_orientation(o: u16) -> Vec<u8> {
        let mut t = b"II\x2a\x00\x08\x00\x00\x00".to_vec();
        t.extend_from_slice(&1u16.to_le_bytes());
        t.extend_from_slice(&0x0112u16.to_le_bytes()); // Orientation
        t.extend_from_slice(&3u16.to_le_bytes()); // SHORT
        t.extend_from_slice(&1u32.to_le_bytes());
        t.extend_from_slice(&(o as u32).to_le_bytes());
        t.extend_from_slice(&0u32.to_le_bytes());
        t
    }

    fn minimal_jpeg() -> Vec<u8> {
        // >= 12 bytes so `detect` recognises it (real encoded JPEGs always are).
        let mut j = vec![0xFF, 0xD8]; // SOI
        j.extend_from_slice(&[0xFF, 0xDA, 0x00, 0x08, 1, 1, 0, 0, 0, 0]); // SOS header
        j.extend_from_slice(&[0xAA, 0xBB, 0xCC]); // entropy
        j.extend_from_slice(&[0xFF, 0xD9]); // EOI
        j
    }

    fn contains(hay: &[u8], needle: &[u8]) -> bool {
        hay.windows(needle.len()).any(|w| w == needle)
    }

    #[test]
    fn jpeg_inject_carries_exif_xmp_normalising_orientation() {
        let meta = Canonical {
            exif: Some(tiff_orientation(6)),
            xmp: Some(b"<x:xmpmeta>hi</x:xmpmeta>".to_vec()),
            ..Default::default()
        };
        let out = inject(&minimal_jpeg(), &meta);
        // Round-trips through extract: EXIF present, orientation normalised to 1.
        let back = extract(&out);
        assert!(back.exif.is_some());
        assert_eq!(back.orientation, 1, "orientation normalised (pixels baked)");
        assert!(contains(&out, b"<x:xmpmeta>hi</x:xmpmeta>"), "XMP carried");
    }

    /// `(marker, payload)` of each header segment of `jpeg` before SOS.
    fn jpeg_segments(jpeg: &[u8]) -> Vec<(u8, Vec<u8>)> {
        let mut out = Vec::new();
        let mut i = 2;
        while jpeg[i + 1] != 0xDA {
            let n = u16::from_be_bytes([jpeg[i + 2], jpeg[i + 3]]) as usize;
            out.push((jpeg[i + 1], jpeg[i + 4..i + 2 + n].to_vec()));
            i += 2 + n;
        }
        out
    }

    fn icc_payload(profile: &[u8]) -> Vec<u8> {
        let mut p = b"ICC_PROFILE\0\x01\x01".to_vec();
        p.extend_from_slice(profile);
        p
    }

    /// A target that came tagged: Android's Bitmap.compress writes the
    /// bitmap's own profile (Hayn IMG-24). Injecting must replace it, as it
    /// replaces EXIF and XMP, not add a second "chunk 1 of 1" that readers
    /// reject; the JFIF segment stays first and the rest stays.
    #[test]
    fn jpeg_inject_replaces_the_targets_own_metadata() {
        let mut target = vec![0xFF, 0xD8];
        app_segment(&mut target, 0xE0, b"JFIF\0\x01\x01\0\0\x01\0\x01\0\0");
        app_segment(&mut target, 0xE2, &icc_payload(b"old profile"));
        let mut old_exif = b"Exif\0\0".to_vec();
        old_exif.extend_from_slice(&tiff_orientation(3));
        app_segment(&mut target, 0xE1, &old_exif);
        let mut old_xmp = XMP_SIG.to_vec();
        old_xmp.extend_from_slice(b"<old/>");
        app_segment(&mut target, 0xE1, &old_xmp);
        app_segment(&mut target, 0xE2, b"MPF\0kept");
        app_segment(&mut target, 0xFE, b"comment kept");
        target.extend_from_slice(&minimal_jpeg()[2..]);
        let meta = Canonical {
            exif: Some(tiff_orientation(6)),
            xmp: Some(b"<new/>".to_vec()),
            icc: Some(b"new profile".to_vec()),
            ..Default::default()
        };
        let out = inject(&target, &meta);
        let segments = jpeg_segments(&out);
        assert!(segments[0].1.starts_with(b"JFIF\0"), "JFIF first");
        let iccs: Vec<_> = segments
            .iter()
            .filter(|(m, p)| *m == 0xE2 && p.starts_with(b"ICC_PROFILE\0"))
            .collect();
        assert_eq!(iccs.len(), 1, "one profile");
        assert_eq!(iccs[0].1, icc_payload(b"new profile"));
        let exifs = segments
            .iter()
            .filter(|(m, p)| *m == 0xE1 && p.starts_with(b"Exif\0\0"))
            .count();
        assert_eq!(exifs, 1, "one EXIF");
        assert_eq!(extract(&out).orientation, 1);
        assert!(!contains(&out, b"<old/>") && contains(&out, b"<new/>"));
        assert!(contains(&out, b"MPF\0kept") && contains(&out, b"comment kept"));
        assert!(
            out.ends_with(&minimal_jpeg()[2..]),
            "entropy data untouched"
        );
    }

    /// What the source does not carry, the target keeps: its own profile may
    /// be the only one naming its pixels.
    #[test]
    fn jpeg_inject_keeps_what_the_source_lacks() {
        let mut target = vec![0xFF, 0xD8];
        app_segment(&mut target, 0xE2, &icc_payload(b"target profile"));
        target.extend_from_slice(&minimal_jpeg()[2..]);
        let meta = Canonical {
            exif: Some(tiff_orientation(1)),
            ..Default::default()
        };
        let out = inject(&target, &meta);
        assert_eq!(extract(&out).icc.as_deref(), Some(&b"target profile"[..]));
        assert!(extract(&out).exif.is_some());
    }

    #[test]
    fn png_inject_replaces_the_targets_own_metadata() {
        let mut png = vec![137, 80, 78, 71, 13, 10, 26, 10];
        png_chunk(&mut png, b"IHDR", &[0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0]);
        png_chunk(&mut png, b"iCCP", &build_iccp(b"old profile"));
        png_chunk(&mut png, b"eXIf", &tiff_orientation(3));
        png_chunk(&mut png, b"iTXt", b"XML:com.adobe.xmp\0\0\0\0\0<old/>");
        png_chunk(&mut png, b"tEXt", b"Comment\0kept");
        png_chunk(&mut png, b"IEND", &[]);
        let meta = Canonical {
            exif: Some(tiff_orientation(6)),
            xmp: Some(b"<new/>".to_vec()),
            icc: Some(b"new profile".to_vec()),
            ..Default::default()
        };
        let out = inject(&png, &meta);
        let count = |kind: &[u8]| out.windows(4).filter(|w| *w == kind).count();
        assert_eq!((count(b"iCCP"), count(b"eXIf"), count(b"iTXt")), (1, 1, 1));
        let back = extract(&out);
        assert_eq!(back.icc.as_deref(), Some(&b"new profile"[..]));
        assert_eq!(back.orientation, 1);
        assert!(!contains(&out, b"<old/>") && contains(&out, b"<new/>"));
        assert!(contains(&out, b"Comment\0kept"));
        assert!(out.ends_with(&png[png.len() - 12..]), "IEND last");
    }

    #[test]
    fn png_inject_carries_exif() {
        // A minimal valid PNG header (sig + IHDR) + IEND is enough for our parser.
        let mut png = vec![137, 80, 78, 71, 13, 10, 26, 10];
        super::png_chunk(&mut png, b"IHDR", &[0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0]);
        super::png_chunk(&mut png, b"IEND", &[]);
        let meta = Canonical {
            exif: Some(tiff_orientation(8)),
            ..Default::default()
        };
        let out = inject(&png, &meta);
        let back = extract(&out);
        assert!(back.exif.is_some(), "eXIf carried");
        assert_eq!(back.orientation, 1);
    }

    #[test]
    fn unsupported_format_returns_unchanged() {
        let bytes = vec![1u8, 2, 3, 4];
        assert_eq!(inject(&bytes, &Canonical::default()), bytes);
    }

    /// A minimal SIMPLE-lossless WebP: a `VP8L` chunk whose 5-byte header encodes
    /// the dimensions (the trailing "pixels" are arbitrary — neither inject nor
    /// extract decodes them).
    fn webp_vp8l(w: u32, h: u32) -> Vec<u8> {
        let bits: u32 = ((w - 1) & 0x3FFF) | (((h - 1) & 0x3FFF) << 14); // alpha=0
        let mut payload = vec![0x2f];
        payload.extend_from_slice(&bits.to_le_bytes());
        payload.extend_from_slice(&[0xAA, 0xBB, 0xCC]); // arbitrary coded bytes
        let mut body = Vec::new();
        body.extend_from_slice(b"VP8L");
        body.extend_from_slice(&(payload.len() as u32).to_le_bytes());
        body.extend_from_slice(&payload);
        if payload.len() & 1 == 1 {
            body.push(0);
        }
        let mut f = Vec::new();
        f.extend_from_slice(b"RIFF");
        f.extend_from_slice(&((4 + body.len()) as u32).to_le_bytes());
        f.extend_from_slice(b"WEBP");
        f.extend_from_slice(&body);
        f
    }

    #[test]
    fn webp_inject_wraps_simple_to_extended_and_carries_meta() {
        let webp = webp_vp8l(20, 10);
        assert!(extract(&webp).exif.is_none(), "no metadata to start");

        let meta = Canonical {
            exif: Some(tiff_orientation(6)),
            xmp: Some(b"<x:xmpmeta>w</x:xmpmeta>".to_vec()),
            icc: Some(b"icc-bytes".to_vec()),
            ..Default::default()
        };
        let out = inject(&webp, &meta);

        // Round-trips through extract: all three blobs carried, orientation baked.
        let back = extract(&out);
        assert!(back.exif.is_some(), "EXIF carried");
        assert_eq!(back.orientation, 1, "orientation normalised (pixels baked)");
        assert_eq!(
            back.xmp.as_deref(),
            Some(b"<x:xmpmeta>w</x:xmpmeta>".as_slice())
        );
        assert_eq!(back.icc.as_deref(), Some(b"icc-bytes".as_slice()));

        // Wrapped into the extended form; the coded image survived.
        assert!(contains(&out, b"VP8X"), "wrapped to extended");
        assert!(contains(&out, b"VP8L"), "coded image kept");
        // VP8X flags byte: RIFF/WEBP header (12) + chunk header (8) = offset 20.
        let flags = out[20];
        assert_eq!(flags & VP8X_EXIF, VP8X_EXIF);
        assert_eq!(flags & VP8X_XMP, VP8X_XMP);
        assert_eq!(flags & VP8X_ICC, VP8X_ICC);
        // Chunk order: ICCP precedes the image; EXIF/XMP follow it.
        let icc_pos = out.windows(4).position(|c| c == b"ICCP").unwrap();
        let img_pos = out.windows(4).position(|c| c == b"VP8L").unwrap();
        let exif_pos = out.windows(4).position(|c| c == b"EXIF").unwrap();
        assert!(icc_pos < img_pos, "ICCP before image");
        assert!(img_pos < exif_pos, "EXIF after image");
        // RIFF size header equals the body length (== file length - 8).
        let declared = u32::from_le_bytes([out[4], out[5], out[6], out[7]]) as usize;
        assert_eq!(declared, out.len() - 8);
    }

    #[test]
    fn webp_inject_noop_when_meta_empty() {
        let webp = webp_vp8l(8, 8);
        assert_eq!(inject(&webp, &Canonical::default()), webp);
    }

    #[test]
    fn webp_xmp_png_wrapper_unwrapped_to_bare_packet() {
        // XMP extracted from a PNG keeps its iTXt wrapper inside Canonical.
        let mut wrapped = b"XML:com.adobe.xmp\0".to_vec();
        wrapped.extend_from_slice(&[0, 0]); // comp flag + method
        wrapped.extend_from_slice(b"\0\0"); // empty lang + translated keyword
        wrapped.extend_from_slice(b"<x:xmpmeta>p</x:xmpmeta>");
        let meta = Canonical {
            xmp: Some(wrapped),
            ..Default::default()
        };
        let out = inject(&webp_vp8l(8, 8), &meta);
        // The WebP XMP chunk holds the bare packet, not the PNG wrapper.
        assert!(
            !contains(&out, b"XML:com.adobe.xmp"),
            "PNG wrapper stripped"
        );
        assert_eq!(
            extract(&out).xmp.as_deref(),
            Some(b"<x:xmpmeta>p</x:xmpmeta>".as_slice())
        );
    }

    fn png_sig_ihdr() -> Vec<u8> {
        let mut png = vec![137, 80, 78, 71, 13, 10, 26, 10];
        super::png_chunk(&mut png, b"IHDR", &[0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0]);
        png
    }

    #[test]
    fn png_inject_carries_icc_compressed_roundtrip() {
        let mut png = png_sig_ihdr();
        super::png_chunk(&mut png, b"IEND", &[]);
        let base_len = png.len();
        // A compressible (repetitive) profile, so we can assert it was really
        // zlib'd — short incompressible data would land in a deflate STORED
        // block (raw bytes verbatim), which says nothing about compression.
        let icc = vec![0xABu8; 4096];
        let meta = Canonical {
            icc: Some(icc.clone()),
            ..Default::default()
        };
        let out = inject(&png, &meta);
        assert!(contains(&out, b"iCCP"), "iCCP chunk written");
        assert!(out.len() < base_len + icc.len(), "iCCP profile compressed");
        // Round-trips: extract decompresses the iCCP back to the exact bytes.
        assert_eq!(extract(&out).icc.as_deref(), Some(icc.as_slice()));
    }

    #[test]
    fn icc_is_raw_in_canonical_so_png_carries_to_webp() {
        // A PNG iCCP (compressed) must normalise to the RAW profile in Canonical,
        // so injecting into a WebP (whose ICCP is uncompressed) lands it verbatim
        // rather than re-wrapping a compressed blob.
        let raw_icc = b"raw-icc-abcdefghij".to_vec();
        let mut png = png_sig_ihdr();
        super::png_chunk(&mut png, b"iCCP", &super::build_iccp(&raw_icc));
        super::png_chunk(&mut png, b"IEND", &[]);

        let meta = extract(&png);
        assert_eq!(
            meta.icc.as_deref(),
            Some(raw_icc.as_slice()),
            "normalised raw"
        );

        let webp_out = inject(&webp_vp8l(8, 8), &meta);
        assert!(
            contains(&webp_out, raw_icc.as_slice()),
            "raw ICC in WebP ICCP"
        );
        assert_eq!(extract(&webp_out).icc.as_deref(), Some(raw_icc.as_slice()));
    }
}
