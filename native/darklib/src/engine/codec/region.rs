//! Parts of an AVIF at a level of detail, for display (Hayn PERF-03).
//!
//! A zoomed view asks for the tiles in view at the detail the zoom needs, and
//! an image is never decoded whole to show it. AV1 has no partial decode, so
//! the reader works with what the container offers:
//!
//! - **Grid** (an ImageGrid of `av01` cells, as DarkLib writes past 16 MP):
//!   only the cells under a request are decoded, in parallel, one decoder
//!   thread each, and the last few stay in a small cache.
//! - **One item:** decoded once on open, its rows straight into a pyramid of
//!   raw files (full size, then halves down to a few hundred pixels) in the
//!   caller's cache directory, so the decoded image never stays in memory. A
//!   tile is then a read of its rows from the level it needs. The files go
//!   when the reader is dropped.
//!
//! Tiles come upright (`irot`/`imir` applied), in sRGB, with the alpha
//! auxiliary, premultiplied: what a display takes. A sampled tile averages
//! the full-size pixels of each `sample`×`sample` block, blocks counted from
//! the stored image's corner; for a mirrored or turned image that places a
//! sampled tile within one sampled pixel, and a full-size tile exactly.
//! A source whose colours cannot be shown right here is refused: PQ/HLG (no
//! tone mapper) and profiles that are not matrix/TRC.

use std::fs::{self, File};
use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use super::avif_dav1d::{self, decoder_threads};
use crate::engine::color::{rgb_space, ToSrgb};
use crate::engine::error::{DarkError, Result};
use crate::engine::format::{detect, ImageFormat};
use crate::engine::inspect::{inspect, Transfer};
use crate::engine::metadata::isobmff::{self, GridInfo, PrimaryAlpha};

/// Decoded grid cells kept between requests, in bytes (eight 1024² cells).
const CELL_CACHE_BYTES: usize = 32 << 20;

/// The pyramid stops at the first level whose long edge is at most this.
const PYRAMID_FLOOR: u32 = 256;

/// A tile: premultiplied 8-bit RGBA, row-major.
pub struct Tile {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

/// An AVIF read by regions; see the module documentation.
pub struct AvifRegion {
    bytes: Vec<u8>,
    stored_w: u32,
    stored_h: u32,
    angle: u8,
    mirror: Option<u8>,
    to_srgb: Option<ToSrgb>,
    source: Source,
}

enum Source {
    Grid {
        grid: GridInfo,
        alpha: GridAlpha,
        cell_w: u32,
        cell_h: u32,
        cache: Mutex<CellCache>,
    },
    Whole(Pyramid),
}

/// Where a grid's transparency is.
enum GridAlpha {
    None,
    /// One `av01` alpha item per cell.
    Cells(Vec<u32>),
    /// One alpha item for the whole canvas, decoded once: a byte per pixel.
    Canvas(Vec<u8>),
}

impl AvifRegion {
    /// Reads the container and prepares the reader. A grid decodes its first
    /// cell (its size); one item is decoded whole into the pyramid files
    /// under `cache_dir`. Errors for anything but an SDR AVIF whose colours
    /// convert to sRGB here, and past the decode budget.
    pub fn open(bytes: Vec<u8>, cache_dir: &Path) -> Result<Self> {
        if detect(&bytes) != ImageFormat::Avif {
            return Err(DarkError::Malformed("region: not an AVIF"));
        }
        super::check_decode_budget(&bytes)?;
        if matches!(inspect(&bytes).transfer, Transfer::Pq | Transfer::Hlg) {
            return Err(DarkError::Malformed(
                "region: PQ/HLG has no SDR display here",
            ));
        }
        let to_srgb = match crate::engine::metadata::extract(&bytes).icc {
            None => None, // no profile: sRGB
            Some(icc) => {
                let space = rgb_space(&icc)
                    .ok_or(DarkError::Malformed("region: profile is not matrix/TRC"))?;
                ToSrgb::new(&space)
            }
        };
        let primary = isobmff::primary_item_id(&bytes)
            .ok_or(DarkError::Malformed("avif: no primary item"))?;
        let (angle, mirror) = isobmff::read_orientation(&bytes).unwrap_or((0, None));
        let mut region = AvifRegion {
            bytes,
            stored_w: 0,
            stored_h: 0,
            angle,
            mirror,
            to_srgb,
            source: Source::Whole(Pyramid::default()),
        };
        match isobmff::read_grid(&region.bytes, primary) {
            Some(grid) => region.open_grid(grid)?,
            None => region.open_whole(primary, cache_dir)?,
        }
        Ok(region)
    }

