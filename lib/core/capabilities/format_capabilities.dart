import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FormatCapabilities — per-device support map for media output formats.
// The list is "what the device can ENCODE" (decoding is broader since
// software decoders can fill any gap).
//
// Real probing happens through platform channels in the implementation
// phase (e.g. MediaCodecInfo on Android, kVTProfileLevel_HEVC_* on iOS).
// The defaults here are conservative platform heuristics so the picker
// behaves sensibly out of the box.
// ─────────────────────────────────────────────────────────────────────────────

class FormatCapabilities {
  const FormatCapabilities({
    required this.supportsHeic,
    required this.supportsHeif,
    required this.supportsAvifHardware,
    required this.supportsWebp,
  });

  /// Apple-style HEIF/HEVC. Avoided on app stores when not licensed.
  final bool supportsHeic;

  /// Generic HEIF (less common). When [supportsHeic] is true, we show "HEIC"
  /// (the recognised name); HEIF alone surfaces only when its sibling isn't
  /// available.
  final bool supportsHeif;

  /// AVIF hardware decode/encode. AV1/AVIF is royalty-free so we always
  /// expose the option — but flag a warning if it's software-only.
  final bool supportsAvifHardware;

  final bool supportsWebp;

  /// Conservative defaults based on platform. Production replaces this with
  /// a real native probe.
  ///
  /// HEIC and HEIF are mutually exclusive in the picker — HEIC is the Apple
  /// label, HEIF the generic one. iOS shows HEIC, Android (and others) HEIF.
  factory FormatCapabilities.detect() {
    if (Platform.isIOS) {
      return const FormatCapabilities(
        supportsHeic: true,
        supportsHeif: false,
        // iPhone 15 Pro / 15 Pro Max (A17 Pro) and every iPhone 16+ ship with
        // hardware AV1 decode/encode. We default to true and let the real
        // platform probe (Phase 2+) downgrade older models if needed.
        supportsAvifHardware: true,
        supportsWebp: true,
      );
    }
    if (Platform.isAndroid) {
      // Android 9 (API 28)+ writes HEIF via HeifWriter.
      // Modern Snapdragon/Exynos SoCs (2023+) ship with AVIF hardware
      // acceleration; we assume it's there unless a real probe says
      // otherwise. Reasonable default for the post-S22/Pixel-7 generation.
      return const FormatCapabilities(
        supportsHeic: false,
        supportsHeif: true,
        supportsAvifHardware: true,
        supportsWebp: true,
      );
    }
    return const FormatCapabilities(
      supportsHeic: false,
      supportsHeif: false,
      supportsAvifHardware: false,
      supportsWebp: true,
    );
  }
}

final formatCapabilitiesProvider =
    Provider<FormatCapabilities>((ref) => FormatCapabilities.detect());
