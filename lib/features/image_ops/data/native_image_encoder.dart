import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NativeImageEncoder — encodes to HEIC/JPEG via the platform's own ImageIO
// pipeline (iOS), instead of flutter_image_compress. Why we own this step:
//
//   • No "opaque image with AlphaLast" warnings: we decode straight to the
//     source's (opaque) CGImage and hand THAT to CGImageDestination, so there's
//     no spurious alpha channel for ImageIO to complain about and drop.
//   • Real camera EXIF survives: when keepMetadata is set we copy the source's
//     full property set (Exif/TIFF/GPS + colour profile) into the output — which
//     flutter_image_compress only does for JPEG. Display orientation is always
//     carried so the photo never comes out rotated.
//
// Returns null when there's no native impl (Android/desktop today), the format
// isn't writable on this OS (e.g. a device with no HEVC encoder), or anything
// fails — the caller then falls back to the plugin encoder. Never throws.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class NativeImageEncoder {
  // Shares the lossless-strip channel; the native side multiplexes by method.
  static const MethodChannel channel = MethodChannel('hayn/metadata');

  /// Encode [source] to [format] ('heic' | 'jpeg' | 'png') at [quality] (0–100).
  /// The native side copies the whole source property set then removes only what
  /// the flags drop: [keepMetadata] governs camera/GPS + the HDR gain map;
  /// [keepOriginalTime] (independent) governs the in-file capture date. [bitDepth]
  /// 0 = match the source, 8 = re-encode the base at 8-bit (colour precision
  /// only — HDR is kept regardless).
  static Future<Uint8List?> encode({
    required Uint8List source,
    required String format,
    required int quality,
    required bool keepMetadata,
    bool keepOriginalTime = true,
    int bitDepth = 0,
  }) async {
    try {
      final res = await channel.invokeMethod<Uint8List>('encodeImage', {
        'bytes': source,
        'format': format,
        'quality': quality,
        'keepMetadata': keepMetadata,
        'keepOriginalTime': keepOriginalTime,
        'bitDepth': bitDepth,
      });
      return (res != null && res.isNotEmpty) ? res : null;
    } catch (_) {
      return null;
    }
  }

  /// Bake the EXIF orientation INTO the pixels → a LOSSLESS PNG with corrected
  /// metadata (orientation = 1; date per [keepOriginalTime]; camera/GPS per
  /// [keepMetadata]). Used for AVIF (flutter_avif mishandles orientation/date)
  /// and PNG output (PNG viewers ignore EXIF orientation). Lossless — no quality
  /// loss. Returns null off-iOS / on failure (caller falls back).
  static Future<Uint8List?> bakeUpright({
    required Uint8List source,
    required bool keepMetadata,
    required bool keepOriginalTime,
  }) async {
    try {
      final res = await channel.invokeMethod<Uint8List>('bakeUpright', {
        'bytes': source,
        'keepMetadata': keepMetadata,
        'keepOriginalTime': keepOriginalTime,
      });
      return (res != null && res.isNotEmpty) ? res : null;
    } catch (_) {
      return null;
    }
  }
}
