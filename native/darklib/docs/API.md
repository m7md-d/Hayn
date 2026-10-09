# API reference

> Status reviewed 2026-09-26: this describes the experimental implementation, not a preservation guarantee. The [bounded contract](../../../docs/10-DARKLIB.md) and [known defects](../../../docs/12-STABILIZATION.md) take precedence over older completion claims.

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
Requests EXIF/XMP/IPTC removal (and ICC if `policy.icc == Strip`), dispatching on
the detected container (JPEG/PNG/WebP/AVIF/HEIF) without pixel re-encoding.
Known orientation and Ultra-HDR MPF defects mean this is not a preservation
guarantee; see the stabilization plan.
`Err(UnsupportedFormat)` for containers without an editor.

```rust
pub fn extract(b: &[u8]) -> Canonical;       // never fails; absent fields = None
pub fn inject(encoded: &[u8], meta: &Canonical) -> Vec<u8>;
pub fn inject_reporting(encoded: &[u8], meta: &Canonical) -> Injected; // { bytes, dropped: Vec<MetaKind> }
```
`extract` reads the canonical model; `inject` writes EXIF/XMP/ICC back into already
-encoded bytes (orientation normalised to 1). AVIF/HEIF: items stored in the file
or in `idat` (a grid descriptor, as Android's `MediaMuxer` writes it, `mdat`
first or last); the ICC goes to the primary and, for a grid, to every tile —
Android reads a grid's colour from its first tile. Pair them around a re-encode to
carry metadata across a transcode. `inject` returns the input unchanged if it
can't safely add the items (verify-or-bail). In JPEG and PNG
each kind `meta` carries replaces the target's own (a JPEG from Android's
`Bitmap.compress` already names its bitmap's profile; two would make readers
drop both, Hayn IMG-24); a kind `meta` lacks stays, and a leading JFIF stays
first. In JPEG an ICC profile goes in numbered APP2 chunks (up to 255 of
64 KB), IPTC in APP13, and EXIF or XMP past one segment's 64 KB is left out
(Extended XMP is not written), the target's own of that kind staying.
`extract` joins ICC chunks by their numbers; a gap, a repeat or a count that
differs is no profile. WebP rebuilds its metadata chunks from `meta`.
`inject_reporting` says which kinds `meta` held that the target could not
take — a segment too large, IPTC outside JPEG, a layout outside the
supported ones — and `inject` is its bytes (Hayn RV-04). That is what was
written, not proof that it was read the same way: an independent reader
still decides preservation. FFI: `api::metadata::transplant_metadata`
returns `Transplanted { bytes, dropped }`, and `codec::Transcoded` has
`dropped` too.

Every writer prepares `meta` through one step, `carry::for_target` (the
intermediate-form contract, Hayn docs/10-DARKLIB.md): EXIF without its old
thumbnail and upright, one XMP packet (a JPEG's Extended XMP joined, then
split again for a JPEG target with an MD5 GUID), IPTC-IIM as JPEG's APP13 or
as IPTC Core XMP elsewhere (the source's XMP wins; a conflict without a
matching IPTCDigest is reported), ICC as it is. `Canonical::xmp` is always
the bare packet (a PNG's `iTXt` unwrapped and inflated).

```rust
let meta  = metadata::extract(src);
let clean = metadata::strip(src, metadata::StripPolicy::default())?;
let withmeta = metadata::inject(&newly_encoded, &meta);
```

**Advanced / lower-level** (same module; mostly used internally — reach for these
only for format-specific work):
`metadata::isobmff::{extract_icc, extract_nclx, extract_exif_xmp, has_gainmap,
primary_item_id, alpha_item_id, item_type, read_grid (GridInfo), extract_item_av1,
extract_primary_av1, av1c_for_item, extract_av1c_config_obus, read_orientation,
inject}`, `metadata::xmp::strip_privacy_keeping_hdr`,
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
    Avif { quality: u8, depth: Option<u8> }, // software (rav1e); 8 or 10, None = 10
}

pub enum HdrOutcome { None, GainMapKept, GainMapDropped, GainMapKeepFailed }
pub struct Transcoded { pub bytes: Vec<u8>, pub hdr: HdrOutcome }

pub fn decode(bytes: &[u8], max_edge: Option<u32>) -> Result<Decoded>;
pub fn encode(img: &Decoded, target: Target) -> Result<Vec<u8>>;
pub fn transcode(bytes: &[u8], target: Target, max_edge: Option<u32>,
                 keep_metadata: bool) -> Result<Transcoded>;
