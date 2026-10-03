# DarkLib

> Status reviewed 2026-09-26: this describes the experimental implementation, not a preservation guarantee. The [bounded contract](../../docs/10-DARKLIB.md) and [known defects](../../docs/12-STABILIZATION.md) take precedence over older completion claims.

**An offline, royalty-free image core in Rust** — lossless metadata surgery,
colour management, and modern-codec decode/encode behind one small engine.

DarkLib was extracted from the [Hayn](https://github.com/m7md-d/Hayn) offline
media app and is being developed as a standalone, reusable library. Everything
runs **on-device**: no network, no telemetry. Codecs are **patent-clean** (AV1,
WebP, JPEG, PNG); patent-encumbered formats are never software-encoded.

> Status: **pre-1.0, evolving.** The engine API is not yet stable. See
> [CHANGELOG](CHANGELOG.md) and the [roadmap](#roadmap).

---

## Why DarkLib

- **Lossless metadata, never a re-encode.** Stripping or carrying EXIF/XMP/ICC is
  done by *container surgery* — rewriting boxes/segments/chunks — so the coded
  pixels are byte-identical. No generational quality loss.
- **Safety over speed.** The risky path (ISO-BMFF box rebuilds for AVIF/HEIF)
  **self-validates**: it re-parses its own output and byte-compares every kept
  item; on any mismatch it returns the input *untouched*. It corrupts nothing.
- **Royalty-free by construction.** AV1/AVIF (decode via `rav1d`, encode via
  `rav1e`), WebP (`libwebp`), JPEG, PNG. No x264/x265, no software HEVC.
- **Never downscale the saved output.** Downscaling is opt-in for *previews*
  only; full-resolution work is the rule. Huge images encode as a tiled AVIF
  ImageGrid (and tiled images decode), so even 200 MP stays full-resolution with
  bounded memory.
- **Capability-aware.** A per-format descriptor drives "what a conversion will
  lose" so callers can warn instead of silently dropping data.

## Architecture at a glance

```
darklib (crate)
├── engine/            ← the portable, pure-Rust core (no FFI, no platform)
│   ├── format         · container sniffing + per-format capability descriptor
│   ├── metadata       · strip / extract / inject (JPEG·PNG·WebP·AVIF·HEIF)
│   │                    + isobmff, xmp, exif helpers (lossless surgery)
│   ├── color          · ICC extract/inject + CICP(nclx)→ICC synthesis
│   ├── codec          · decode / encode / transcode (+ avif_dav1d, region)
│   └── error          · Result<T, DarkError> — no panics on bad input
└── api/ + frb_generated   ← thin FFI adapter for Flutter (flutter_rust_bridge)
```

Reusing DarkLib in a **Rust** project? Depend on the crate and use
`darklib::engine::*` directly — `api`/`frb_generated` are only the Flutter
binding. (A future workspace split into `darklib-core` + `darklib-frb` is on the
roadmap; see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).)

## Capabilities

| Format | Detect | Strip (lossless) | Extract | Inject / carry | Decode | Encode |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| JPEG | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| PNG  | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| WebP | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| AVIF | ✅ | ✅ | ✅ | ✅ | ✅ (rav1d) | ✅ (rav1e) |
| HEIC/HEIF | ✅ | ✅ | ✅ | ✅ | ⛔ HW-only¹ | ⛔¹ |
| GIF / BMP / TIFF | ✅ | — | — | — | partial² | — |

¹ HEVC carries active patents, so DarkLib never bundles a software HEVC
codec (see [docs/FORMATS.md](docs/FORMATS.md)); HEIC decode is delegated to the
platform's hardware decoder. ² via the `image` crate where applicable.

Colour and HDR handling are experimental. ICC carry and CICP synthesis exist,
but the RGBA8 pipeline does not preserve general PQ/HLG precision; strip has
known orientation and Ultra-HDR JPEG MPF defects. A format checkmark above
means an API path exists, not that all image properties are preserved. See the
[stabilization plan](../../docs/12-STABILIZATION.md) and
[HDR research](../../docs/11-HDR-RESEARCH.md).

## Supported targets

`aarch64` (Android arm64-v8a, iOS, Apple Silicon), `x86_64` (Android, desktop),
and the iOS simulator. **32-bit ARM (`armeabi-v7a`) is not supported** — the
`rav1d` decoder needs nightly Rust there. Details + rationale:
[docs/SUPPORT.md](docs/SUPPORT.md).

## Quick start (Rust engine)

```rust
use darklib::engine::{metadata, codec, format};

// 1. Sniff the container.
let fmt = format::detect(bytes);                 // ImageFormat::Avif, …

// 2. Request metadata stripping (known orientation/HDR gaps: see status).
let clean = metadata::strip(bytes, metadata::StripPolicy::default())?;

// 3. Extract the canonical metadata model (raw EXIF/XMP/ICC + orientation).
let meta = metadata::extract(bytes);

// 4. Transcode AVIF/JPEG/PNG/WebP → WebP, carrying the metadata across.
let webp = codec::transcode(bytes, codec::Target::Webp { quality: 80, lossless: false }, None)?;
let out  = metadata::inject(&webp, &meta);       // re-attach EXIF/XMP/ICC

// 5. Predict conversion loss for a capability-aware UI.
let loss = format::FormatDescriptor::of(fmt).loss_to(format::ImageFormat::Jpeg);
if loss.alpha { /* warn: JPEG can't hold transparency */ }
```

`strip`/`extract`/`inject` are pure container surgery (no re-encode);
`decode`/`encode`/`transcode` are the pixel path.

## Building

```sh
cargo test           # 60+ unit/golden tests, all pure-Rust
cargo clippy --all-targets -- -D warnings
cargo fmt --check
```

Cross-compiling for mobile, FFI/codegen, and the AV1 assembly setup are in
[docs/BUILD.md](docs/BUILD.md).

## Stabilization

The former stage checklist described implementation progress, not independent
conformance. Current gates cover result/error semantics, preservation defects,
backend evaluation, and device/resource tests. Follow the
[bounded contract](../../docs/10-DARKLIB.md) and
[stabilization plan](../../docs/12-STABILIZATION.md); do not mark the engine
complete solely because its internal round-trip tests pass.

## License

GNU General Public License, version 3 (`GPL-3.0-only`), the same licence as
Hayn. Full text in [LICENSE](LICENSE).

## Documentation

- [docs/API.md](docs/API.md) — full public API reference (Rust engine + Dart/FFI) with examples; `cargo doc --open` for the generated rustdoc
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — engine layers, the FFI boundary, the self-validate model
- [docs/FORMATS.md](docs/FORMATS.md) — format decision tree, royalty-free stance, colour/HDR
- [docs/SUPPORT.md](docs/SUPPORT.md) — targets, MSRV, the no-armv7 rationale
- [docs/BUILD.md](docs/BUILD.md) — build, cross-compile, FFI codegen
- [CONTRIBUTING.md](CONTRIBUTING.md) — conventions and the green gate
