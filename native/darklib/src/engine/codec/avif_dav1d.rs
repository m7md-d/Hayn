//! AVIF → RGBA decode via rav1d (the pure-Rust dav1d port) — Stage 5.
//!
//! AV1 is royalty-free, so DarkLib decodes it in-process: one uniform path on
//! every platform, and frame-accurate for the animation features to come. (HEVC-
//! coded HEIC is NOT decoded here — its patents bar a bundled software decoder,
//! CLAUDE.md §5 — that stays a hardware path.) We drive rav1d through its dav1d
//! C-ABI entry points (all `pub`), using rav1d's own `#[repr(C)]` types so there
//! is no hand-mirrored struct to drift out of layout. The whole unsafe lifecycle
//! lives in one place; any failure returns an error so the caller can fall back
//! to a platform decoder during migration — we never hand back a torn buffer.

use std::mem::MaybeUninit;
use std::ptr::{copy_nonoverlapping, NonNull};

use rav1d::include::dav1d::data::Dav1dData;
use rav1d::include::dav1d::dav1d::{Dav1dContext, Dav1dSettings};
use rav1d::include::dav1d::picture::Dav1dPicture;
use rav1d::src::lib::{
    dav1d_close, dav1d_data_create, dav1d_data_unref, dav1d_default_settings, dav1d_get_picture,
    dav1d_open, dav1d_picture_unref, dav1d_send_data,
};

use crate::engine::error::{DarkError, Result};
use crate::engine::metadata::isobmff;

fn fail() -> DarkError {
    DarkError::Malformed("avif decode failed")
}

/// Decode an AVIF still to 8-bit `(width, height, rgba)` — a plain `av01`
/// primary or an ImageGrid (tiled) one, plus the alpha auxiliary and the
/// `irot`/`imir` orientation transform.
pub fn decode(bytes: &[u8]) -> Result<(u32, u32, Vec<u8>)> {
    let primary =
        isobmff::primary_item_id(bytes).ok_or(DarkError::Malformed("avif: no primary item"))?;
    let (w, h, mut rgba) = decode_item(bytes, primary, 0)?;

    // Transparency: AVIF stores alpha as a separate monochrome auxiliary image
    // (an av01 item, or a grid of them for large images). Decode it and copy its
    // luma into the alpha channel. Any failure or size mismatch leaves the image
    // opaque — alpha is never allowed to corrupt the colour decode.
    if let Some(alpha_id) = isobmff::alpha_item_id(bytes) {
        if let Ok((aw, ah, argba)) = decode_item(bytes, alpha_id, 0) {
            if aw == w && ah == h {
                for px in 0..(w as usize * h as usize) {
                    rgba[px * 4 + 3] = argba[px * 4]; // mono luma → alpha
                }
            }
        }
    }

    // AVIF stores orientation as irot/imir item properties (not EXIF). Bake the
    // transform into the pixels here so the output is upright and the re-encode
    // writes no orientation tag — matching how every other format is handled.
    if let Some((angle, mirror)) = isobmff::read_orientation(bytes) {
        return Ok(apply_orientation(
            w as usize, h as usize, rgba, angle, mirror,
        ));
    }
    Ok((w, h, rgba))
}

/// Cap on a grid canvas (pixels): 256 MP ≈ 1 GiB of RGBA. Covers every real
/// camera (Samsung's 200 MP included) while refusing a malicious descriptor that
/// claims a multi-gigabyte canvas.
const MAX_GRID_PIXELS: u64 = 256 * 1024 * 1024;

/// Decode one item to RGBA: an `av01` item directly, or a `grid` derived item by
/// decoding its tiles one at a time and assembling them onto the canvas (peak
/// memory ≈ canvas + one tile — the memory-bounded answer to huge images).
fn decode_item(bytes: &[u8], id: u32, depth: u8) -> Result<(u32, u32, Vec<u8>)> {
    if depth == 0 {
        if let Some(grid) = isobmff::read_grid(bytes, id) {
            return decode_grid(bytes, &grid);
        }
    }
    // Per-item av1C config (a tile/alpha item must get ITS sequence header, never
    // another item's); the primary may fall back to the file's first av1C. Some
    // encoders also repeat the sequence header in the item data — harmless.
    let mut stream = isobmff::av1c_for_item(bytes, id)
        .or_else(|| {
            (Some(id) == isobmff::primary_item_id(bytes))
                .then(|| isobmff::extract_av1c_config_obus(bytes))
                .flatten()
        })
        .unwrap_or_default();
    let item = isobmff::extract_item_av1(bytes, id)
        .ok_or(DarkError::Malformed("avif: item is not AV1"))?;
    stream.extend_from_slice(&item);
    // SAFETY: the context/data/picture lifecycle is fully created, used and freed
    // inside this call; every pointer originates from rav1d and stays in scope.
    unsafe { decode_obus(&stream) }
}

