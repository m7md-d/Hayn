//! Lossless WebP metadata surgery.
//!
//! RIFF container: `RIFF` <u32 size> `WEBP` then FourCC-tagged chunks (each a
//! u32 little-endian size + payload padded to even length). Metadata lives in
//! the `EXIF` and `XMP ` chunks — drop them and clear the matching VP8X flag
//! bits (EXIF=0x08, XMP=0x04). `ICCP` (+ flag 0x20) is kept unless the policy
//! strips colour. Coded chunks (VP8/VP8L/ALPH/ANMF…) are copied byte-for-byte.
//! On malformation returns the input untouched.

use super::{IccPolicy, StripPolicy};
use crate::engine::error::Result;

pub fn strip(b: &[u8], policy: StripPolicy) -> Result<Vec<u8>> {
    Ok(strip_bytes(b, policy))
}

fn strip_bytes(b: &[u8], policy: StripPolicy) -> Vec<u8> {
    if b.len() < 16 || &b[0..4] != b"RIFF" || &b[8..12] != b"WEBP" {
        return b.to_vec();
    }
    let strip_icc = policy.icc == IccPolicy::Strip;

    let mut body: Vec<u8> = Vec::with_capacity(b.len());
    let mut i = 12usize;
    let mut changed = false;
    while i + 8 <= b.len() {
        let fourcc = &b[i..i + 4];
        let size = (b[i + 4] as usize)
            | ((b[i + 5] as usize) << 8)
            | ((b[i + 6] as usize) << 16)
            | ((b[i + 7] as usize) << 24);
        let padded = size + (size & 1); // chunks are padded to an even length
        let chunk_end = i + 8 + padded;
        if chunk_end > b.len() {
            return b.to_vec();
        }

        if fourcc == b"EXIF" || fourcc == b"XMP " || (fourcc == b"ICCP" && strip_icc) {
            changed = true; // drop whole chunk (header + payload + pad)
        } else if fourcc == b"VP8X" && size >= 1 {
            // Clear EXIF (0x08) + XMP (0x04) flag bits; also ICCP (0x20) when
            // stripping colour, so the file stays self-consistent.
            let mut chunk = b[i..chunk_end].to_vec();
            let mask: u8 = if strip_icc { !0x2C } else { !0x0C };
            let cleared = chunk[8] & mask;
            if cleared != chunk[8] {
                chunk[8] = cleared;
                changed = true;
            }
            body.extend_from_slice(&chunk);
        } else {
            body.extend_from_slice(&b[i..chunk_end]);
        }
        i = chunk_end;
    }
    if !changed {
        return b.to_vec();
    }

    let riff_size = (4 + body.len()) as u32; // 'WEBP' + chunks
    let mut out: Vec<u8> = Vec::with_capacity(8 + riff_size as usize);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&riff_size.to_le_bytes());
    out.extend_from_slice(b"WEBP");
    out.extend_from_slice(&body);
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::metadata::{IccPolicy, OrientationPolicy, StripPolicy};

    /// Append a RIFF chunk (fourcc + LE u32 size + payload + even-pad).
    fn chunk(out: &mut Vec<u8>, fourcc: &[u8; 4], data: &[u8]) {
        out.extend_from_slice(fourcc);
        out.extend_from_slice(&(data.len() as u32).to_le_bytes());
        out.extend_from_slice(data);
        if data.len() & 1 == 1 {
            out.push(0);
        }
    }

    fn sample() -> Vec<u8> {
        let mut chunks = Vec::new();
        // VP8X with EXIF(0x08)+XMP(0x04)+ICCP(0x20) flags set.
        chunk(
            &mut chunks,
            b"VP8X",
            &[0x2C, 0, 0, 0, 0x0F, 0, 0, 0x0F, 0, 0],
        );
        chunk(&mut chunks, b"ICCP", b"fake-icc-profile");
        chunk(&mut chunks, b"VP8 ", &[0xAA, 0xBB, 0xCC, 0xDD]); // coded pixels
        chunk(&mut chunks, b"EXIF", b"secret-exif-gps");
        chunk(&mut chunks, b"XMP ", b"<x:xmpmeta>private</x:xmpmeta>");

        let mut v = Vec::new();
        v.extend_from_slice(b"RIFF");
        v.extend_from_slice(&((4 + chunks.len()) as u32).to_le_bytes());
        v.extend_from_slice(b"WEBP");
        v.extend_from_slice(&chunks);
        v
    }

    fn contains(hay: &[u8], needle: &[u8]) -> bool {
        hay.windows(needle.len()).any(|w| w == needle)
    }

    fn vp8x_flags(buf: &[u8]) -> u8 {
        let pos = buf.windows(4).position(|w| w == b"VP8X").unwrap();
        buf[pos + 8] // fourcc(4) + size(4) → first payload byte
    }

    #[test]
    fn drops_exif_xmp_clears_flags_keeps_iccp_and_pixels() {
        let out = strip(&sample(), StripPolicy::default()).unwrap();
        assert!(!contains(&out, b"secret-exif-gps"), "EXIF chunk gone");
        assert!(!contains(&out, b"xmpmeta"), "XMP chunk gone");
        assert!(contains(&out, b"fake-icc-profile"), "ICCP kept by default");
        assert!(
            contains(&out, &[0xAA, 0xBB, 0xCC, 0xDD]),
            "VP8 pixels byte-identical"
        );
        // EXIF + XMP bits cleared; ICCP (0x20) still set.
        assert_eq!(vp8x_flags(&out) & 0x0C, 0);
        assert_eq!(vp8x_flags(&out) & 0x20, 0x20);
        // RIFF size header equals the new body length.
        let declared = u32::from_le_bytes([out[4], out[5], out[6], out[7]]) as usize;
        assert_eq!(declared, out.len() - 8);
    }

    #[test]
    fn strip_icc_removes_iccp_and_clears_its_flag() {
        let out = strip(
            &sample(),
            StripPolicy {
                icc: IccPolicy::Strip,
                orientation: OrientationPolicy::Keep,
            },
        )
        .unwrap();
        assert!(!contains(&out, b"fake-icc-profile"), "ICCP removed");
        assert_eq!(vp8x_flags(&out) & 0x20, 0, "ICCP flag cleared");
        assert!(contains(&out, &[0xAA, 0xBB, 0xCC, 0xDD]), "pixels intact");
    }
}
