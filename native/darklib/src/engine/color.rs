//! Colour management — synthesise an ICC profile from CICP code points (nclx).
//!
//! AVIF/HEIF often carry colour as nclx CODE POINTS (primaries / transfer /
//! matrix), not an embedded ICC — iPhone HEIC tags Display-P3 this way. When such
//! an image is converted to JPEG/PNG/WebP the gamut would be lost (read as sRGB →
//! wrong colours). We rebuild a matrix/TRC ICC profile from the code points so it
//! travels with the pixels, with NO bundled profile (no licensing question): the
//! colorants are derived from the published primary chromaticities and Bradford-
//! adapted to the ICC D50 PCS, and the curve is the standard sRGB transfer.
//!
//! Correctness is pinned by an independent check — the sRGB colorants this code
//! derives must equal the published sRGB D50 constants (see tests). Only SDR
//! transfers are handled; PQ/HLG (HDR) deliberately bail to the HDR stage.

type M3 = [[f64; 3]; 3];
type V3 = [f64; 3];

/// ICC D50 PCS white (the profile connection space illuminant).
const D50_XYZ: V3 = [0.96422, 1.0, 0.82521];

/// Bradford cone-response matrix (for chromatic adaptation).
const BRADFORD: M3 = [
    [0.8951, 0.2664, -0.1614],
    [-0.7502, 1.7135, 0.0367],
    [0.0389, -0.0685, 1.0296],
];

/// Build a display-class RGB matrix/TRC ICC profile for the given CICP
/// `primaries` and `transfer`, or `None` for primaries/transfers we don't map
/// (unknown primaries, or HDR transfers — PQ/HLG/linear — which the HDR stage
/// owns). The profile embeds D50-adapted colorants, a `chad` adaptation tag and
/// the sRGB tone curve.
pub fn synthesize_from_cicp(primaries: u16, transfer: u16) -> Option<Vec<u8>> {
    if !is_sdr_transfer(transfer) {
        return None; // PQ/HLG/linear → not an SDR matrix profile
    }
    let (prim, white) = primaries_chroma(primaries)?;
    let colorants = d50_colorants(prim, white)?;
    let chad = adapt_to_d50(white)?;
    Some(build_icc(&colorants, &chad))
}

/// SDR transfers we represent with the sRGB parametric curve (close enough for a
/// display profile): BT.709 / BT.601 / sRGB / BT.2020-10/12-bit.
fn is_sdr_transfer(tc: u16) -> bool {
    matches!(tc, 1 | 6 | 13 | 14 | 15)
}

/// CICP colour-primaries code → (RGB primary chromaticities, white chromaticity).
fn primaries_chroma(cp: u16) -> Option<([[f64; 2]; 3], [f64; 2])> {
    let d65 = [0.3127, 0.3290];
    match cp {
        1 => Some(([[0.640, 0.330], [0.300, 0.600], [0.150, 0.060]], d65)), // BT.709 / sRGB
        9 => Some(([[0.708, 0.292], [0.170, 0.797], [0.131, 0.046]], d65)), // BT.2020
        12 => Some(([[0.680, 0.320], [0.265, 0.690], [0.150, 0.060]], d65)), // Display P3
        _ => None,
    }
}

// ── linear algebra ───────────────────────────────────────────────────────────

fn mul_mv(m: &M3, v: &V3) -> V3 {
    [
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2],
    ]
}

fn mul_mm(a: &M3, b: &M3) -> M3 {
    let mut r = [[0.0f64; 3]; 3];
    for (i, ri) in r.iter_mut().enumerate() {
        for (j, rij) in ri.iter_mut().enumerate() {
            *rij = (0..3).map(|k| a[i][k] * b[k][j]).sum();
        }
    }
    r
}

