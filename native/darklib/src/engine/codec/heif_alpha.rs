//! The alpha plane of a HEIF image, for platforms whose HEIF decoder drops it
//! (Hayn IMG-15: Android ignores Apple's alpha auxiliary and returns its
//! colour samples as opaque).
//!
//! DarkLib never decodes HEVC (patents, see the module above). It does the
//! container side in two steps around an HEVC decoder the app already ships:
//! [`alpha_stream`] extracts the alpha item(s) as one Annex-B elementary
//! stream, one frame per tile, which the caller decodes to 8-bit grey; then
//! [`attach_alpha`] assembles those frames, applies the alpha item's own
//! orientation, and writes the plane into the platform's decode of the colour
//! image. Every layout the reader does not answer for is an error, never a
//! guessed plane.

use std::io::Cursor;

use image::{
    codecs::png::{CompressionType, FilterType, PngEncoder},
    ExtendedColorType, ImageEncoder,
};

use super::avif_dav1d::apply_orientation;
use super::{decode, MAX_DECODE_PIXELS};
use crate::engine::error::{DarkError, Result};
use crate::engine::metadata::isobmff::{self, PrimaryAlpha};

/// The alpha plane's coded frames, ready for an HEVC decoder.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AlphaStream {
    /// Annex-B HEVC: each frame's parameter sets, then its picture.
    pub hevc: Vec<u8>,
    /// One frame per tile, in row-major tile order.
    pub frames: u32,
    /// Size of every frame; the decoded grey output is `frames × width × height`
    /// bytes.
    pub width: u32,
    pub height: u32,
}

/// Where the alpha samples go: a single item, or tiles on a grid canvas.
struct Layout {
    tiles: Vec<u32>,
    tile: (u32, u32),
    cols: u32,
    canvas: (u32, u32),
    /// Whose `irot`/`imir` apply to the assembled plane.
    oriented_by: u32,
    /// The colour samples are premultiplied by alpha (`prem` reference).
    premultiplied: bool,
}

fn bad(why: &'static str) -> DarkError {
    DarkError::Malformed(why)
}

fn layout(b: &[u8]) -> Result<Option<Layout>> {
    let primary = isobmff::primary_item_id(b).ok_or(bad("heif: no primary item"))?;
    let (tiles, cols, canvas, oriented_by, alpha_id) =
        match isobmff::primary_alpha(b).ok_or(bad("heif: unreadable alpha graph"))? {
            PrimaryAlpha::None => return Ok(None),
            PrimaryAlpha::Item(alpha) => match isobmff::read_grid(b, alpha) {
                Some(g) => (g.tiles, g.cols, (g.width, g.height), alpha, alpha),
                None => (vec![alpha], 1, (0, 0), alpha, alpha),
            },
            // Each tile of a grid primary has its own alpha item: the
            // primary's grid gives the canvas and its orientation applies.
            PrimaryAlpha::Tiles(ids) => {
                let g = isobmff::read_grid(b, primary).ok_or(bad("heif: no primary grid"))?;
                let first = *ids.first().ok_or(bad("heif: empty grid"))?;
                (ids, g.cols, (g.width, g.height), primary, first)
            }
        };
    let mut tile = None;
    for &id in &tiles {
        if isobmff::item_type(b, id) != Some(*b"hvc1") {
            return Err(bad("heif alpha: tile is not HEVC"));
        }
        let size = ispe(b, id).ok_or(bad("heif alpha: tile without ispe"))?;
        if *tile.get_or_insert(size) != size {
            // One frame size for the decoder's raw output.
            return Err(bad("heif alpha: tiles differ in size"));
        }
    }
    let tile = tile.ok_or(bad("heif alpha: no tiles"))?;
    let canvas = if canvas == (0, 0) { tile } else { canvas };
    let rows = (tiles.len() as u32).div_ceil(cols);
    if tile.0 == 0
        || tile.1 == 0
        || (tile.0 as u64 * cols as u64) < canvas.0 as u64
        || (tile.1 as u64 * rows as u64) < canvas.1 as u64
    {
        return Err(bad("heif alpha: tiles don't cover the canvas"));
    }
    if canvas.0 as u64 * canvas.1 as u64 > MAX_DECODE_PIXELS {
        return Err(DarkError::TooLarge);
    }
    // Clean-aperture crops are not applied here; refuse rather than misplace.
    for id in [oriented_by, alpha_id, primary] {
        if has_property(b, id, b"clap") {
            return Err(DarkError::UnsupportedFormat);
        }
    }
    let premultiplied =
        isobmff::iref_targets(b, b"prem", primary).is_some_and(|to| to.contains(&alpha_id));
    Ok(Some(Layout {
        tiles,
        tile,
        cols,
        canvas,
        oriented_by,
        premultiplied,
    }))
}