```
AVIF `depth` is the user's choice (Hayn IMG-23): 8 or 10 bits per channel;
`None` keeps rav1e's default, 10, which is smaller and closer than 8 even for
8-bit input. It reaches the single item, the grid tiles and a kept gain map.
`decode` handles PNG/JPEG/WebP/AVIF (EXIF orientation baked into pixels); **HEIC is
not software-decoded** → `Err` (use a hardware/platform decoder). `max_edge`
downscales for **previews only** — `None` keeps full resolution; never downscale a
saved output. `transcode` = `decode → optional downscale → encode`; with
`keep_metadata` it carries EXIF/XMP/ICC. HDR policy (Hayn, 2026-09-28): a
full-resolution AVIF→AVIF convert without `irot`/`imir`/EXIF rotation keeps the
ISO 21496-1 gain map (tmap metadata and its alternate `pixi`/`colr` verbatim,
gain-map image re-encoded; with or without metadata) → `GainMapKept`, verified
by ImageIO in Hayn (IMG-10). Any other target, a resize or a rotation encodes
the SDR base → `GainMapDropped`; a failed keep → `GainMapKeepFailed`. A PQ/HLG
primary is refused with `preservation_required:hdr_transfer_unsupported`: RGBA8
has no tone mapper, and relabelled PQ samples would be a wrong image.

```rust
let out = codec::transcode(src, codec::Target::Webp { quality: 80, lossless: false }, None, true)?;
assert_eq!(out.hdr, codec::HdrOutcome::None); // an SDR source
```

### Streaming JPEG re-encode (`engine::codec::jpeg_stream`, crate-private)

`reencode(src, quality)`: JPEG → JPEG a band of rows at a time (Hayn RUN-01
step 6), so memory follows the compressed size, not the pixels (+66 MB for a
200 MP photo on a Galaxy S25 Edge, against +1.7 GB decoded whole). Decode and
encode are libjpeg-turbo's code (`mozjpeg-sys` in its v6 profile,
`JCP_FASTEST`): Android's `Bitmap.compress` settings, 4:2:0, baseline tables.
The scan is first coded with the standard Huffman tables, one restart interval
per MCU row, then `codec::huffman` re-codes it under optimal tables built by
libjpeg's own algorithm, two passes over the entropy-coded data spread over up
to eight threads. Without restarts the scan is byte for byte what libjpeg's
`optimize_coding` writes (a unit test checks it); with them the pixels are the
same and the file a few bytes per MCU row larger.

Pixels keep the stored orientation, so the EXIF (Orientation included), XMP,
ICC, IPTC and comments are copied as they are; APP0/APP14 are the encoder's.
An MPF gain map stays valid (same geometry): the images after the primary are
appended and the index moved (`metadata::jpeg::relocate_mpf`). Progressive,
multi-scan, CMYK, 12-bit and arithmetic-coded sources are
`DarkError::Unsupported`; any libjpeg warning (corrupt or truncated data) is an
error, not grey rows. libjpeg's fatal errors unwind (`C-unwind`) to a
`catch_unwind` around the session; guards free its state.

### Inspect (`engine::inspect`)

```rust
pub enum Transfer { Unknown, NoHdrSignal, Pq, Hlg }
pub enum Presence { Unknown, Absent, Present }
pub struct Facts { pub transfer: Transfer, pub gain_map: Presence, pub alpha: Presence,
                   pub width: u32, pub height: u32, pub orientation: u8,
                   pub bit_depth: u8 }