    fn open_grid(&mut self, grid: GridInfo) -> Result<()> {
        let bad = |why| Err(DarkError::Malformed(why));
        let (w, h) = (grid.width, grid.height);
        if w == 0 || h == 0 || grid.tiles.is_empty() {
            return bad("avif grid: bad canvas size");
        }
        let alpha = match isobmff::primary_alpha(&self.bytes) {
            None => return bad("avif: alpha references unreadable"),
            Some(PrimaryAlpha::None) => GridAlpha::None,
            Some(PrimaryAlpha::Tiles(ids)) if ids.len() == grid.tiles.len() => {
                GridAlpha::Cells(ids)
            }
            Some(PrimaryAlpha::Tiles(_)) => return bad("avif grid: wrong alpha tile count"),
            Some(PrimaryAlpha::Item(id)) => match isobmff::read_grid(&self.bytes, id) {
                Some(a) if (a.rows, a.cols, a.width, a.height) == (grid.rows, grid.cols, w, h) => {
                    GridAlpha::Cells(a.tiles)
                }
                Some(_) => return bad("avif grid: alpha grid differs from the image"),
                None => GridAlpha::Canvas(self.alpha_plane(id, w, h)?),
            },
        };
        self.stored_w = w;
        self.stored_h = h;
        // The first cell gives the cell size, and checks the cells cover the
        // canvas, as a whole decode does.
        let (cw, ch, first) = self.decode_cell_with(&grid, &alpha, 0, 0, 0, decoder_threads())?;
        if (cw as u64) * (grid.cols as u64) < w as u64
            || (ch as u64) * (grid.rows as u64) < h as u64
        {
            return bad("avif grid: tiles don't cover canvas");
        }
        let mut cache = CellCache::default();
        cache.put(0, Arc::new(first));
        self.source = Source::Grid {
            grid,
            alpha,
            cell_w: cw,
            cell_h: ch,
            cache: Mutex::new(cache),
        };
        Ok(())
    }

    fn open_whole(&mut self, primary: u32, cache_dir: &Path) -> Result<()> {
        let (w, h) = isobmff::primary_extent(&self.bytes)
            .ok_or(DarkError::Malformed("avif: no dimensions"))?;
        let alpha = match isobmff::primary_alpha(&self.bytes) {
            None => return Err(DarkError::Malformed("avif: alpha references unreadable")),
            Some(PrimaryAlpha::None) => None,
            Some(PrimaryAlpha::Item(id)) => Some(self.alpha_plane(id, w, h)?),
            Some(PrimaryAlpha::Tiles(_)) => {
                return Err(DarkError::Malformed("avif: per-tile alpha without a grid"))
            }
        };
        let mut writer = PyramidWriter::create(cache_dir, w, h)?;
        let to_srgb = &self.to_srgb;
        let (dw, dh) = avif_dav1d::decode_item_rows(
            &self.bytes,
            primary,
            decoder_threads(),
            &mut |y0, band| {
                let mut band = band.to_vec();
                if let Some(a) = &alpha {
                    merge_alpha(&mut band, &a[y0 * w as usize..]);
                }
                if let Some(c) = to_srgb {
                    c.apply(&mut band);
                }
                writer.rows(&band)
            },
        )?;
        if (dw, dh) != (w, h) {
            return Err(DarkError::Malformed("avif: decoded size differs from ispe"));
        }
        self.stored_w = w;
        self.stored_h = h;
        self.source = Source::Whole(writer.finish()?);
        Ok(())
    }