fn ispe(b: &[u8], id: u32) -> Option<(u32, u32)> {
    let p = property(b, id, b"ispe")?;
    Some((
        u32::from_be_bytes(p.get(12..16)?.try_into().ok()?),
        u32::from_be_bytes(p.get(16..20)?.try_into().ok()?),
    ))
}

fn property(b: &[u8], id: u32, typ: &[u8; 4]) -> Option<Vec<u8>> {
    isobmff::item_properties(b, id)?
        .into_iter()
        .find(|p| p.get(4..8) == Some(typ))
}

fn has_property(b: &[u8], id: u32, typ: &[u8; 4]) -> bool {
    property(b, id, typ).is_some()
}

/// The alpha plane of `b`'s primary image as an HEVC stream; `None` when the
/// image has no alpha. Errors on HEIF it cannot read or lay out.
pub fn alpha_stream(b: &[u8]) -> Result<Option<AlphaStream>> {
    let Some(l) = layout(b)? else {
        return Ok(None);
    };
    let mut hevc = Vec::new();
    for &id in &l.tiles {
        let hvcc = property(b, id, b"hvcC").ok_or(bad("heif alpha: no hvcC"))?;
        let nal_len = hvcc_parameter_sets(&hvcc, &mut hevc)?;
        let data = isobmff::read_item_by_id(b, id).ok_or(bad("heif alpha: unreadable item"))?;
        length_prefixed_to_annex_b(&data, nal_len, &mut hevc)?;
    }
    Ok(Some(AlphaStream {
        hevc,
        frames: l.tiles.len() as u32,
        width: l.tile.0,
        height: l.tile.1,
    }))
}

const START: [u8; 4] = [0, 0, 0, 1];

/// Appends the VPS/SPS/PPS arrays of an `hvcC` box (header included) as
/// Annex-B NAL units; returns the NAL length size of the item data.
fn hvcc_parameter_sets(hvcc: &[u8], out: &mut Vec<u8>) -> Result<usize> {
    let c = hvcc.get(8..).ok_or(bad("hvcC: short"))?;
    let nal_len = (*c.get(21).ok_or(bad("hvcC: short"))? & 3) as usize + 1;
    let arrays = *c.get(22).ok_or(bad("hvcC: short"))?;
    let mut q = 23usize;
    for _ in 0..arrays {
        q += 1; // array_completeness, reserved, NAL unit type
        let n = u16::from_be_bytes([
            *c.get(q).ok_or(bad("hvcC: short"))?,
            *c.get(q + 1).ok_or(bad("hvcC: short"))?,
        ]);
        q += 2;
        for _ in 0..n {
            let len = u16::from_be_bytes([
                *c.get(q).ok_or(bad("hvcC: short"))?,
                *c.get(q + 1).ok_or(bad("hvcC: short"))?,
            ]) as usize;
            q += 2;
            out.extend_from_slice(&START);
            out.extend_from_slice(c.get(q..q + len).ok_or(bad("hvcC: short"))?);
            q += len;
        }
    }
    Ok(nal_len)
}