pub fn inspect(bytes: &[u8]) -> Facts;
```
JPEG `gain_map`: `hdrgm` or ISO 21496-1 in the primary's segments, or
Apple's map, whose own XMP (`apdi:AuxiliaryImageType`) the MPF index leads to
(Hayn IMG-25); MPF alone stays Unknown.
`bit_depth`: bits per channel as stored — HEIF/AVIF `pixi`, else `av1C`
(high_bitdepth/twelve_bit) or `hvcC` (bitDepthLumaMinus8) of the primary or
of a grid's first tile; PNG `IHDR`; JPEG the `SOF` precision; WebP 8; 0 when
the header does not say. What "match the source" means for a depth choice.
`width`/`height`: the stored size from the header (0 unknown). `orientation`:
the EXIF code (1..=8) that turns the stored pixels upright — `irot`/`imir`
for AVIF/HEIF (via `isobmff::exif_orientation`), the EXIF tag otherwise; 0
when the file names none.
Container scan, no pixel decode. AVIF/HEIC: the PRIMARY item's `colr` nclx (a
grid falls back to its first tile; a `tmap` item's own `colr` is ignored) and
`tmap` or a gain-map `auxC`. PNG: `cICP` before `IDAT`. JPEG: `hdrgm`/Apple
`HDRGainMap` XMP or an ISO 21496-1 APP2; MPF alone is `Unknown`. WebP has no HDR
signalling. `NoHdrSignal`/`Absent` mean no known signal was found, not proof of
SDR; an unreadable container is `Unknown`. `width`/`height` are the stored size
from the header (`codec::header_dimensions`; HEIF/AVIF: the primary item or its
grid canvas), before orientation, 0 when the header does not say.

### Regions for display (`engine::codec::region`)

```rust
pub struct Tile { pub width: u32, pub height: u32, pub rgba: Vec<u8> } // premultiplied
impl AvifRegion {
    pub fn open(bytes: Vec<u8>, cache_dir: &Path) -> Result<AvifRegion>;
    pub fn width(&self) -> u32;   // upright
    pub fn height(&self) -> u32;
    pub fn tiles(&self, rect: [u32; 4], cuts: &[u32], sample: u32) -> Result<Vec<Tile>>;
}
```
An AVIF read a rectangle at a time, for a zoomed view that must not decode the
whole image (Hayn PERF-03). A **grid** decodes only the cells under a request,
in parallel (one decoder thread each), keeping the last 32 MiB of cells. **One
item** is decoded once on `open`, its rows straight into raw RGBA files under
`cache_dir` (full size, then halves down to 256 px), deleted on drop; a tile is
a read from the level its `sample` needs. `tiles` takes an upright rectangle
`[left, top, right, bottom)` and a power-of-two `sample`, and returns it cut at
the upright x positions `cuts`: upright (`irot`/`imir`), alpha merged, in sRGB
(`color::ToSrgb` from the profile), premultiplied. Sampled pixels average the
`sample`×`sample` full-size blocks counted from the stored image's corner (for
a turned or mirrored image a sampled tile sits within one sampled pixel; full
size is exact). `open` refuses PQ/HLG, a profile that is not matrix/TRC,
anything but AVIF, and the decode budget's excess.

### HEIF alpha (`engine::codec::heif_alpha`)

```rust
pub struct AlphaStream { pub hevc: Vec<u8>, pub frames: u32, pub width: u32, pub height: u32 }
pub fn alpha_stream(heif: &[u8]) -> Result<Option<AlphaStream>>;
pub fn attach_alpha(heif: &[u8], base: &[u8], grey: &[u8]) -> Result<Vec<u8>>;
```
For a platform whose HEIF decoder drops the alpha plane (Android, Hayn IMG-15).
DarkLib still decodes no HEVC: `alpha_stream` extracts the primary image's
alpha item(s) as one Annex-B stream, each frame its `hvcC` parameter sets then
its picture, one frame per tile (a single item, an alpha grid, or per-tile alpha
of a colour grid). An outside HEVC decoder turns it into 8-bit full-range grey
(`frames × width × height` bytes). `attach_alpha` pastes the frames onto the
canvas, applies the alpha item's own `irot`/`imir`, un-premultiplies colour for
a `prem` reference, scales the plane to a `base` sampled down for a preview, and
returns `base` with it as an RGBA PNG (fast deflate: an intermediate). A `clap`
crop, tiles of different sizes, or a plane that fits neither size nor shape is
an error, never a guessed plane.

### Verify (`engine::verify`)

```rust
pub enum AlphaKept { Kept, Declared, Lost, Unknown }
pub fn alpha_kept(source: &[u8], output: &[u8]) -> AlphaKept;
```
Checks a conversion's output against its source by decoding pixels, where the
container cannot answer. `alpha_kept` decodes the output (within the decode
budget) and looks for any alpha sample below 255; only when it shows none is the
source decoded, to tell a lost alpha plane (`Lost`) from an opaque one (`Kept`).
A source DarkLib cannot decode (HEIC) answers from its container's alpha
auxiliary. An output it cannot decode answers `Declared` when its container
declares alpha (values unread). A channel whose samples are all 255 is not
transparency: Android's HEIF decoder returns exactly that for a transparent
Apple HEIC (Hayn IMG-15).

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
`strip_metadata` requests keeping orientation and ICC unless `strip_icc` is
true, but orientation is not consistently retained by the current editors. It
throws on unsupported containers. `read_metadata_summary`
powers a "what will be removed" preview and works cross-platform incl. HEIC/AVIF.

### `api::codec`
```rust
enum CodecFormat { Jpeg, Png, Webp, WebpLossless, Avif }
fn transcode(bytes, format: CodecFormat, quality: u32, max_edge: u32,
             keep_metadata: bool, bit_depth: u32) -> Result<Transcoded, String>
