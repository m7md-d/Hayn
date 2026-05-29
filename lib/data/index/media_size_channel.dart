import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MediaSizeChannel — Dart side of the cheap native byte-size lookup.
//
// `AssetEntity.file` materialises (and on iOS exports a copy of) the whole
// origin file just to read its length — ruinous across a 10k library. The
// platform already knows the size without touching the bytes:
//   • Android → MediaStore's `_size` column
//   • iOS     → PHAssetResource.fileSize
// This channel asks for a *batch* of sizes in one round-trip.
//
// Contract: it never throws. Any id the platform can't resolve (or the whole
// batch, if the channel isn't wired — desktop, tests, an old build) is simply
// omitted. Callers treat a missing id as "fall back to the slow path", so no
// platform special-casing leaks upward.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class MediaSizeChannel {
  static const MethodChannel channel = MethodChannel('hayn/media_size');

  /// Returns `id → byteSize` for the ids the platform could resolve cheaply.
  static Future<Map<String, int>> getSizes(List<String> ids) async {
    if (ids.isEmpty) return const {};
    try {
      final result = await channel.invokeMapMethod<String, Object?>(
        'getSizes',
        {'ids': ids},
      );
      if (result == null) return const {};
      final out = <String, int>{};
      result.forEach((id, value) {
        final bytes = value is int
            ? value
            : (value is num ? value.toInt() : null);
        if (bytes != null && bytes >= 0) out[id] = bytes;
      });
      return out;
    } on MissingPluginException {
      return const {}; // native side not present on this platform/build
    } catch (_) {
      return const {}; // any platform error → let the caller fall back
    }
  }
}
