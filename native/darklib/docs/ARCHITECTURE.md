# Architecture

DarkLib is one crate with two layers: a **portable pure-Rust engine** and a thin
**FFI adapter**. Only the engine is meant for general reuse.

```
src/
├── lib.rs                 crate root: re-exports `engine` and `api`
├── engine/                ← portable core (no FFI, no platform, no I/O)
│   ├── format.rs          container sniffing + FormatDescriptor / ConversionLoss
│   ├── error.rs           DarkError + Result<T> (no panics on malformed input)
│   ├── metadata/
│   │   ├── mod.rs         strip(policy) dispatch + the `Canonical` model
│   │   ├── extract.rs     read EXIF/XMP/ICC/IPTC + unified orientation
│   │   ├── inject.rs      carry metadata back into encoded bytes
│   │   ├── jpeg.rs / png.rs / webp.rs   per-container segment/chunk surgery
│   │   ├── isobmff.rs     AVIF/HEIF box rebuild (strip + inject + extract)
│   │   ├── xmp.rs         XMP property surgery (keep HDR gain-map, drop privacy)
│   │   └── exif.rs        minimal TIFF/EXIF reading (orientation, blocks)
│   ├── color.rs           ICC extract/inject + CICP(nclx) → ICC synthesis
│   └── codec/
│       ├── mod.rs         decode / encode / transcode + the `Target` enum
│       └── avif_dav1d.rs  AVIF → RGBA via rav1d (the pure-Rust dav1d)
└── api/ + frb_generated.rs   FFI adapter for Flutter (flutter_rust_bridge)
```

## Engine principles

**Lossless by default.** `metadata::strip`, `extract` and `inject` never touch
the coded pixels. They rewrite containers: JPEG `APPn`/`COM` segments, PNG
ancillary chunks, WebP `RIFF`/`VP8X` chunks, and ISO-BMFF (`meta`/`iinf`/`iloc`/
`iref`/`iprp`) boxes. A re-encode only happens on the explicit `codec` path.

**The `Canonical` model.** `extract` returns a `Canonical { exif, xmp, icc, iptc,
orientation }` where each blob is kept **verbatim** (no parse→reserialize), so
private MakerNotes and vendor boxes survive a round-trip. `inject` consumes the
same model.

**Verify-or-bail for risky surgery.** ISO-BMFF stores *absolute* file offsets in
`iloc`, so removing or adding an item shifts every other item's offset. Rather
than patch offsets in place (one slip = a corrupt image), the engine **rebuilds**
`mdat` with fresh offsets and then **self-validates**: it re-parses its own
output and byte-compares every kept item (including the primary image) against
the source. Any mismatch — or any structure outside the supported subset —
returns the input *unchanged*. The codec payload (AV1/HEVC) is never modified.

**No silent failure.** Every fallible operation returns `Result<_, DarkError>`;
malformed input yields an error, not a panic and not a corrupted buffer. Callers
are expected to fall back (e.g. to a platform decoder) on `Err`.

**Unified orientation.** On decode, the source's EXIF orientation is baked into
the pixels once (encoders write no orientation tag), eliminating the classic
double-rotate.

## The codec path

`decode → (optional preview downscale) → encode`. Decoders: `image` (PNG/JPEG),
`libwebp` (WebP), `rav1d` (AVIF). Encoders: `image` (PNG/JPEG), `libwebp` (WebP),
`rav1e`/`ravif` (AVIF). HEIC is **not** decoded or encoded in software — see
[FORMATS.md](FORMATS.md).

The single `unsafe` surface is `codec::avif_dav1d`, which drives rav1d's dav1d
C-ABI (`open`/`send_data`/`get_picture`/`close`) using rav1d's own `#[repr(C)]`
types — no hand-mirrored structs — and keeps the entire context/picture lifecycle
inside one function.

> Downscaling exists only for previews (`max_edge`). The saved/transcoded output
> is never downscaled; large-image **tiling** (keep dimensions) is the planned
> answer to very large inputs.

## The FFI boundary

`api/` exposes a small, FRB-friendly surface (`simple`, `metadata`, `codec`) that
converts to/from the engine types and runs heavy work off the Dart isolate.
`frb_generated.rs` is produced by `flutter_rust_bridge_codegen` and is not edited
by hand. None of this is required to use the engine from Rust.

### Planned: a workspace split

For clean standalone reuse the crate should become a Cargo **workspace**:

- `darklib-core` — today's `engine/`, the portable library (the publishable unit,
  no `flutter_rust_bridge` dependency).
- `darklib-frb` — today's `api/` + generated glue, depending on `darklib-core`.

This isn't done yet (it touches the FRB codegen config and the cargokit manifest
path). Until then, depend on the crate and use `darklib::engine::*`; the FFI layer
compiles but is inert for Rust-only consumers.