    /// Alpha item `id` (not a grid) as one byte per pixel, `w`×`h`.
    fn alpha_plane(&self, id: u32, w: u32, h: u32) -> Result<Vec<u8>> {
        let mut plane = Vec::with_capacity(w as usize * h as usize);
        let (aw, ah) =
            avif_dav1d::decode_item_rows(&self.bytes, id, decoder_threads(), &mut |_, band| {
                plane.extend(band.as_chunks::<4>().0.iter().map(|p| p[0]));
                Ok(())
            })?;
        if (aw, ah) != (w, h) {
            return Err(DarkError::Malformed(
                "avif: alpha size differs from the image",
            ));
        }
        Ok(plane)
    }

    /// Upright width.
    pub fn width(&self) -> u32 {
        if self.angle & 1 == 1 {
            self.stored_h
        } else {
            self.stored_w
        }
    }

    /// Upright height.
    pub fn height(&self) -> u32 {
        if self.angle & 1 == 1 {
            self.stored_w
        } else {
            self.stored_h
        }
    }

    /// The upright rectangle `[left, top, right, bottom)` sampled down by
    /// `sample` (a power of two), cut at the upright x positions `cuts` into
    /// tiles, left to right: one row of a view in one call.
    pub fn tiles(&self, rect: [u32; 4], cuts: &[u32], sample: u32) -> Result<Vec<Tile>> {
        let s = sample.clamp(1, 1 << 12);
        if !s.is_power_of_two() {
            return Err(DarkError::Malformed("region: sample is not a power of two"));
        }
        let (uw, uh) = (self.width(), self.height());
        let l = rect[0].min(uw);
        let t = rect[1].min(uh);
        let r = rect[2].clamp(l, uw);
        let b = rect[3].clamp(t, uh);
        if r == l || b == t {
            return Err(DarkError::Malformed("region: empty rectangle"));
        }
        let [sl, st, sr, sb] = stored_rect(
            self.angle,
            self.mirror,
            self.stored_w,
            self.stored_h,
            [l, t, r, b],
        );
        let (bw, bh, block) = match &self.source {
            Source::Whole(p) => p.read([sl, st, sr, sb], s)?,
            Source::Grid { .. } => self.grid_block([sl, st, sr, sb], s)?,
        };
        let (bw, bh, mut block) = avif_dav1d::apply_orientation(
            bw as usize,
            bh as usize,
            block,
            self.angle,
            self.mirror,
            4,
        );
        premultiply(&mut block);
        // Cut points in the block's columns; the block starts at `l / s`.
        let mut edges: Vec<u32> = vec![0];
        edges.extend(
            cuts.iter()
                .filter(|&&c| c > l && c < r)
                .map(|&c| (c / s).saturating_sub(l / s).min(bw)),
        );
        edges.push(bw);
        let mut out = Vec::with_capacity(edges.len() - 1);
        for pair in edges.windows(2) {
            let (x0, x1) = (pair[0] as usize, pair[1] as usize);
            if x1 <= x0 {
                continue;
            }
            let tw = x1 - x0;
            let mut rgba = Vec::with_capacity(tw * bh as usize * 4);
            for row in block.chunks_exact(bw as usize * 4) {
                rgba.extend_from_slice(&row[x0 * 4..x1 * 4]);
            }
            out.push(Tile {
                width: tw as u32,
                height: bh,
                rgba,
            });
        }
        Ok(out)
    }

