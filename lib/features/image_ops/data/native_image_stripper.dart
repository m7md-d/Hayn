import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NativeImageStripper — bridge to the platform's lossless metadata strip
// (iOS: ImageIO / CGImageDestination, which copies the coded image WITHOUT
// re-encoding and only drops the metadata dicts). Used for HEIC/AVIF, which
// pure-Dart can't edit losslessly.
//
// Returns the stripped bytes (same container, same pixels) or NULL when the
// platform has no implementation (Android/desktop today) or anything fails —
// the caller then skips the file rather than degrading it. Never throws.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class NativeImageStripper {
  static const MethodChannel channel = MethodChannel('hayn/metadata');

  /// True only where a native implementation exists. iOS ships one; elsewhere
  /// the channel isn't registered and [strip] returns null.
  static Future<Uint8List?> strip(Uint8List bytes) async {
    try {
      final out = await channel.invokeMethod<Uint8List>(
        'stripLossless',
        <String, dynamic>{'bytes': bytes},
      );
      if (out == null || out.isEmpty) return null;
      return out;
    } catch (_) {
      // MissingPluginException (no native side) or a platform error → skip.
      return null;
    }
  }
}
