import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NativeAvifEncoder — bridge to the device's HARDWARE AV1 encoder (Android
// MediaCodec `video/av01`) which produces a real .avif. This is the royalty-free
// + hardware path (CLAUDE.md §5); it replaces the slow software libaom
// (flutter_avif) on capable devices.
//
// Returns null whenever hardware isn't available or anything fails (iOS, older
// SoCs, an unexpected stream) so the caller transparently falls back to the
// software encoder — output can never regress.
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
    } catch (_) {
      _available = false;
      return false;
    }
  }

  /// Encode [source] image bytes to AVIF via hardware at [quality] (0–100).
  /// Returns the .avif bytes, or null to signal "fall back to software".
  static Future<Uint8List?> encode({
    required Uint8List source,
    required int quality,
  }) async {
    if (!await isAvailable()) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('encode', {
        'bytes': source,
        'quality': quality.clamp(0, 100),
      });
    } catch (_) {
      return null;
    }
  }
}