    /// The stored rectangle sampled by `s`, from the grid cells under it:
    /// `(width, height, straight RGBA)`.
    fn grid_block(&self, rect: [u32; 4], s: u32) -> Result<(u32, u32, Vec<u8>)> {
        let Source::Grid {
            grid,
            alpha,
            cell_w,
            cell_h,
            cache,
        } = &self.source
        else {
            unreachable!("grid_block on a whole image");
        };
        let (cw, ch) = (*cell_w, *cell_h);
        let win = sampled_window(rect, s, self.stored_w, self.stored_h);
        let [x0, y0, x1, y1] = win.stored;
        let (ow, oh) = (win.w as usize, win.h as usize);
        let cols = (x0 / cw)..=((x1 - 1) / cw);
        let rows = (y0 / ch)..=((y1 - 1) / ch);
        let cells: Vec<usize> = rows
            .flat_map(|r| cols.clone().map(move |c| (r * grid.cols + c) as usize))
            .collect();
        let mut acc = Accumulator::new(ow, oh, s, win.x, win.y);
        // A few at a time, in parallel: a view's cells at a coarse level are
        // many, and holding them all would cost what a whole decode does.
        let batch = decoder_threads();
        for chunk in cells.chunks(batch) {
            let mut have: Vec<(usize, Arc<Vec<u8>>)> = Vec::with_capacity(chunk.len());
            let mut missing = Vec::new();
            {
                let mut cache = cache
                    .lock()
                    .map_err(|_| DarkError::Malformed("region: cache"))?;
                for &i in chunk {
                    match cache.get(i) {
                        Some(px) => have.push((i, px)),
                        None => missing.push(i),
                    }
                }
            }
            let decoded: Vec<Result<(usize, Vec<u8>)>> = std::thread::scope(|scope| {
                let jobs: Vec<_> = missing
                    .iter()
                    .map(|&i| {
                        scope.spawn(move || {
                            let (c, r) = (i as u32 % grid.cols, i as u32 / grid.cols);
                            self.decode_cell_with(grid, alpha, i, c * cw, r * ch, 1)
                                .and_then(|(w, h, px)| {
                                    if (w, h) == (cw, ch) {
                                        Ok((i, px))
                                    } else {
                                        Err(DarkError::Malformed("avif grid: tile size mismatch"))
                                    }
                                })
                        })
                    })
                    .collect();
                jobs.into_iter()
                    .map(|j| {
                        j.join()
                            .unwrap_or(Err(DarkError::Malformed("region: cell decode")))
                    })
                    .collect()
            });
            for d in decoded {
                let (i, px) = d?;
                let px = Arc::new(px);
                if let Ok(mut cache) = cache.lock() {
                    cache.put(i, Arc::clone(&px));
                }
                have.push((i, px));
            }
            for (i, px) in have {
                let (c, r) = (i as u32 % grid.cols, i as u32 / grid.cols);
                acc.add_cell(&px, cw, ch, c * cw, r * ch, win.stored);
            }
        }
        Ok((win.w, win.h, acc.finish()))
    }

