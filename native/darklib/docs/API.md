# API reference

This is the curated reference for DarkLib's public surface — every function and
type, what it does, and how to use it. It covers two audiences:

- **Rust** consumers, who use the pure [`engine`](#rust-engine-api) directly.
- **Dart / Flutter** consumers, who use the [FFI surface](#dart--ffi-api)
  (`flutter_rust_bridge`).

> **Authoritative reference: rustdoc.** This file is a hand-curated companion;
> the always-in-sync, per-item reference is generated from the source:
> ```sh
> cargo doc --no-deps --open
> ```
> For a Rust *library*, rustdoc is the idiomatic equivalent of `man` pages — it
> stays in lockstep with the code and renders signatures, links and examples.
> (A roff `man` page would be a CLI convention and would drift; we don't ship
> one. It can be generated later if a downstream packager needs it.)

Conventions: fallible engine calls return `Result<T, DarkError>`; infallible
parsers return `Option<T>` and never panic on malformed input.

---

## Rust engine API

`use darklib::engine::{format, metadata, color, codec, error};`

### `engine::error`

```rust
pub enum DarkError {
    UnsupportedFormat,       // container not supported for this op (yet)
    Malformed(&'static str), // bytes malformed for their detected container
}
pub type Result<T> = std::result::Result<T, DarkError>;
```

`DarkError` is `Clone` + `Display`; the FFI layer converts it to a plain `String`.

### `engine::format` — detection & capability

```rust
pub fn detect(b: &[u8]) -> ImageFormat;
```
Identify the container from leading magic bytes. Pure, never panics; returns
`ImageFormat::Unknown` for unrecognised or too-short input.

```rust
pub enum ImageFormat { Jpeg, Png, Webp, Gif, Bmp, Tiff, Heic, Avif, Unknown }
```

```rust
pub struct FormatDescriptor {
    pub format: ImageFormat,
    pub supports_exif: bool,
    pub supports_xmp: bool,
    pub supports_icc: bool,
    pub supports_iptc: bool,
    pub supports_alpha: bool,
    pub lossless_metadata_ops: bool, // metadata add/remove with no re-encode
    pub hdr_capable: bool,           // deep bit depth OR a gain map
}
pub fn FormatDescriptor::of(format: ImageFormat) -> FormatDescriptor;
pub fn FormatDescriptor::loss_to(self, target: ImageFormat) -> ConversionLoss;
```
`of` returns what a format *can* carry (not whether DarkLib implements an op yet).
`loss_to` predicts, at the format-capability level, what a `self → target`
conversion would drop.

```rust
pub struct ConversionLoss { pub exif, xmp, icc, iptc, alpha, hdr: bool }
pub fn ConversionLoss::any(self) -> bool;   // true if anything would be lost
```

```rust
let d = format::FormatDescriptor::of(format::detect(bytes));
if d.lossless_metadata_ops { /* offer "strip metadata" */ }
let loss = d.loss_to(format::ImageFormat::Jpeg);
if loss.alpha { /* warn: JPEG drops transparency */ }
```

### `engine::metadata` — lossless container surgery

No re-encode: these rewrite containers, leaving coded pixels byte-identical.

```rust
pub struct Canonical {            // raw blobs, kept verbatim (no parse→reserialize)
    pub exif: Option<Vec<u8>>,    // TIFF block
    pub xmp:  Option<Vec<u8>>,    // XMP packet
    pub icc:  Option<Vec<u8>>,    // raw ICC profile
    pub iptc: Option<Vec<u8>>,
    pub orientation: u16,         // unified EXIF orientation (1 = upright)
}

pub enum IccPolicy { Keep, Strip }          // Keep = colour-safe (default)
pub enum OrientationPolicy { Keep }         // keep the orientation tag (no flip)
pub struct StripPolicy { pub icc: IccPolicy, pub orientation: OrientationPolicy }
impl Default for StripPolicy;               // { Keep, Keep }
```

```rust
pub fn strip(bytes: &[u8], policy: StripPolicy) -> Result<Vec<u8>>;
```
Remove EXIF/XMP/IPTC (and ICC if `policy.icc == Strip`) losslessly, dispatching on
the detected container (JPEG/PNG/WebP/AVIF/HEIF). HDR gain maps are preserved.
`Err(UnsupportedFormat)` for containers without an editor.

```rust
pub fn extract(b: &[u8]) -> Canonical;       // never fails; absent fields = None
pub fn inject(encoded: &[u8], meta: &Canonical) -> Vec<u8>;
```
`extract` reads the canonical model; `inject` writes EXIF/XMP/ICC back into already
-encoded bytes (orientation normalised to 1). Pair them around a re-encode to
carry metadata across a transcode. `inject` returns the input unchanged if it
can't safely add the items (verify-or-bail).

```rust
let meta  = metadata::extract(src);
let clean = metadata::strip(src, metadata::StripPolicy::default())?;
let withmeta = metadata::inject(&newly_encoded, &meta);
```

**Advanced / lower-level** (same module; mostly used internally — reach for these
only for format-specific work):
`metadata::isobmff::{extract_icc, extract_nclx, extract_exif_xmp, has_gainmap,
extract_primary_av1, extract_av1c_config_obus, inject}`,
`metadata::xmp::strip_privacy_keeping_hdr`,
`metadata::exif::{summarize, with_orientation_1, ExifSummary}`, and the per-format
`metadata::{jpeg,png,webp,isobmff}::strip`.

### `engine::color`

```rust
pub fn synthesize_from_cicp(primaries: u16, transfer: u16) -> Option<Vec<u8>>;
```
Build an ICC v4 profile from CICP code points (e.g. a profile-less Display-P3
HEIF tagged only with `nclx`), so the gamut survives a convert. `None` for
unsupported code points. Supported primaries: 1 (sRGB/709), 9 (BT.2020), 12 (P3);
SDR transfers.

### `engine::codec` — the pixel path (decode / encode / transcode)

```rust
pub struct Decoded { pub width: u32, pub height: u32, pub rgba: Vec<u8> } // 8-bit RGBA

pub enum Target {
    Jpeg(u8),                               // quality 1..=100 (opaque)
    Png,                                    // lossless
    Webp { quality: u8, lossless: bool },
    Avif { quality: u8 },                   // software (rav1e)
}

pub fn decode(bytes: &[u8], max_edge: Option<u32>) -> Result<Decoded>;
pub fn encode(img: &Decoded, target: Target) -> Result<Vec<u8>>;
pub fn transcode(bytes: &[u8], target: Target, max_edge: Option<u32>) -> Result<Vec<u8>>;
```
`decode` handles PNG/JPEG/WebP/AVIF (EXIF orientation baked into pixels); **HEIC is
not software-decoded** → `Err` (use a hardware/platform decoder). `max_edge`
downscales for **previews only** — `None` keeps full resolution; never downscale a
saved output. `transcode` = `decode → optional downscale → encode`.

```rust
let webp = codec::transcode(src, codec::Target::Webp { quality: 80, lossless: false }, None)?;
```

---

## Dart / FFI API

Exposed via `flutter_rust_bridge` under `darklib::api`. Function names map to Dart
(`detect_format` → `detectFormat`, etc.). `#[frb(sync)]` calls run inline; the
rest run on a worker pool (off the Dart isolate). Engine errors arrive as a Dart
exception carrying the `DarkError` message.

### `api::simple`
| Rust | Dart | Notes |
|---|---|---|
| `greet(name: String) -> String` | `greet` | smoke test |
| `darklib_version() -> String` | `darklibVersion` | crate version |
| `init_app()` | `initApp` | one-time init hook |

### `api::metadata`
```rust
#[frb(sync)] fn detect_format(bytes) -> ImageFormat
#[frb(sync)] fn describe_format(bytes) -> FormatInfo
#[frb(sync)] fn can_strip_lossless(bytes) -> bool
             fn strip_metadata(bytes, strip_icc: bool) -> Result<Vec<u8>, String>  // async
#[frb(sync)] fn read_metadata_summary(bytes) -> MetadataSummary

struct FormatInfo { format, supports_exif, supports_xmp, supports_icc,
                    supports_iptc, hdr_capable, can_strip }
struct MetadataSummary { has_exif, has_xmp, has_icc, has_gps, has_date,
                         has_camera, orientation: u16, tag_count: u32 }
```
`strip_metadata` keeps the orientation tag always and the ICC profile unless
`strip_icc` is true; throws on an unsupported container. `read_metadata_summary`
powers a "what will be removed" preview and works cross-platform incl. HEIC/AVIF.

### `api::codec`
```rust
enum CodecFormat { Jpeg, Png, Webp, WebpLossless, Avif }
fn transcode(bytes, format: CodecFormat, quality: u32, max_edge: u32) -> Result<Vec<u8>, String>
fn transcode_keep_metadata(bytes, format, quality, max_edge) -> Result<Vec<u8>, String>
```
`max_edge == 0` means keep original size. `transcode_keep_metadata` carries the
source's EXIF/XMP/ICC into the output where supported. Both throw on a container
the codec layer can't decode yet (notably **HEIC** — decode it on the platform
side and feed pixels in until hardware decode lands).

---

## Current limitations

- **HEIC decode** is hardware-only (no bundled software HEVC) — `decode`/
  `transcode` of a HEIC source returns an error; callers fall back to a platform
  decoder. See [FORMATS.md](FORMATS.md) and [SUPPORT.md](SUPPORT.md).
- **AVIF decode**: opaque only (the alpha auxiliary item isn't decoded yet), no
  `irot`/`imir` rotation (EXIF orientation is applied), and 10/12-bit is reduced
  to 8-bit RGBA (the current SDR contract).
- **HDR carry through a re-encode** (convert) isn't wired yet — a strip preserves
  the gain map, but a transcode currently drops it.
- **Very large images**: the encode path doesn't tile yet; previews use
  `max_edge`, but full-resolution tiling (no downscale) is planned.
