# Building DarkLib

## Prerequisites

- A stable Rust toolchain (MSRV **1.79**) via `rustup`.
- For mobile cross-compilation, the relevant targets and helpers:
  ```sh
  rustup target add aarch64-linux-android x86_64-linux-android \
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
source. Assembly is **off** for the AV1 codecs (`rav1e` and `rav1d`), which keeps
cross-compilation trivial (no `nasm`/`meson`) at a modest speed cost — re-enable
it later behind a feature once the asm toolchain is wired into CI.

## Cross-compiling for Android

```sh
cargo ndk -t arm64-v8a -t x86_64 build --release
```

The whole core (AVIF/WebP encode + AVIF decode + all metadata surgery, including
`bitdepth_16` for HDR) is ~4.5 MB for arm64.

## Within the Flutter app (Hayn)

The build is automatic: the vendored **cargokit** Gradle/Xcode glue compiles the
crate for each target during `flutter build`. Nothing extra to run.

- Android: cargokit is patched to skip `android-arm`, so a plain
  `flutter build apk` works; `abiFilters` keeps the package to arm64 + x86_64.
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