    /// Grid cell `i` (stored origin `x`, `y`) decoded with `threads` decoder
    /// threads: its alpha merged, in sRGB. `(width, height, straight RGBA)`.
    fn decode_cell_with(
        &self,
        grid: &GridInfo,
        alpha: &GridAlpha,
        i: usize,
        x: u32,
        y: u32,
        threads: usize,
    ) -> Result<(u32, u32, Vec<u8>)> {
        let mut px = Vec::new();
        let (w, h) =
            avif_dav1d::decode_item_rows(&self.bytes, grid.tiles[i], threads, &mut |_, band| {
                px.extend_from_slice(band);
                Ok(())
            })?;
        match alpha {
            GridAlpha::None => {}
            GridAlpha::Cells(ids) => {
                let mut a = Vec::with_capacity(px.len() / 4);
                let (aw, ah) =
                    avif_dav1d::decode_item_rows(&self.bytes, ids[i], threads, &mut |_, band| {
                        a.extend(band.as_chunks::<4>().0.iter().map(|p| p[0]));
                        Ok(())
                    })?;
                if (aw, ah) != (w, h) {
                    return Err(DarkError::Malformed(
                        "avif: alpha size differs from the image",
                    ));
                }
                merge_alpha(&mut px, &a);
            }
            GridAlpha::Canvas(plane) => {
                // The canvas crops the right and bottom cells.
                let cw = self.stored_w as usize;
                for (dy, row) in px.chunks_exact_mut(w as usize * 4).enumerate() {
                    let sy = y as usize + dy;
                    if sy >= self.stored_h as usize {
                        break;
                    }
                    for (dx, p) in row.as_chunks_mut::<4>().0.iter_mut().enumerate() {
                        let sx = x as usize + dx;
                        if sx < cw {
                            p[3] = plane[sy * cw + sx];
                        }
                    }
                }
            }
        }
        if let Some(c) = &self.to_srgb {
            c.apply(&mut px);
        }
        Ok((w, h, px))
    }
}

/// The stored-pixel rectangle under an upright one. The upright image is the
/// stored one turned `angle`×90° counter-clockwise, then mirrored (`imir`
/// mode 1 left↔right, 0 top↔bottom), as [`avif_dav1d::apply_orientation`]
/// turns it.
fn stored_rect(angle: u8, mirror: Option<u8>, w: u32, h: u32, rect: [u32; 4]) -> [u32; 4] {
    // Size after the turn, where the mirror applies.
    let (rw, rh) = if angle & 1 == 1 { (h, w) } else { (w, h) };
    let [mut l, mut t, mut r, mut b] = rect;
    match mirror {
        Some(1) => (l, r) = (rw - r, rw - l),
        Some(0) => (t, b) = (rh - b, rh - t),
        _ => {}
    }
    // Undo the turn: a point (u, v) of the turned image came from (x, y).
    match angle & 3 {
        1 => [w - b, l, w - t, r], // (u, v) = (y, w - x)
        2 => [w - r, h - b, w - l, h - t],
        3 => [t, h - r, b, h - l], // (u, v) = (h - y, x)
        _ => [l, t, r, b],
    }
}

/// A stored rectangle sampled by `s`: its sampled origin and size, and the
/// stored pixels those sampled pixels average (blocks counted from the
/// stored image's corner, the last ones cut by its edge).
struct Window {
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    stored: [u32; 4],
}

fn sampled_window(rect: [u32; 4], s: u32, w: u32, h: u32) -> Window {
    let [l, t, r, b] = rect;
    let (lw, lh) = (w.div_ceil(s), h.div_ceil(s));
    let x = (l / s).min(lw - 1);
    let y = (t / s).min(lh - 1);
    let ow = (r - l).div_ceil(s).min(lw - x).max(1);
    let oh = (b - t).div_ceil(s).min(lh - y).max(1);
    Window {
        x,
        y,
        w: ow,
        h: oh,
        stored: [x * s, y * s, ((x + ow) * s).min(w), ((y + oh) * s).min(h)],
    }
}

/// Averages full-size pixels into their sampled pixels.
struct Accumulator {
    w: usize,
    h: usize,
    s: u32,
    x: u32,
    y: u32,
    sum: Vec<u32>,
    count: Vec<u32>,
}

impl Accumulator {
    fn new(w: usize, h: usize, s: u32, x: u32, y: u32) -> Self {
        Accumulator {
            w,
            h,
            s,
            x,
            y,
            sum: vec![0; w * h * 4],
            count: vec![0; w * h],
        }
    }

    /// Adds the pixels of a `cw`×`ch` cell at stored (`ox`, `oy`) that fall in
    /// `stored` (the window).
    fn add_cell(&mut self, px: &[u8], cw: u32, ch: u32, ox: u32, oy: u32, stored: [u32; 4]) {
        let [x0, y0, x1, y1] = stored;
        let (ax0, ax1) = (x0.max(ox), x1.min(ox + cw));
        let (ay0, ay1) = (y0.max(oy), y1.min(oy + ch));
        for sy in ay0..ay1 {
            let row = ((sy - oy) * cw) as usize * 4;
            let oyi = (sy / self.s - self.y) as usize;
            for sx in ax0..ax1 {
                let p = row + (sx - ox) as usize * 4;
                let o = oyi * self.w + (sx / self.s - self.x) as usize;
                for c in 0..4 {
                    self.sum[o * 4 + c] += px[p + c] as u32;
                }
                self.count[o] += 1;
            }
        }
    }