/// Assemble an ImageGrid: decode each tile and paste it row-major, cropping the
/// right/bottom tiles to the canvas (the grid's output size is authoritative).
fn decode_grid(bytes: &[u8], g: &isobmff::GridInfo) -> Result<(u32, u32, Vec<u8>)> {
    let (cw, ch) = (g.width as usize, g.height as usize);
    if cw == 0 || ch == 0 || (cw as u64) * (ch as u64) > MAX_GRID_PIXELS {
        return Err(DarkError::Malformed("avif grid: bad canvas size"));
    }
    let mut canvas = vec![0u8; cw * ch * 4];
    let (mut tw, mut th) = (0usize, 0usize);
    for (i, &tile_id) in g.tiles.iter().enumerate() {
        let (w, h, px) = decode_item(bytes, tile_id, 1)?;
        let (w, h) = (w as usize, h as usize);
        if i == 0 {
            (tw, th) = (w, h);
            // Tiles must cover the canvas; short tiles would leave black bands.
            if tw == 0 || th == 0 || tw * (g.cols as usize) < cw || th * (g.rows as usize) < ch {
                return Err(DarkError::Malformed("avif grid: tiles don't cover canvas"));
            }
        } else if (w, h) != (tw, th) {
            return Err(DarkError::Malformed("avif grid: tile size mismatch"));
        }
        let (x0, y0) = ((i % g.cols as usize) * tw, (i / g.cols as usize) * th);
        for ty in 0..th {
            let y = y0 + ty;
            if y >= ch {
                break;
            }
            let copy_w = tw.min(cw.saturating_sub(x0));
            if copy_w == 0 {
                break;
            }
            let s = ty * tw * 4;
            let d = (y * cw + x0) * 4;
            canvas[d..d + copy_w * 4].copy_from_slice(&px[s..s + copy_w * 4]);
        }
    }
    Ok((cw as u32, ch as u32, canvas))
}

unsafe fn decode_obus(obus: &[u8]) -> Result<(u32, u32, Vec<u8>)> {
    let mut settings = MaybeUninit::<Dav1dSettings>::zeroed();
    dav1d_default_settings(NonNull::new(settings.as_mut_ptr()).unwrap());
    let mut settings = settings.assume_init();
    settings.n_threads = 1; // one still, deterministic, light (fits an isolate)
    settings.max_frame_delay = 1;

    let mut ctx: Option<Dav1dContext> = None;
    if dav1d_open(NonNull::new(&mut ctx), NonNull::new(&mut settings)).0 != 0 {
        return Err(fail());
    }
    let out = decode_with_ctx(ctx, obus);
    dav1d_close(NonNull::new(&mut ctx));
    out
}

unsafe fn decode_with_ctx(ctx: Option<Dav1dContext>, obus: &[u8]) -> Result<(u32, u32, Vec<u8>)> {
    // Copy the OBU stream into a dav1d-owned buffer, then feed the whole temporal
    // unit. For a single self-contained still, one send + one get suffices.
    let mut data = MaybeUninit::<Dav1dData>::zeroed();
    let dst = dav1d_data_create(NonNull::new(data.as_mut_ptr()), obus.len());
    if dst.is_null() {
        return Err(fail());
    }
    copy_nonoverlapping(obus.as_ptr(), dst, obus.len());
    let mut data = data.assume_init();
    let _ = dav1d_send_data(ctx, NonNull::new(&mut data));

    let mut pic = Dav1dPicture::default();
    let result = if dav1d_get_picture(ctx, NonNull::new(&mut pic)).0 == 0 {
        let rgba = picture_to_rgba(&pic);
        dav1d_picture_unref(NonNull::new(&mut pic));
        rgba
    } else {
        Err(fail())
    };
    dav1d_data_unref(NonNull::new(&mut data)); // no-op once send consumed it
    result
}

