# Changelog

All notable changes to DarkLib are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project aims to
adopt [Semantic Versioning](https://semver.org/) from 1.0.0 onward. While pre-1.0
the engine API may change between minor versions.

## [Unreleased]

### Added
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