    fn finish(self) -> Vec<u8> {
        let mut out = vec![0u8; self.w * self.h * 4];
        for (o, &n) in self.count.iter().enumerate() {
            let n = n.max(1);
            for c in 0..4 {
                out[o * 4 + c] = ((self.sum[o * 4 + c] + n / 2) / n) as u8;
            }
        }
        out
    }
}

/// Alpha bytes `a`, one per pixel, into the alpha of straight RGBA `px`.
fn merge_alpha(px: &mut [u8], a: &[u8]) {
    for (p, &a) in px.as_chunks_mut::<4>().0.iter_mut().zip(a) {
        p[3] = a;
    }
}

/// Straight RGBA to premultiplied, in place.
fn premultiply(px: &mut [u8]) {
    for p in px.as_chunks_mut::<4>().0 {
        let a = p[3] as u32;
        if a != 255 {
            for v in &mut p[..3] {
                *v = ((*v as u32 * a + 127) / 255) as u8;
            }
        }
    }
}

/// Recently used decoded cells, within [`CELL_CACHE_BYTES`].
#[derive(Default)]
struct CellCache {
    /// Least recently used first.
    cells: Vec<(usize, Arc<Vec<u8>>)>,
}

impl CellCache {
    fn get(&mut self, i: usize) -> Option<Arc<Vec<u8>>> {
        let at = self.cells.iter().position(|(k, _)| *k == i)?;
        let hit = self.cells.remove(at);
        let px = Arc::clone(&hit.1);
        self.cells.push(hit);
        Some(px)
    }