/// Convert a decoded `Dav1dPicture` (planar YUV, 8/10/12-bit) to packed 8-bit
/// RGBA, applying the matrix coefficients + range from the sequence header. Deep
/// (10/12-bit) sources are reduced to 8-bit here — the current SDR contract; a
/// wide/HDR path lands with HDR-through-convert. Alpha is set opaque here;
/// `decode` composites the separate AVIF alpha auxiliary item over the result.
unsafe fn picture_to_rgba(pic: &Dav1dPicture) -> Result<(u32, u32, Vec<u8>)> {
    let (w, h) = (pic.p.w, pic.p.h);
    if w <= 0 || h <= 0 {
        return Err(fail());
    }
    let bpc = pic.p.bpc;
    if !(8..=12).contains(&bpc) {
        return Err(fail());
    }
    let bpc = bpc as u8;
    let deep = bpc > 8; // planes are little-endian u16 samples
    let maxv = ((1u32 << bpc) - 1) as f32;
    let (w, h) = (w as usize, h as usize);

    // Colour conversion parameters from the sequence header (defaults: BT.601,
    // full range — the common still-image case if a header is somehow absent).
    let (mtrx, full) = match pic.seq_hdr {
        Some(sh) => {
            let sh = sh.as_ref();
            (sh.mtrx, sh.color_range != 0)
        }
        None => (6, true),
    };
    let identity = mtrx == 0; // MC identity: the planes ARE G, B, R
    let (kr, kb) = kr_kb(mtrx);
    let kg = 1.0 - kr - kb;

    // Chroma subsampling shift per layout (0=I400, 1=I420, 2=I422, 3=I444).
    let layout = pic.p.layout;
    let has_chroma = layout != 0;
    let (sub_x, sub_y) = match layout {
        1 => (1usize, 1usize),
        2 => (1, 0),
        _ => (0, 0),
    };

    let yp = pic.data[0].ok_or_else(fail)?.as_ptr() as *const u8;
    let ystride = pic.stride[0];
    let (up, vp, cstride) = if has_chroma {
        (
            pic.data[1].ok_or_else(fail)?.as_ptr() as *const u8,
            pic.data[2].ok_or_else(fail)?.as_ptr() as *const u8,
            pic.stride[1],
        )
    } else {
        (std::ptr::null(), std::ptr::null(), 0)
    };

    let mut rgba = vec![0u8; w * h * 4];
    for y in 0..h {
        let yrow = yp.offset(y as isize * ystride);
        let crow = (y >> sub_y) as isize * cstride;
        for x in 0..w {
            let yv = sample(yrow, x, deep);
            let (r, g, b) = if !has_chroma {
                let l = to_u8(norm_luma(yv, maxv, full, bpc));
                (l, l, l)
            } else {
                let cx = x >> sub_x;
                let uv = sample(up.offset(crow), cx, deep);
                let vv = sample(vp.offset(crow), cx, deep);
                if identity {
                    // MC identity: planes are G, B, R at `bpc` bits.
                    (scale8(vv, maxv), scale8(yv, maxv), scale8(uv, maxv))
                } else {
                    let yn = norm_luma(yv, maxv, full, bpc);
                    let cbn = norm_chroma(uv, maxv, full, bpc);
                    let crn = norm_chroma(vv, maxv, full, bpc);
                    let r = yn + 2.0 * (1.0 - kr) * crn;
                    let b = yn + 2.0 * (1.0 - kb) * cbn;
                    let g = (yn - kr * r - kb * b) / kg;
                    (to_u8(r), to_u8(g), to_u8(b))
                }
            };
            let o = (y * w + x) * 4;
            rgba[o] = r;
            rgba[o + 1] = g;
            rgba[o + 2] = b;
            rgba[o + 3] = 255;
        }
    }
    Ok((w as u32, h as u32, rgba))
}

/// Read one sample at column `i` from a row pointer: a byte for 8-bit sources, a
/// little-endian `u16` for deep (10/12-bit) ones. Plane bases are 64-aligned and
/// strides are even, so the `u16` read is aligned.
unsafe fn sample(row: *const u8, i: usize, deep: bool) -> u32 {
    if deep {
        *(row as *const u16).add(i) as u32
    } else {
        *row.add(i) as u32
    }
}

/// Normalise a luma sample to `[0,1]` (full range) or studio range.
fn norm_luma(s: u32, maxv: f32, full: bool, bpc: u8) -> f32 {
    if full {
        s as f32 / maxv
    } else {
        let lo = (16u32 << (bpc - 8)) as f32;
        let range = (219u32 << (bpc - 8)) as f32;
        (s as f32 - lo) / range
    }
}

/// Normalise a chroma sample to roughly `[-0.5, 0.5]` around its mid-point.
fn norm_chroma(s: u32, maxv: f32, full: bool, bpc: u8) -> f32 {
    let center = (1u32 << (bpc - 1)) as f32;
    if full {
        (s as f32 - center) / maxv
    } else {
        let range = (224u32 << (bpc - 8)) as f32;
        (s as f32 - center) / range
    }
}

/// Scale a `bpc`-bit sample straight to 8-bit (MC-identity GBR planes).
fn scale8(s: u32, maxv: f32) -> u8 {
    to_u8(s as f32 / maxv)
}

fn to_u8(v: f32) -> u8 {
    (v * 255.0 + 0.5).clamp(0.0, 255.0) as u8
}

/// Luma weights (Kr, Kb) for the CICP matrix-coefficient code. Defaults to BT.601
/// for SD/unspecified, which is also what most still encoders tag.
fn kr_kb(mtrx: u32) -> (f32, f32) {
    match mtrx {
        1 => (0.2126, 0.0722), // BT.709
        9 => (0.2627, 0.0593), // BT.2020 non-constant luminance
        _ => (0.299, 0.114),   // BT.601 (5/6) and the safe default
    }
}

