# Supported targets

DarkLib builds on **stable Rust** for every target it supports.

| Platform | Target triple | ABI | Supported |
|---|---|---|:--:|
| Android (phones) | `aarch64-linux-android` | arm64-v8a | ✅ |
| Android (emulator/x86) | `x86_64-linux-android` | x86_64 | ✅ |
| Android (legacy 32-bit) | `armv7-linux-androideabi` | armeabi-v7a | ⛔ |
| iOS device | `aarch64-apple-ios` | — | ✅ |
| iOS simulator | `aarch64-apple-ios-sim`, `x86_64-apple-ios` | — | ✅ |
| Desktop / host | `aarch64-*`, `x86_64-*` | — | ✅ |

**Minimum Supported Rust Version (MSRV): 1.79.**

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

The Flutter app's Android Gradle config sets `abiFilters = arm64-v8a, x86_64`,
and the vendored cargokit is patched to skip `android-arm`, so a plain
`flutter build apk` works. For a fully clean release with no 32-bit slice at all,
build with an explicit platform list:

```sh
flutter build apk --release --target-platform android-arm64,android-x64
```

## If you ever need armv7

It's a deliberate non-goal, but if a downstream consumer must target it, the
options are: build that ABI on a nightly toolchain, or gate the `rav1d` dependency
behind `cfg(not(target_arch = "arm"))` and fall back to a platform decoder for
AVIF on 32-bit ARM. Neither is maintained here.
