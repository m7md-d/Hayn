# Contributing to DarkLib

DarkLib touches users' irreplaceable photos, so correctness and safety come
before speed or cleverness.

## The green gate

Every change must pass, with no warnings:

```sh
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
```

Cross-compile sanity (`cargo ndk -t arm64-v8a build`) and, when embedded,
`flutter analyze` + `flutter build apk --debug` are part of the bar too. See
[docs/BUILD.md](docs/BUILD.md).

## Conventions

- **No panics on input.** Fallible work returns `Result<_, DarkError>`. Malformed
  data yields an error, never a panic and never a corrupted buffer. Don't
  `unwrap()` on parsed input.
- **Lossless means lossless.** Metadata operations (`strip`/`extract`/`inject`)
  must not re-encode pixels. If you can't do it as container surgery, it doesn't
  belong on that path.
- **Verify-or-bail for container rebuilds.** Anything that rewrites ISO-BMFF
  offsets must self-validate (re-parse + byte-compare kept items) and return the
  input unchanged on any mismatch. Never ship a "probably fine" rebuild.
- **Royalty-free codecs only.** No patent-encumbered software codecs (no x264/
  x265/HEVC). See [docs/FORMATS.md](docs/FORMATS.md).
- **Contain `unsafe`.** FFI/`unsafe` lifecycles stay in one module with a
  `// SAFETY:` rationale; the safe API around them must be misuse-proof.
- **Test on real, awkward files.** HEIC from iPhones, HDR, transparency, odd
  dimensions, profile-less `nclx` images. Add a golden test with each feature.
- **Comments in English**, matching the existing code.
- **Stable Rust only** (MSRV 1.79). Don't introduce nightly requirements; that's
  exactly why 32-bit ARM is unsupported.

## Adding a format or codec

The engine is built to extend: add detection in `engine::format`, a capability
row to `FormatDescriptor`, metadata surgery under `engine::metadata`, and a
`codec::Target`/decode arm as needed — each behind the same interfaces, with
tests. Keep the pure `engine` free of FFI and platform assumptions.
