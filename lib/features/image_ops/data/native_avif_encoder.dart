import 'package:flutter/services.dart';

import '../../../core/diagnostics/media_diagnostics.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NativeAvifEncoder — bridge to the device's HARDWARE AV1 encoder (Android
// MediaCodec `video/av01`) which produces a real .avif. This is the royalty-free
// + hardware path (CLAUDE.md §5); it replaces the slow software libaom
// (flutter_avif) on capable devices.
//
// Returns null whenever hardware isn't available or anything fails (iOS, older
// SoCs, an unexpected stream) so the caller transparently falls back to the
// software encoder. Correct preservation still requires output verification.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class NativeAvifEncoder {
  static const MethodChannel _channel = MethodChannel('hayn/avif');

  /// Whether a hardware AV1 encoder exists on this device. Cached after the
  /// first probe (it never changes for a given device).
  static bool? _available;

  static Future<bool> isAvailable() async {
    final cached = _available;
    if (cached != null) return cached;
    try {
      final ok = await _channel.invokeMethod<bool>('isAvailable') ?? false;
      _available = ok;
      return ok;
    } on MissingPluginException {
      _available = false;
      return false;
    } catch (_) {
      MediaDiagnostics.record(
        MediaBackend.androidAvif,
        MediaOperation.probe,
        MediaDiagnosticCode.exception,
      );
      // A transient probe error must not disable hardware for this process.
      return false;
    }
  }

  /// Encode [source] image bytes to AVIF via hardware at [quality] (0–100).
  /// Returns the .avif bytes, or null to signal "fall back to software".
  static Future<Uint8List?> encode({
    required Uint8List source,
    required int quality,
  }) async {
    if (!await isAvailable()) {
      MediaDiagnostics.record(
        MediaBackend.androidAvif,
        MediaOperation.encode,
        MediaDiagnosticCode.unavailable,
      );
      return null;
    }
    try {
      final res = await _channel.invokeMethod<Uint8List>('encode', {
        'bytes': source,
        'quality': quality.clamp(0, 100),
      });
      if (res == null || res.isEmpty) {
        MediaDiagnostics.record(
          MediaBackend.androidAvif,
          MediaOperation.encode,
          MediaDiagnosticCode.emptyOutput,
        );
        return null;
      }
      return res;
    } on MissingPluginException {
      MediaDiagnostics.record(
        MediaBackend.androidAvif,
        MediaOperation.encode,
        MediaDiagnosticCode.unavailable,
      );
      return null;
    } catch (_) {
      MediaDiagnostics.record(
        MediaBackend.androidAvif,
        MediaOperation.encode,
        MediaDiagnosticCode.exception,
      );
      return null;
    }
  }
}