```
`max_edge == 0` means keep original size. `bit_depth` 8 or 10 sets an AVIF's
depth; anything else keeps the default, 10. The result carries the bytes and the
`HdrOutcome`. It throws on a container the codec layer can't decode yet (notably
**HEIC** — decode it on the platform side and feed pixels in), and throws
`preservation_required:hdr_transfer_unsupported` for PQ/HLG.

```rust
fn jpeg_reencode(bytes: Vec<u8>, quality: u32) -> Result<Vec<u8>, String>
```
The streaming re-encode above (quality 1..=100). Throws `unsupported:<why>`
(`jpeg_progressive`, `jpeg_multi_scan`, `jpeg_components`, `jpeg_precision`,
`jpeg_coding`) for a source another path should take, `too_large` past the
decode budget, and a plain message for damaged data.

### `api::inspect`

```rust
fn profile_space(bytes) -> Option<ProfileSpace>   // async
pub struct ProfileSpace { pub to_xyz_d50: Vec<f32>, pub transfer: Vec<f32> }
```
The source's colour profile (ICC, or one built from `nclx`/`cICP`) as an RGB
space: the D50 RGB→XYZ matrix, column-major, and `[a, b, c, d, e, f, g]` with
Y = (aX + b)^g + e for X ≥ d, cX + f below (`engine::color::rgb_space`).
`None` without a profile or for a LUT/sampled-curve one.
```rust
fn inspect_image(bytes) -> Facts   // async; see engine::inspect above
```

### `api::region`

```rust
impl RegionReader {                       // opaque; Dart disposes it
    fn open(path: String, cache_dir: String) -> Result<RegionReader, String>  // async
    fn width(&self) -> u32                // sync getter, upright
    fn height(&self) -> u32
    fn tiles(&self, rect: Vec<u32>, cuts: Vec<u32>, sample: u32)
        -> Result<Vec<RegionTile>, String>   // async
}
pub struct RegionTile { pub width: u32, pub height: u32, pub rgba: Vec<u8> }
```
`engine::codec::region` over FFI. `open` reads the file at `path` (deletable
once it returns); the cache files go when the reader is disposed.

### `api::codec` (HEIF alpha)
```rust
fn heif_alpha_stream(bytes) -> Result<Option<AlphaStream>, String>
fn heif_attach_alpha(source, base, grey) -> Result<Vec<u8>, String>
```

### `api::verify`
```rust
fn alpha_kept(source, output) -> AlphaKept   // async; see engine::verify above
```

---

## Current limitations

- **HEIC decode** is hardware-only (no bundled software HEVC) — `decode`/
  `transcode` of a HEIC source returns an error; callers fall back to a platform
  decoder. See [FORMATS.md](FORMATS.md) and [SUPPORT.md](SUPPORT.md).
- **AVIF decode**: 10/12-bit is reduced to 8-bit RGBA (the current SDR contract).
  Orientation (`irot`/`imir`), transparency (the alpha auxiliary item) and
  **ImageGrid (tiled) images** are all handled — grid tiles decode one at a time,
  so peak memory ≈ canvas + one tile.
- **HDR carry through a re-encode**: AVIF→AVIF at full resolution only (see
  above). The writer adds the `tmap` brand, derives each `pixi` from its
  `av1C`, and gives the `altr` group an id outside the item ids. Other targets
  and Apple's HEIC flavour produce the SDR base. A gain map whose base is HDR
  but not signalled by nclx is not detected.
- **Very large images**: AVIF tiles in BOTH directions — grid decode, and grid
  *encode* (opaque images above 16 MP encode tile-by-tile as an ImageGrid at full
  resolution; transparency or other targets use the single-pass path). JPEG/PNG/
  WebP encodes of huge images are still single-pass.