fn inv3(m: &M3) -> Option<M3> {
    let det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
        - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
        + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
    if det.abs() < 1e-12 {
        return None;
    }
    let id = 1.0 / det;
    Some([
        [
            (m[1][1] * m[2][2] - m[1][2] * m[2][1]) * id,
            (m[0][2] * m[2][1] - m[0][1] * m[2][2]) * id,
            (m[0][1] * m[1][2] - m[0][2] * m[1][1]) * id,
        ],
        [
            (m[1][2] * m[2][0] - m[1][0] * m[2][2]) * id,
            (m[0][0] * m[2][2] - m[0][2] * m[2][0]) * id,
            (m[0][2] * m[1][0] - m[0][0] * m[1][2]) * id,
        ],
        [
            (m[1][0] * m[2][1] - m[1][1] * m[2][0]) * id,
            (m[0][1] * m[2][0] - m[0][0] * m[2][1]) * id,
            (m[0][0] * m[1][1] - m[0][1] * m[1][0]) * id,
        ],
    ])
}

/// xy chromaticity → XYZ at unit luminance (Y = 1).
fn xy_to_xyz(xy: [f64; 2]) -> V3 {
    [xy[0] / xy[1], 1.0, (1.0 - xy[0] - xy[1]) / xy[1]]
}

/// RGB→XYZ matrix (relative to the native white) from primaries + white.
fn rgb_to_xyz(prim: [[f64; 2]; 3], white: [f64; 2]) -> Option<M3> {
    let r = xy_to_xyz(prim[0]);
    let g = xy_to_xyz(prim[1]);
    let b = xy_to_xyz(prim[2]);
    let m: M3 = [[r[0], g[0], b[0]], [r[1], g[1], b[1]], [r[2], g[2], b[2]]];
    let s = mul_mv(&inv3(&m)?, &xy_to_xyz(white));
    Some([
        [m[0][0] * s[0], m[0][1] * s[1], m[0][2] * s[2]],
        [m[1][0] * s[0], m[1][1] * s[1], m[1][2] * s[2]],
        [m[2][0] * s[0], m[2][1] * s[1], m[2][2] * s[2]],
    ])
}

/// Bradford chromatic-adaptation matrix from a source white (xy) to D50.
fn adapt_to_d50(src_white: [f64; 2]) -> Option<M3> {
    let cone_s = mul_mv(&BRADFORD, &xy_to_xyz(src_white));
    let cone_d = mul_mv(&BRADFORD, &D50_XYZ);
    let diag: M3 = [
        [cone_d[0] / cone_s[0], 0.0, 0.0],
        [0.0, cone_d[1] / cone_s[1], 0.0],
        [0.0, 0.0, cone_d[2] / cone_s[2]],
    ];
    Some(mul_mm(&inv3(&BRADFORD)?, &mul_mm(&diag, &BRADFORD)))
}

/// D50-adapted colorant matrix; its columns are the rXYZ / gXYZ / bXYZ tags.
fn d50_colorants(prim: [[f64; 2]; 3], white: [f64; 2]) -> Option<M3> {
    Some(mul_mm(&adapt_to_d50(white)?, &rgb_to_xyz(prim, white)?))
}

// ── ICC serialisation (matrix/TRC display profile, v4) ───────────────────────

/// Encode an s15Fixed16 number (signed 16.16 fixed point), big-endian.
fn s15f16(v: f64) -> [u8; 4] {
    ((v * 65536.0).round() as i32).to_be_bytes()
}

fn xyz_tag(x: f64, y: f64, z: f64) -> Vec<u8> {
    let mut v = b"XYZ \0\0\0\0".to_vec();
    v.extend_from_slice(&s15f16(x));
    v.extend_from_slice(&s15f16(y));
    v.extend_from_slice(&s15f16(z));
    v
}

fn sf32_tag(m: &M3) -> Vec<u8> {
    let mut v = b"sf32\0\0\0\0".to_vec();
    for row in m {
        for &c in row {
            v.extend_from_slice(&s15f16(c));
        }
    }
    v
}

/// parametricCurveType, function type 4 (the sRGB transfer): g a b c d e f.
fn para_srgb_tag() -> Vec<u8> {
    let mut v = b"para\0\0\0\0".to_vec();
    v.extend_from_slice(&4u16.to_be_bytes()); // function type 4
    v.extend_from_slice(&0u16.to_be_bytes()); // reserved
    for p in [
        2.4,
        1.0 / 1.055,
        0.055 / 1.055,
        1.0 / 12.92,
        0.04045,
        0.0,
        0.0,
    ] {
        v.extend_from_slice(&s15f16(p));
    }
    v
}

