# Supported targets

> Status reviewed 2026-09-26: this describes the experimental implementation, not a preservation guarantee. The [bounded contract](../../../docs/10-DARKLIB.md) and [known defects](../../../docs/12-STABILIZATION.md) take precedence over older completion claims.

DarkLib builds on **stable Rust** for every target it supports.

| Platform | Target triple | ABI | Supported |
|---|---|---|:--:|
| Android (phones) | `aarch64-linux-android` | arm64-v8a | ✅ |
| Android (emulator/x86) | `x86_64-linux-android` | x86_64 | builds, not shipped since 2026-09-30 |
| Android (legacy 32-bit) | `armv7-linux-androideabi` | armeabi-v7a | ⛔ |
| iOS device | `aarch64-apple-ios` | — | ✅ |
| iOS simulator | `aarch64-apple-ios-sim`, `x86_64-apple-ios` | — | ✅ |
| Desktop / host | `aarch64-*`, `x86_64-*` | — | ✅ |

**MSRV: Rust 1.88.** Set by locked `image 0.25.10` (the highest `rust-version` among the dependencies) and verified on 2026-09-30: `cargo +1.88.0 check --locked --all-targets` and `cargo +1.88.0 test --locked` pass. Raise it only with a lockfile change that needs it, and re-verify.

## Why no 32-bit ARM (`armeabi-v7a`)

The AVIF decoder, [`rav1d`](https://crates.io/crates/rav1d), gates an unstable
feature on 32-bit ARM only:

```rust
#![cfg_attr(target_arch = "arm", feature(stdarch_arm_feature_detection))]
```

`arm` here is **32-bit** ARM. On that target rav1d uses `core::arch` NEON
intrinsics whose runtime feature detection is still nightly-only, so the crate
needs a nightly toolchain there. On `aarch64` (64-bit ARM) the equivalent NEON
support is stable — which is why arm64, x86_64 and iOS all build fine on stable.

We don't ship 32-bit ARM:

- 32-bit-only Android devices are effectively extinct — Google Play has required
  64-bit since August 2019.
- Pinning the whole project to nightly to serve a vanishing ABI isn't worth the
  fragility, and `RUSTC_BOOTSTRAP` hacks aren't appropriate for a shipped binary.

So `armeabi-v7a` is **unsupported**. The codebase still *compiles* for it only
under nightly; on stable it will fail with `error[E0554]`.

## Building without armv7

The Flutter app's Android Gradle config sets `abiFilters = arm64-v8a` (x86_64
served only PC emulators and a few Chromebooks; dropped by user decision on
2026-09-30), and the vendored cargokit builds `android-arm64` only, so a plain
`flutter build apk` works and packages one ABI.

## If you ever need armv7

It's a deliberate non-goal, but if a downstream consumer must target it, the
options are: build that ABI on a nightly toolchain, or gate the `rav1d` dependency
behind `cfg(not(target_arch = "arm"))` and fall back to a platform decoder for
AVIF on 32-bit ARM. Neither is maintained here.

## Packaging caveat (2026-09-26)

Supported DarkLib targets and APK contents are different questions. With a
single ABI, `--split-per-abi` adds nothing (and conflicts with
`ndk.abiFilters`); build the universal APK. See the
[measured build results](../../../docs/12-STABILIZATION.md) before treating the
table above as a guarantee about packaged slices.
