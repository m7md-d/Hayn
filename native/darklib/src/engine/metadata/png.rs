//! Lossless PNG metadata surgery.
//!
//! Drop text / timestamp / EXIF ancillary chunks (`tEXt`/`zTXt`/`iTXt`/`eXIf`/
//! `tIME`); keep IHDR/PLTE/IDAT/IEND and the colour chunks (gAMA/cHRM/sRGB).
//! `iCCP` (ICC) is kept unless the policy strips colour. IDAT is copied
//! byte-for-byte. On malformation returns the input untouched.

use super::{IccPolicy, StripPolicy};
use crate::engine::error::Result;

const SIG: [u8; 8] = [137, 80, 78, 71, 13, 10, 26, 10];

pub fn strip(b: &[u8], policy: StripPolicy) -> Result<Vec<u8>> {
    Ok(strip_bytes(b, policy))
}

fn strip_bytes(b: &[u8], policy: StripPolicy) -> Vec<u8> {
    if b.len() < 8 || b[..8] != SIG {
        return b.to_vec();
    }
    let strip_icc = policy.icc == IccPolicy::Strip;

    let mut out: Vec<u8> = Vec::with_capacity(b.len());
    out.extend_from_slice(&b[..8]);
    let mut i = 8usize;
    while i + 8 <= b.len() {
        let len = ((b[i] as usize) << 24)
            | ((b[i + 1] as usize) << 16)
            | ((b[i + 2] as usize) << 8)
            | (b[i + 3] as usize);
        let kind = &b[i + 4..i + 8];
        let chunk_end = i + 12 + len; // length(4) + type(4) + data(len) + crc(4)
        if chunk_end > b.len() {
            return b.to_vec();
        }
        let drop = kind == b"tEXt"
            || kind == b"zTXt"
            || kind == b"iTXt"
            || kind == b"eXIf"
            || kind == b"tIME"
            || (kind == b"iCCP" && strip_icc);
        if !drop {
            out.extend_from_slice(&b[i..chunk_end]);
        }
        if kind == b"IEND" {
            break;
        }
        i = chunk_end;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::metadata::{IccPolicy, OrientationPolicy, StripPolicy};

    /// Append a PNG chunk (length + type + data + a dummy CRC).
    fn chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
        out.extend_from_slice(&(data.len() as u32).to_be_bytes());
        out.extend_from_slice(kind);
        out.extend_from_slice(data);
        out.extend_from_slice(&[0xDE, 0xAD, 0xBE, 0xEF]); // CRC (not validated)
    }

    fn sample() -> Vec<u8> {
        let mut p = SIG.to_vec();
        chunk(&mut p, b"IHDR", &[0, 0, 0, 4, 0, 0, 0, 4, 8, 6, 0, 0, 0]);
        chunk(&mut p, b"iCCP", b"profile\0fake-icc");
        chunk(&mut p, b"eXIf", b"secret-exif-gps");
        chunk(&mut p, b"tEXt", b"Comment\0private");
        chunk(&mut p, b"IDAT", &[0x78, 0x9C, 0x01, 0x02, 0x03]);
        chunk(&mut p, b"IEND", &[]);
        p
    }

    fn contains(hay: &[u8], needle: &[u8]) -> bool {
        hay.windows(needle.len()).any(|w| w == needle)
    }

    #[test]
    fn drops_exif_and_text_keeps_iccp_and_idat() {
        let out = strip(&sample(), StripPolicy::default()).unwrap();
        assert!(!contains(&out, b"secret-exif-gps"), "eXIf gone");
        assert!(!contains(&out, b"private"), "tEXt gone");
        assert!(contains(&out, b"fake-icc"), "iCCP kept by default");
        assert!(
            contains(&out, &[0x78, 0x9C, 0x01, 0x02, 0x03]),
            "IDAT byte-identical"
        );
        // Ends with the intact IEND chunk: len(0) + "IEND" + its CRC.
        assert_eq!(
            &out[out.len() - 12..],
            &[0, 0, 0, 0, b'I', b'E', b'N', b'D', 0xDE, 0xAD, 0xBE, 0xEF]
        );
    }

    #[test]
    fn strip_icc_also_removes_iccp() {
        let out = strip(
            &sample(),
            StripPolicy {
                icc: IccPolicy::Strip,
                orientation: OrientationPolicy::Keep,
            },
        )
        .unwrap();
        assert!(
            !contains(&out, b"fake-icc"),
            "iCCP removed when policy says so"
        );
        assert!(
            contains(&out, &[0x78, 0x9C, 0x01, 0x02, 0x03]),
            "IDAT still intact"
        );
    }

    #[test]
    fn not_a_png_returns_input() {
        let junk = vec![1u8, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        assert_eq!(strip(&junk, StripPolicy::default()).unwrap(), junk);
    }
}