/// multiLocalizedUnicodeType with a single en-US record.
fn mluc_tag(s: &str) -> Vec<u8> {
    let utf16: Vec<u8> = s.encode_utf16().flat_map(u16::to_be_bytes).collect();
    let mut v = b"mluc\0\0\0\0".to_vec();
    v.extend_from_slice(&1u32.to_be_bytes()); // record count
    v.extend_from_slice(&12u32.to_be_bytes()); // record size
    v.extend_from_slice(b"enUS"); // language 'en' + country 'US'
    v.extend_from_slice(&(utf16.len() as u32).to_be_bytes());
    v.extend_from_slice(&28u32.to_be_bytes()); // string offset from tag start
    v.extend_from_slice(&utf16);
    v
}

fn build_icc(colorants: &M3, chad: &M3) -> Vec<u8> {
    // Colorant tags are the columns of the adapted matrix.
    let rxyz = xyz_tag(colorants[0][0], colorants[1][0], colorants[2][0]);
    let gxyz = xyz_tag(colorants[0][1], colorants[1][1], colorants[2][1]);
    let bxyz = xyz_tag(colorants[0][2], colorants[1][2], colorants[2][2]);
    let wtpt = xyz_tag(D50_XYZ[0], D50_XYZ[1], D50_XYZ[2]);
    let chad_t = sf32_tag(chad);
    let trc = para_srgb_tag();
    let desc = mluc_tag("DarkLib synthetic RGB");
    let cprt = mluc_tag("CC0");

    // Unique data blocks; rTRC/gTRC/bTRC then alias the single TRC block.
    let blocks: [(&[u8; 4], &Vec<u8>); 8] = [
        (b"desc", &desc),
        (b"cprt", &cprt),
        (b"wtpt", &wtpt),
        (b"chad", &chad_t),
        (b"rXYZ", &rxyz),
        (b"gXYZ", &gxyz),
        (b"bXYZ", &bxyz),
        (b"rTRC", &trc),
    ];
    let tag_count = blocks.len() + 2; // + gTRC + bTRC aliases
    let header_len = 128usize;
    let table_len = 4 + tag_count * 12;

    let mut table: Vec<([u8; 4], u32, u32)> = Vec::new();
    let mut data = Vec::new();
    let (mut trc_off, mut trc_len) = (0u32, 0u32);
    for (sig, block) in blocks {
        let off = (header_len + table_len + data.len()) as u32;
        let len = block.len() as u32;
        table.push((*sig, off, len));
        data.extend_from_slice(block);
        while data.len() % 4 != 0 {
            data.push(0); // tag data is 4-byte aligned
        }
        if sig == b"rTRC" {
            (trc_off, trc_len) = (off, len);
        }
    }
    table.push((*b"gTRC", trc_off, trc_len));
    table.push((*b"bTRC", trc_off, trc_len));

    let total = header_len + table_len + data.len();
    let mut out = Vec::with_capacity(total);
    // ── header (128 bytes) ──
    out.extend_from_slice(&(total as u32).to_be_bytes()); // profile size
    out.extend_from_slice(&[0; 4]); // preferred CMM
    out.extend_from_slice(&0x0420_0000u32.to_be_bytes()); // version 4.2
    out.extend_from_slice(b"mntr"); // device class (display)
    out.extend_from_slice(b"RGB "); // data colour space
    out.extend_from_slice(b"XYZ "); // PCS
    out.extend_from_slice(&[0; 12]); // date/time
    out.extend_from_slice(b"acsp"); // profile file signature
    out.extend_from_slice(&[0; 4]); // primary platform
    out.extend_from_slice(&[0; 4]); // profile flags
    out.extend_from_slice(&[0; 4]); // device manufacturer
    out.extend_from_slice(&[0; 4]); // device model
    out.extend_from_slice(&[0; 8]); // device attributes
    out.extend_from_slice(&[0; 4]); // rendering intent (perceptual)
    out.extend_from_slice(&s15f16(D50_XYZ[0])); // PCS illuminant (D50)
    out.extend_from_slice(&s15f16(D50_XYZ[1]));
    out.extend_from_slice(&s15f16(D50_XYZ[2]));
    out.extend_from_slice(&[0; 4]); // profile creator
    out.extend_from_slice(&[0; 16]); // profile ID
    out.extend_from_slice(&[0; 28]); // reserved
                                     // ── tag table ──
    out.extend_from_slice(&(tag_count as u32).to_be_bytes());
    for (sig, off, len) in &table {
        out.extend_from_slice(sig);
        out.extend_from_slice(&off.to_be_bytes());
        out.extend_from_slice(&len.to_be_bytes());
    }
    // ── tag data ──
    out.extend_from_slice(&data);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The decisive correctness check: the sRGB colorants this code DERIVES must
    /// match the published sRGB D50-adapted (Bradford) constants. If the matrix +
    /// adaptation maths is right for sRGB, it is right for every primary set.
    #[test]
    fn srgb_colorants_match_published_constants() {
        let (prim, white) = primaries_chroma(1).unwrap();
        let c = d50_colorants(prim, white).unwrap();
        let close = |a: f64, b: f64| (a - b).abs() < 1e-3;
        // [rX rY rZ] [gX gY gZ] [bX bY bZ] — the standard sRGB v4 colorants.
        assert!(close(c[0][0], 0.43607) && close(c[1][0], 0.22249) && close(c[2][0], 0.01392));
        assert!(close(c[0][1], 0.38515) && close(c[1][1], 0.71687) && close(c[2][1], 0.09708));
        assert!(close(c[0][2], 0.14307) && close(c[1][2], 0.06061) && close(c[2][2], 0.71410));
    }

    fn read_tag(icc: &[u8], sig: &[u8; 4]) -> Option<Vec<u8>> {
        let count = u32::from_be_bytes(icc[128..132].try_into().ok()?) as usize;
        (0..count).find_map(|i| {
            let e = 132 + i * 12;
            (&icc[e..e + 4] == sig).then(|| {
                let off = u32::from_be_bytes(icc[e + 4..e + 8].try_into().unwrap()) as usize;
                let len = u32::from_be_bytes(icc[e + 8..e + 12].try_into().unwrap()) as usize;
                icc[off..off + len].to_vec()
            })
        })
    }

    #[test]
    fn synthesizes_a_parseable_icc_whose_colorants_round_trip() {
        let (prim, white) = primaries_chroma(12).unwrap(); // Display P3
        let expect = d50_colorants(prim, white).unwrap();
        let icc = synthesize_from_cicp(12, 13).unwrap();

        // Valid ICC envelope: 'acsp' signature, size field == real length.
        assert_eq!(&icc[36..40], b"acsp");
        assert_eq!(
            u32::from_be_bytes(icc[0..4].try_into().unwrap()) as usize,
            icc.len()
        );

        // rXYZ tag reads back as the computed colorant (serialisation round-trip).
        let rxyz = read_tag(&icc, b"rXYZ").unwrap();
        assert_eq!(&rxyz[0..4], b"XYZ ");
        let rx = i32::from_be_bytes(rxyz[8..12].try_into().unwrap()) as f64 / 65536.0;
        assert!((rx - expect[0][0]).abs() < 1e-3, "rXYZ.X round-trips");
        // The TRC and white point are present.
        assert!(read_tag(&icc, b"rTRC").is_some());
        assert!(read_tag(&icc, b"wtpt").is_some());
    }

    #[test]
    fn p3_profile_differs_from_srgb() {
        let srgb = synthesize_from_cicp(1, 13).unwrap();
        let p3 = synthesize_from_cicp(12, 13).unwrap();
        assert_ne!(
            read_tag(&srgb, b"rXYZ"),
            read_tag(&p3, b"rXYZ"),
            "wider gamut"
        );
    }

    #[test]
    fn hdr_and_unknown_bail() {
        assert!(
            synthesize_from_cicp(9, 16).is_none(),
            "PQ transfer → HDR stage"
        );
        assert!(
            synthesize_from_cicp(9, 18).is_none(),
            "HLG transfer → HDR stage"
        );
        assert!(
            synthesize_from_cicp(2, 13).is_none(),
            "unsupported primaries"
        );
    }
}
