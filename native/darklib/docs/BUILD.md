# Building DarkLib

## Prerequisites

- A stable Rust toolchain via `rustup`, **1.88 or newer** (MSRV, verified with the lockfile: `cargo +1.88.0 test --locked`, 2026-09-30).
- For mobile cross-compilation, the relevant targets and helpers:
  ```sh
  rustup target add aarch64-linux-android \
                    aarch64-apple-ios aarch64-apple-ios-sim
  cargo install cargo-ndk
  ```
  (32-bit ARM, `armv7-linux-androideabi`, is intentionally unsupported — see
  [SUPPORT.md](SUPPORT.md).)

## Standalone (host) — the day-to-day loop

```sh
cargo test                                   # unit + golden tests (pure Rust)
cargo clippy --all-targets -- -D warnings
cargo fmt --check
cargo build --release
```

The engine has no system dependencies; `libwebp` and the AV1 codecs build from
source.

**Assembly.** `rav1d` (AV1 decode) builds dav1d's arm64 assembly on every
`aarch64` target (Android, iOS, Apple-silicon hosts), with the C compiler the
target already uses, so no extra tool (Hayn PERF-05: about twice the decode
speed on the phone). Its dotprod/i8mm routines run only where the CPU reports
them. Two consequences:

- `rav1d` comes from its repository at tag `v1.1.0` (`[patch.crates-io]` in
  `Cargo.toml`): the published 1.1.0 lacks `src/arm/asm-offsets.h`, which
  three of its arm64 files include. The Rust and assembly sources are the
  same as the published crate's. The first build fetches it over the network;
  return to crates.io once a release ships the header.
- `build.rs` links the Android library with `-Wl,-Bsymbolic`: the assembly
  addresses rav1d's tables PC-relative, which Android's linker refuses
  against exported symbols (`R_AARCH64_ADR_PREL_PG_HI21`).

x86 builds stay without assembly (nasm's objects do not link into the shared
library, and x86 is only hosts). `rav1e` (AVIF encode) is built without it.

**libjpeg-turbo's code.** `mozjpeg-sys` (streaming JPEG, Hayn RUN-01 step 6)
compiles its vendored C with `cc`, and on `aarch64` its NEON routines (C
intrinsics and GNU assembly) with the same compiler: no nasm, no CMake. It is
used in its libjpeg v6 profile only. x86 builds have no SIMD here either (the
`nasm_simd` feature stays off), so host timings are not the phone's. It needs
`cc` 1.2 or later, which moved `cc` in `Cargo.lock` from 1.0.83 to 1.6.0 for
every C build (libwebp, rav1d's assembly).

## Cross-compiling for Android

```sh
cargo ndk -t arm64-v8a build --release
```

The whole core (AVIF/WebP encode + AVIF decode + all metadata surgery, including
`bitdepth_16` for HDR) is ~4.5 MB for arm64.

## Within the Flutter app (Hayn)

The build is automatic: the vendored **cargokit** Gradle/Xcode glue compiles the
crate for each target during `flutter build`. Nothing extra to run.

- Android: cargokit is patched to build `android-arm64` only, the one ABI in
  the app's `abiFilters` (x86_64 dropped 2026-09-30), so a plain
  `flutter build apk` works and debug builds skip the emulator ABIs.
- A known APK-build flake on macOS (a stale iOS SPM symlink) is cleared with
  `rm -rf ios/Flutter/ephemeral/Packages` before rebuilding.

## FFI bindings (flutter_rust_bridge)

The Dart bindings in the app's `lib/src/rust/` and `src/frb_generated.rs` are
generated. The Dart `flutter_rust_bridge` dependency version **must equal** the
codegen version (**2.12.0**). After changing the `api/` surface, regenerate:

```sh
flutter_rust_bridge_codegen generate
```

`frb_generated.rs` is never hand-edited. Pure-Rust reuse of the `engine` needs
none of this.

## The green gate (per change)

A change is "green" when all of these pass:

```sh
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
cargo ndk -t arm64-v8a build          # cross-compile sanity
# in the app: flutter analyze && flutter build apk --debug
```