    fn put(&mut self, i: usize, px: Arc<Vec<u8>>) {
        self.cells.retain(|(k, _)| *k != i);
        self.cells.push((i, px));
        let mut total: usize = self.cells.iter().map(|(_, p)| p.len()).sum();
        while total > CELL_CACHE_BYTES && self.cells.len() > 1 {
            total -= self.cells.remove(0).1.len();
        }
    }
}

/// The decoded image as raw straight RGBA files: level k is the image
/// sampled by 2^k. Deleted on drop.
#[derive(Default)]
struct Pyramid {
    levels: Vec<Level>,
}

struct Level {
    path: PathBuf,
    file: File,
    w: u32,
    h: u32,
}

impl Drop for Pyramid {
    fn drop(&mut self) {
        for l in &self.levels {
            let _ = fs::remove_file(&l.path);
        }
    }
}

impl Pyramid {
    /// The stored rectangle sampled by `s`: `(width, height, straight RGBA)`
    /// from the level of `s`, or averaged further from the coarsest.
    fn read(&self, rect: [u32; 4], s: u32) -> Result<(u32, u32, Vec<u8>)> {
        let k = (s.trailing_zeros() as usize).min(self.levels.len() - 1);
        let level = &self.levels[k];
        let ls = 1u32 << k; // the level's own sample
        let full_w = self.levels[0].w;
        let full_h = self.levels[0].h;
        let win = sampled_window(rect, s, full_w, full_h);
        // The window in the level's pixels.
        let f = s / ls;
        let [x0, y0, x1, y1] = win.stored;
        let (lx0, ly0) = (x0 / ls, y0 / ls);
        let (lx1, ly1) = (x1.div_ceil(ls).min(level.w), y1.div_ceil(ls).min(level.h));
        let (lw, lh) = (lx1 - lx0, ly1 - ly0);
        let mut px = vec![0u8; lw as usize * lh as usize * 4];
        for (dy, row) in px.chunks_exact_mut(lw as usize * 4).enumerate() {
            let at = ((ly0 as u64 + dy as u64) * level.w as u64 + lx0 as u64) * 4;
            read_at(&level.file, row, at)?;
        }
        if f == 1 {
            return Ok((lw, lh, px));
        }
        let mut acc = Accumulator::new(win.w as usize, win.h as usize, f, win.x, win.y);
        acc.add_cell(&px, lw, lh, lx0, ly0, [lx0, ly0, lx1, ly1]);
        Ok((win.w, win.h, acc.finish()))
    }
}

/// Writes level 0 row by row, then halves it down to the floor.
struct PyramidWriter {
    dir: PathBuf,
    stem: String,
    w: u32,
    h: u32,
    first: Option<(PathBuf, BufWriter<File>)>,
    written: u64,
}

static NEXT: AtomicU64 = AtomicU64::new(0);

impl PyramidWriter {
    fn create(dir: &Path, w: u32, h: u32) -> Result<Self> {
        let stem = format!(
            "darklib-region-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        );
        let path = dir.join(format!("{stem}-0"));
        let file = create(&path)?;
        Ok(PyramidWriter {
            dir: dir.to_path_buf(),
            stem,
            w,
            h,
            first: Some((path, BufWriter::with_capacity(1 << 20, file))),
            written: 0,
        })
    }

    fn rows(&mut self, band: &[u8]) -> Result<()> {
        let (_, out) = self
            .first
            .as_mut()
            .ok_or(DarkError::Malformed("region: closed"))?;
        out.write_all(band)
            .map_err(|_| DarkError::Malformed("region: cache write"))?;
        self.written += band.len() as u64;
        Ok(())
    }

    fn finish(mut self) -> Result<Pyramid> {
        let io = |_| DarkError::Malformed("region: cache write");
        let (path, out) = self
            .first
            .take()
            .ok_or(DarkError::Malformed("region: closed"))?;
        let file = out
            .into_inner()
            .map_err(|_| DarkError::Malformed("region: cache write"))?;
        let mut pyramid = Pyramid::default();
        pyramid.levels.push(Level {
            path,
            file,
            w: self.w,
            h: self.h,
        });
        if self.written != self.w as u64 * self.h as u64 * 4 {
            return Err(DarkError::Malformed("region: short decode"));
        }
        while {
            let l = pyramid.levels.last().expect("level 0");
            l.w.max(l.h) > PYRAMID_FLOOR && l.w > 1 && l.h > 1
        } {
            let k = pyramid.levels.len();
            let prev = &pyramid.levels[k - 1];
            let (pw, ph) = (prev.w as usize, prev.h as usize);
            let (nw, nh) = (pw.div_ceil(2), ph.div_ceil(2));
            let path = self.dir.join(format!("{}-{k}", self.stem));
            let file = create(&path)?;
            let mut out = BufWriter::with_capacity(1 << 20, file);
            let mut pair = vec![0u8; pw * 2 * 4];
            let mut next = vec![0u8; nw * 4];
            for y in 0..nh {
                let rows = if 2 * y + 1 < ph { 2 } else { 1 };
                read_at(
                    &prev.file,
                    &mut pair[..pw * rows * 4],
                    (2 * y * pw * 4) as u64,
                )?;
                for x in 0..nw {
                    let cols = if 2 * x + 1 < pw { 2 } else { 1 };
                    for c in 0..4 {
                        let mut sum = 0u32;
                        for dy in 0..rows {
                            for dx in 0..cols {
                                sum += pair[(dy * pw + 2 * x + dx) * 4 + c] as u32;
                            }
                        }
                        let n = (rows * cols) as u32;
                        next[x * 4 + c] = ((sum + n / 2) / n) as u8;
                    }
                }
                out.write_all(&next).map_err(io)?;
            }
            let file = out
                .into_inner()
                .map_err(|_| DarkError::Malformed("region: cache write"))?;
            pyramid.levels.push(Level {
                path,
                file,
                w: nw as u32,
                h: nh as u32,
            });
        }
        Ok(pyramid)
    }
}

impl Drop for PyramidWriter {
    fn drop(&mut self) {
        // Unfinished (a decode failed): its file goes.
        if let Some((path, _)) = self.first.take() {
            let _ = fs::remove_file(path);
        }
    }
}

/// A new cache file, read back once written.
fn create(path: &Path) -> Result<File> {
    fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(true)
        .open(path)
        .map_err(|_| DarkError::Malformed("region: cache file"))
}

/// Fills `buf` from `file` at byte `at`.
fn read_at(file: &File, buf: &mut [u8], at: u64) -> Result<()> {
    let err = |_| DarkError::Malformed("region: cache read");
    #[cfg(unix)]
    {
        use std::os::unix::fs::FileExt;
        file.read_exact_at(buf, at).map_err(err)
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::FileExt;
        let mut done = 0;
        while done < buf.len() {
            let n = file
                .seek_read(&mut buf[done..], at + done as u64)
                .map_err(err)?;
            if n == 0 {
                return Err(DarkError::Malformed("region: cache read"));
            }
            done += n;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::codec::{decode, Decoded};

    /// For every turn and mirror: the stored pixels under an upright
    /// rectangle, turned the same way, are that rectangle of the upright
    /// image. A 7×5 image of distinct pixels, every rectangle of it.
    #[test]
    fn stored_rect_is_the_upright_one() {
        let (w, h) = (7usize, 5usize);
        let px: Vec<u8> = (0..(w * h) as u8).flat_map(|i| [i, 0, 0, 255]).collect();
        let crop = |px: &[u8], pw: usize, [l, t, r, b]: [u32; 4]| -> Vec<u8> {
            let mut out = Vec::new();
            for y in t as usize..b as usize {
                out.extend_from_slice(&px[(y * pw + l as usize) * 4..(y * pw + r as usize) * 4]);
            }
            out
        };
        for angle in 0..4u8 {
            for mirror in [None, Some(0), Some(1)] {
                let (uw, uh, upright) =
                    avif_dav1d::apply_orientation(w, h, px.clone(), angle, mirror, 4);
                for t in 0..uh {
                    for b in t + 1..=uh {
                        for l in 0..uw {
                            for r in l + 1..=uw {
                                let s =
                                    stored_rect(angle, mirror, w as u32, h as u32, [l, t, r, b]);
                                let part = crop(&px, w, s);
                                let (pw, ph, turned) = avif_dav1d::apply_orientation(
                                    (s[2] - s[0]) as usize,
                                    (s[3] - s[1]) as usize,
                                    part,
                                    angle,
                                    mirror,
                                    4,
                                );
                                assert_eq!((pw, ph), (r - l, b - t), "{angle} {mirror:?}");
                                assert_eq!(
                                    turned,
                                    crop(&upright, uw as usize, [l, t, r, b]),
                                    "{angle} {mirror:?} [{l} {t} {r} {b}]"
                                );
                            }
                        }
                    }
                }
            }
        }
    }

    /// DarkLib's own grid, cells that do not divide the canvas (300×200 in
    /// 64 px cells): the whole image in one request, at full size and
    /// sampled by 4 (blocks across cell edges).
    #[test]
    fn partial_cells_read_whole_and_sampled() {
        let (w, h) = (300u32, 200u32);
        let mut rgba = Vec::new();
        for y in 0..h {
            for x in 0..w {
                rgba.extend_from_slice(&[
                    (x % 256) as u8,
                    (y % 256) as u8,
                    ((x + y) % 7 * 30) as u8,
                    255,
                ]);
            }
        }
        let avif = super::super::encode_avif_grid(
            &Decoded {
                width: w,
                height: h,
                rgba,
            },
            90,
            None,
            64,
        )
        .unwrap();
        let whole = decode(&avif, None).unwrap();
        let region = AvifRegion::open(avif, &std::env::temp_dir()).unwrap();
        assert!(matches!(region.source, Source::Grid { .. }));
        let full = region.tiles([0, 0, w, h], &[], 1).unwrap();
        assert_eq!((full[0].width, full[0].height), (w, h));
        assert!(full[0].rgba == whole.rgba);
        let s = 4;
        let sampled = &region.tiles([0, 0, w, h], &[], s).unwrap()[0];
        assert_eq!((sampled.width, sampled.height), (w / s, h / s));
        for (oy, ox) in [(0, 0), (15, 15), (16, 16), (49, 74)] {
            for c in 0..3 {
                let mut sum = 0u32;
                for y in oy * s..oy * s + s {
                    for x in ox * s..ox * s + s {
                        sum += whole.rgba[((y * w + x) * 4) as usize + c] as u32;
                    }
                }
                let got = sampled.rgba[((oy * (w / s) + ox) * 4) as usize + c] as u32;
                assert!(got.abs_diff((sum + 8) / 16) <= 1, "({ox},{oy}) channel {c}");
            }
        }
    }
}
