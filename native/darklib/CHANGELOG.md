# Changelog

All notable changes to DarkLib are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project aims to
adopt [Semantic Versioning](https://semver.org/) from 1.0.0 onward. While pre-1.0
the engine API may change between minor versions.

## [Unreleased]

### Added
- **`engine::codec::region` and `api::region::RegionReader`**: an AVIF read by
  regions for display (Hayn PERF-03). A grid decodes only the cells a request
  covers, in parallel; one item is decoded once into raw RGBA files (a pyramid
  of halves) in a cache directory, deleted with the reader. Tiles come
  upright, with alpha, in sRGB, premultiplied, a row at a time. PQ/HLG and
  non-matrix profiles are refused.
- **`color::ToSrgb`**: 8-bit RGB in a matrix/TRC space to sRGB (D50 colorants,
  clipped), for display.
- **`color::rgb_space` and `api::inspect::profile_space`**: a matrix/TRC ICC
  profile (embedded, or built from `nclx`/`cICP`) as an RGB space — the D50
  RGB→XYZ matrix and the transfer in Android's `TransferParameters` form.
  LUT profiles and sampled curves give `None`. Hayn's Android bridge names a
  HEIC's values with it, since Android's decoder returns them unconverted.
- **`Facts.orientation`** from `inspect`: the EXIF code (1..=8) that turns the
  stored pixels upright, from `irot`/`imir` (new `isobmff::exif_orientation`)
  or the EXIF tag; 0 when none is named. Hayn's tiled HEIC encoder on Android
  keeps the stored pixels and writes this into the container (RUN-01).
- **Metadata `inject` into `idat` grids**: AVIF/HEIF whose grid descriptor is
  in `idat` (construction method 1) and whose `mdat` precedes `meta` — the
  shape `MediaMuxer`/`HeifWriter` write — now receive EXIF/XMP/ICC; before,
  the file came back unchanged. Validation compares every pre-existing item,
  `idat` ones included. The ICC property is associated with a grid's tiles as
  well as the grid (Android reads a grid's colour from its first tile).
- **AVIF software decode** via `rav1d` (the pure-Rust dav1d port) behind
  `engine::codec::decode`. Extracts the primary item's AV1 OBUs from the ISO-BMFF
  container (prepending the `av1C` sequence header) and converts planar YUV →
  RGBA for I400/I420/I422/I444, 8/10/12-bit, full/limited range, BT.601/709/2020
  and MC-identity. The whole `unsafe` dav1d lifecycle is contained in one module
  and fails closed (never returns a torn buffer).
- **AVIF alpha (transparency) decode**: the alpha auxiliary item is identified by
  its `auxC` aux-type URN mapped through `ipma` — so it is never confused with an
  HDR gain map (also an `auxl` auxiliary) — and decoded into the RGBA alpha
  channel. Failure or a size mismatch leaves the image opaque (never corrupts the
  colour decode).
- **AVIF orientation** (`irot`/`imir`): the primary image's rotation/mirror item
  properties (read via `ipma`→`ipco`) are baked into the decoded pixels, so AVIF
  is handled upright like every other format. Completes AVIF decode correctness.
- **AVIF ImageGrid (tiled) decode**: a `grid` primary — how large AVIF/HEIFs are
  commonly stored — is assembled from its `dimg` tiles (descriptor read from
  `idat` or `mdat`, construction methods 0 and 1). Tiles decode **one at a time**
  with their own per-item `av1C` config, so peak memory ≈ canvas + one tile; the
  canvas size is capped (256 MP) against malicious descriptors. A grid *alpha*
  auxiliary is assembled the same way. New `isobmff` readers: `primary_item_id`,
  `alpha_item_id`, `item_type`, `read_grid`/`GridInfo`, `extract_item_av1`,
  `av1c_for_item` (replacing `extract_alpha_av1`).
- **Tiled (ImageGrid) AVIF encode** — the "never downscale" answer to huge
  images: opaque images above 16 MP encode tile-by-tile (1024² tiles, edges
  replicated then cropped by the canvas) into a spec-shaped grid container
  (`isobmff::build_grid_avif` + `GridSpec` + `av1c_raw`: hidden tile items,
  essential `av1C`, `ispe`/`pixi`, descriptor in `idat`). Peak memory ≈ source +
  one tile, at full output resolution. Any grid failure falls back to the proven
  single-item encode; transparent images keep the single-item path for now.
- **HDR gain-map carry through convert** (AVIF→AVIF, full resolution):
  `engine::codec::transcode_keep_metadata` re-encodes the base AND the ISO
  21496-1 gain-map image, copies the `tmap` curve metadata verbatim, and rebuilds
  the container from scratch (`isobmff::read_tmap`/`TmapInfo`,
  `build_hdr_avif`/`CodedItem`: tmap derived item + `dimg`, `altr` fallback group,
  hidden gain-map item, essential `av1C`, EXIF/XMP/ICC included in the same
  build). Self-checks the output still reads as HDR with the identical curve; any
  failure falls back to the SDR convert. The FFI `transcode_keep_metadata` now
  delegates to this engine function.
- **Colour management** (`engine::color`): ICC profile extract/inject, plus
  synthesis of an ICC profile from CICP/`nclx` code points (primaries → D50
  colorants via Bradford adaptation + sRGB TRC), so a profile-less AVIF/HEIF
  keeps its gamut on convert.
- **Metadata carry through encode** (`engine::metadata::inject`) for JPEG, PNG,
  WebP and AVIF/HEIF, including WebP `VP8X` muxing and PNG `iCCP`.
- **HDR strip-safety**: a privacy strip preserves HDR gain maps — by construction
  for ISO-BMFF, and via XMP property surgery (`engine::metadata::xmp`) for
  Ultra-HDR JPEG.
- **Capability gate**: `FormatDescriptor` + `ConversionLoss` describe what each
  format can carry and what a conversion would lose.
- **Codec encode** for PNG/JPEG (`image`), WebP (`libwebp`) and AVIF (`rav1e`),
  with unified EXIF-orientation baking on decode.
- Lossless **metadata strip/extract** for JPEG, PNG, WebP and AVIF/HEIF
  (ISO-BMFF box rebuild with self-validation).
- Packaging for standalone reuse: crate metadata, `rlib` output, README and the
  `docs/` set.

### Changed
- **AV1 decode uses up to four threads** (was one) and converts YUV → RGBA in
  bands on the same number of threads; `avif_dav1d::decode_item_rows` hands
  the rows out band by band. On a Galaxy S25 Edge a 12 MP still decoded in
  375 ms instead of 820, a 1024 px grid cell in 36 ms instead of 80.
- The crate now also builds as an `rlib` so the pure `engine` is consumable as a
  normal Rust dependency.

### Removed
- **32-bit ARM (`armeabi-v7a`) support.** `rav1d` requires nightly Rust on that
  target (unstable NEON feature detection); every other target builds on stable.
  The Android build now ships arm64-v8a + x86_64 only. See `docs/SUPPORT.md`.

### Notes
- HEIC/HEIF remain decode-by-hardware only — software HEVC is patent-encumbered
  and is intentionally never bundled.
- HDR carry *through a re-encode* (convert) and a future `darklib-core` /
  `darklib-frb` workspace split are tracked for upcoming work.
