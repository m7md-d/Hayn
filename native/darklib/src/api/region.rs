//! FFI surface for reading an AVIF by regions, for display (Hayn PERF-03).
//! The zoomed views ask for the tiles in view; nothing decodes the whole
//! image to show it. Heavy → async, off the Dart isolate.

use std::path::Path;

use crate::engine::codec::region::AvifRegion;

/// A decoded tile: premultiplied 8-bit RGBA, row-major (what Flutter's
/// `rgba8888` takes).
pub struct RegionTile {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}

/// An AVIF read by regions (`engine::codec::region`). Dart owns it; its
/// cache files go when it is disposed.
pub struct RegionReader {
    inner: AvifRegion,
}

impl RegionReader {
    /// Reads the AVIF at `path` (the caller may delete it once this returns)
    /// and prepares it: a grid decodes one cell, one item is decoded whole
    /// into raw files under `cache_dir`. Throws for anything but an SDR AVIF
    /// whose colours convert to sRGB here, and past the decode budget.
    pub fn open(path: String, cache_dir: String) -> Result<RegionReader, String> {
        let bytes = std::fs::read(&path).map_err(|e| e.to_string())?;
        AvifRegion::open(bytes, Path::new(&cache_dir))
            .map(|inner| RegionReader { inner })
            .map_err(|e| e.to_string())
    }

    /// Upright width.
    #[flutter_rust_bridge::frb(sync, getter)]
    pub fn width(&self) -> u32 {
        self.inner.width()
    }

    /// Upright height.
    #[flutter_rust_bridge::frb(sync, getter)]
    pub fn height(&self) -> u32 {
        self.inner.height()
    }

    /// The upright rectangle `rect` = `[left, top, right, bottom)` sampled
    /// down by `sample` (a power of two), cut at the upright x positions
    /// `cuts` into tiles, left to right.
    pub fn tiles(
        &self,
        rect: Vec<u32>,
        cuts: Vec<u32>,
        sample: u32,
    ) -> Result<Vec<RegionTile>, String> {
        let rect: [u32; 4] = rect
            .try_into()
            .map_err(|_| "rect takes four values".to_string())?;
        self.inner
            .tiles(rect, &cuts, sample)
            .map(|tiles| {
                tiles
                    .into_iter()
                    .map(|t| RegionTile {
                        width: t.width,
                        height: t.height,
                        rgba: t.rgba,
                    })
                    .collect()
            })
            .map_err(|e| e.to_string())
    }
}
