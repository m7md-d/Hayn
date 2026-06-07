# Formats, codecs & colour

DarkLib's codec choices are driven by two rules: **patent-clean only**, and **no
avoidable quality loss**.

## Royalty-free stance

Software encoders/decoders bundled in the binary must be free of active patent
royalties:

- **AV1 / AVIF** — decode `rav1d`, encode `rav1e` (both pure Rust, BSD-2). AV1 is
  royalty-free by design.
- **WebP** (VP8/VP8L) — `libwebp` (BSD).
- **JPEG, PNG** — via the `image` crate (+ `miniz_oxide` for PNG `iCCP`).

**HEVC is deliberately excluded.** HEIC/HEIF images are HEVC-coded, and HEVC
carries active patents in many jurisdictions. DarkLib therefore **never bundles a
software HEVC codec**. It still does full *lossless container surgery* on HEIC
(strip/extract/inject), but **decoding** a HEIC to pixels is delegated to the
platform's hardware decoder (MediaCodec / VideoToolbox), where the OS vendor
licenses the patents. There is no software HEIC encode.

No x264/x265 is ever linked.

## Conversion decision tree

When choosing an output container for "make this smaller / more modern", prefer in
order, gated by what the target environment can actually do:

```
AVIF  →  HEIC  →  WebP / JPEG
(AV1)    (HEVC,    (royalty-free,
         HW only)   universal)
```

- **AVIF** first: best ratio, royalty-free, software path available everywhere.
- **HEIC** only where hardware encode exists *and* the platform is licensed
  (DarkLib won't produce it in software).
- **WebP** as the universal royalty-free fallback; **JPEG** for maximum
  compatibility / when alpha and HDR aren't needed.

The exact policy lives with the embedding app; DarkLib provides the primitives
and the capability data to drive it.

## Capability matrix

`FormatDescriptor::of(fmt)` reports per-format support; `loss_to(target)` predicts
what a conversion drops, so a UI can warn instead of silently losing data.

| Format | EXIF | XMP | ICC | IPTC | Alpha | Lossless meta-ops | HDR-capable |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| JPEG | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | ✅ (Ultra-HDR gain map) |
| PNG  | ✅ | ✅ | ✅ | ⛔ | ✅ | ✅ | ⛔ |
| WebP | ✅ | ✅ | ✅ | ⛔ | ✅ | ✅ | ⛔ |
| AVIF | ✅ | ✅ | ✅ | ⛔ | ✅ | ✅ | ✅ |
| HEIC | ✅ | ✅ | ✅ | ⛔ | ✅ | ✅ | ✅ |
| TIFF | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ⛔ |
| GIF  | ⛔ | ✅ | ⛔ | ⛔ | ✅ | ⛔ | ⛔ |

## Colour management

- ICC profiles are carried **verbatim** through strip/inject (PNG stores them
  zlib-compressed as `iCCP`; JPEG/WebP/ISO-BMFF store them raw — the engine
  normalises to a raw profile internally).
- A profile-less AVIF/HEIF that carries only **`nclx`** CICP code points (e.g. an
  iPhone Display-P3 HEIC) gets an ICC profile **synthesised** from those code
  points: primaries → chromaticities → RGB→XYZ matrix → Bradford D50 adaptation →
  colorants, with an sRGB-style parametric TRC. This preserves the gamut on
  convert without bundling any profile files. Correctness is pinned by a test
  asserting the synthesised sRGB colorants match the published constants.

## HDR gain maps

HDR gain maps are first-class and must never be silently dropped:

- **ISO-BMFF (AVIF/HEIF):** the gain map is a separate auxiliary/derived item
  (ISO 21496-1 `tmap`, or an Apple `auxC` gain-map URN). A privacy strip removes
  only the EXIF/XMP victim items, so the gain map survives **by construction**.
- **Ultra-HDR JPEG:** the gain-map parameters and the locating GContainer live in
  XMP. A naïve strip would drop the whole XMP and silently downgrade the image to
  SDR, so DarkLib does **XMP property surgery** — it keeps a strict allow-list
  (`hdrgm` / `Container` / `Item` + RDF scaffolding) and drops every other
  property *and* its namespace. The MPF index (APP2) that points at the gain map
  is preserved.

Carrying a gain map through a *re-encode* (true convert) needs the gain-map
pixels and is tracked alongside hardware decode.