fn length_prefixed_to_annex_b(data: &[u8], nal_len: usize, out: &mut Vec<u8>) -> Result<()> {
    let mut q = 0usize;
    while q < data.len() {
        let head = data
            .get(q..q + nal_len)
            .ok_or(bad("heif alpha: truncated NAL"))?;
        let len = head.iter().fold(0usize, |n, &x| (n << 8) | x as usize);
        q += nal_len;
        out.extend_from_slice(&START);
        out.extend_from_slice(
            data.get(q..q + len)
                .ok_or(bad("heif alpha: truncated NAL"))?,
        );
        q += len;
    }
    Ok(())
}

/// `base` (the platform's upright decode of `source`, any format DarkLib reads)
/// with `grey` — [`alpha_stream`]'s frames decoded to 8-bit full-range grey —
/// as its alpha, as an RGBA PNG. A base sampled down for a preview gets the
/// plane scaled to it; any other size mismatch is an error.
pub fn attach_alpha(source: &[u8], base: &[u8], grey: &[u8]) -> Result<Vec<u8>> {
    let l = layout(source)?.ok_or(bad("heif: no alpha to attach"))?;
    let (tw, th) = (l.tile.0 as usize, l.tile.1 as usize);
    if grey.len() != l.tiles.len() * tw * th {
        return Err(bad("heif alpha: decoded size mismatch"));
    }
    // Paste the tiles onto the canvas, cropping the right and bottom edges.
    let (cw, ch) = (l.canvas.0 as usize, l.canvas.1 as usize);
    let mut plane = vec![0u8; cw * ch];
    for (i, frame) in grey.chunks_exact(tw * th).enumerate() {
        let (x0, y0) = ((i % l.cols as usize) * tw, (i / l.cols as usize) * th);
        let copy_w = tw.min(cw.saturating_sub(x0));
        for ty in 0..th {
            let y = y0 + ty;
            if y >= ch || copy_w == 0 {
                break;
            }
            plane[y * cw + x0..y * cw + x0 + copy_w]
                .copy_from_slice(&frame[ty * tw..ty * tw + copy_w]);
        }
    }
    let (pw, ph, plane) = match isobmff::item_orientation(source, l.oriented_by) {
        Some((angle, mirror)) => apply_orientation(cw, ch, plane, angle, mirror, 1),
        None => (cw as u32, ch as u32, plane),
    };

    let mut img = decode(base, None)?;
    let plane = if (img.width, img.height) == (pw, ph) {
        plane
    } else if same_shape((pw, ph), (img.width, img.height)) {
        let grey = image::GrayImage::from_raw(pw, ph, plane).ok_or(bad("alpha plane"))?;
        image::imageops::resize(
            &grey,
            img.width,
            img.height,
            image::imageops::FilterType::Triangle,
        )
        .into_raw()
    } else {
        return Err(bad("heif alpha: plane does not match the image"));
    };
    for (px, &a) in img.rgba.as_chunks_mut::<4>().0.iter_mut().zip(&plane) {
        if l.premultiplied && a > 0 && a < 255 {
            for c in &mut px[..3] {
                *c = ((*c as u32 * 255 + a as u32 / 2) / a as u32).min(255) as u8;
            }
        }
        px[3] = a;
    }
    // Fast deflate: about 0.1 s against 2.1 s for a 12 MP image on a desktop
    // (+44% bytes). The result is mostly an intermediate the next engine
    // re-encodes; only a PNG target keeps it as is.
    let mut out = Cursor::new(Vec::new());
    PngEncoder::new_with_quality(&mut out, CompressionType::Fast, FilterType::Adaptive)
        .write_image(&img.rgba, img.width, img.height, ExtendedColorType::Rgba8)
        .map_err(|_| bad("png encode failed"))?;
    Ok(out.into_inner())
}

/// A preview sampled down by a power of two keeps the aspect ratio within a
/// pixel of rounding.
fn same_shape(full: (u32, u32), small: (u32, u32)) -> bool {
    small.0 <= full.0
        && small.1 <= full.1
        && (full.0 as u64 * small.1 as u64).abs_diff(full.1 as u64 * small.0 as u64)
            <= full.0.max(full.1) as u64
}