/// Rotate a `w×h` RGBA buffer by `angle`×90° counter-clockwise (1/2/3), returning
/// `(new_w, new_h, pixels)`.
fn rotate_rgba(w: usize, h: usize, src: &[u8], angle: u8) -> (usize, usize, Vec<u8>) {
    let mut dst = vec![0u8; src.len()];
    match angle {
        2 => {
            // 180°: reverse pixel order.
            let n = w * h;
            for i in 0..n {
                let (s, d) = (i * 4, (n - 1 - i) * 4);
                dst[d..d + 4].copy_from_slice(&src[s..s + 4]);
            }
            (w, h, dst)
        }
        1 | 3 => {
            // 90° CCW (1) or CW (3); the destination is h×w.
            for y in 0..h {
                for x in 0..w {
                    let s = (y * w + x) * 4;
                    let (dx, dy) = if angle == 1 {
                        (y, w - 1 - x) // counter-clockwise
                    } else {
                        (h - 1 - y, x) // clockwise (= 270° CCW)
                    };
                    let d = (dy * h + dx) * 4; // dst width = h
                    dst[d..d + 4].copy_from_slice(&src[s..s + 4]);
                }
            }
            (h, w, dst)
        }
        _ => (w, h, src.to_vec()),
    }
}

/// Mirror a `w×h` RGBA buffer in place: `horizontal` flips left↔right, otherwise
/// top↔bottom.
fn flip_rgba(w: usize, h: usize, px: &mut [u8], horizontal: bool) {
    if horizontal {
        for y in 0..h {
            for x in 0..w / 2 {
                let (a, b) = ((y * w + x) * 4, (y * w + (w - 1 - x)) * 4);
                for k in 0..4 {
                    px.swap(a + k, b + k);
                }
            }
        }
    } else {
        for y in 0..h / 2 {
            for x in 0..w {
                let (a, b) = ((y * w + x) * 4, ((h - 1 - y) * w + x) * 4);
                for k in 0..4 {
                    px.swap(a + k, b + k);
                }
            }
        }
    }
}

/// Apply the AVIF orientation transform (irot `angle`×90° CCW, then imir) to an
/// RGBA buffer, returning the new dimensions and pixels.
fn apply_orientation(
    w: usize,
    h: usize,
    px: Vec<u8>,
    angle: u8,
    mirror: Option<u8>,
) -> (u32, u32, Vec<u8>) {
    let (w, h, mut px) = rotate_rgba(w, h, &px, angle);
    if let Some(mode) = mirror {
        flip_rgba(w, h, &mut px, mode == 1); // mode 1 = left↔right, 0 = top↔bottom
    }
    (w as u32, h as u32, px)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A 2×1 RGBA image: pixel0 = A(1,1,1), pixel1 = B(2,2,2).
    fn ab() -> Vec<u8> {
        vec![1, 1, 1, 255, 2, 2, 2, 255]
    }

    #[test]
    fn rotate_ccw_90() {
        // [A B] → column [B; A] (1 wide, 2 tall).
        let (w, h, px) = rotate_rgba(2, 1, &ab(), 1);
        assert_eq!((w, h), (1, 2));
        assert_eq!(&px[0..4], &[2, 2, 2, 255]); // top = B
        assert_eq!(&px[4..8], &[1, 1, 1, 255]); // bottom = A
    }

    #[test]
    fn rotate_cw_90() {
        // [A B] → column [A; B].
        let (w, h, px) = rotate_rgba(2, 1, &ab(), 3);
        assert_eq!((w, h), (1, 2));
        assert_eq!(&px[0..4], &[1, 1, 1, 255]);
        assert_eq!(&px[4..8], &[2, 2, 2, 255]);
    }

    #[test]
    fn rotate_180() {
        let (w, h, px) = rotate_rgba(2, 1, &ab(), 2);
        assert_eq!((w, h), (2, 1));
        assert_eq!(&px[0..4], &[2, 2, 2, 255]); // B then A
        assert_eq!(&px[4..8], &[1, 1, 1, 255]);
    }

    #[test]
    fn flip_horizontal() {
        let mut px = ab();
        flip_rgba(2, 1, &mut px, true);
        assert_eq!(&px[0..4], &[2, 2, 2, 255]); // B A
        assert_eq!(&px[4..8], &[1, 1, 1, 255]);
    }

    #[test]
    fn flip_vertical() {
        // column [A; B] flipped top↔bottom → [B; A].
        let mut px = vec![1, 1, 1, 255, 2, 2, 2, 255];
        flip_rgba(1, 2, &mut px, false);
        assert_eq!(&px[0..4], &[2, 2, 2, 255]);
        assert_eq!(&px[4..8], &[1, 1, 1, 255]);
    }
}
