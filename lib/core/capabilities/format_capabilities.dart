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
        // FALSE on purpose ("اكشف لا تفترض"): our AVIF encoder (flutter_avif)
        // is SOFTWARE libaom — it never touches the device's AV1 hardware even
        // on A17 Pro/iPhone 16. Claiming hardware made `auto` route every photo
        // (and every crop) to a slow software AVIF encode. With this false,
        // auto → HEIC (hardware HEVC, fast, correctly oriented), and AVIF stays
        // a deliberate, software-warned choice in the picker.
        supportsAvifHardware: false,
        supportsWebp: true,
      );
    }
    if (Platform.isAndroid) {
      // Android 9 (API 28)+ writes HEIF via HeifWriter (hardware HEVC).
      // AVIF is left FALSE for the same reason as iOS: our encoder is software
      // libaom, not the SoC's AV1 block, so auto should prefer the fast
      // hardware HEIF path and treat AVIF as a deliberate, slower choice.
      return const FormatCapabilities(
        supportsHeic: false,
        supportsHeif: true,
        supportsAvifHardware: false,
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
