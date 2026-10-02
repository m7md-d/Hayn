import 'package:flutter/foundation.dart';

import '../../../core/diagnostics/media_diagnostics.dart';
import 'image_probe.dart';
import 'native_image_encoder.dart';

// Flutter hands AVIF and HEIC to Android's ImageDecoder and reads a 10-bit
// result as if it were 8-bit, so those images come back with scrambled colours
// (IMG-13). On Android they go through the platform bridge instead, which
// returns an 8-bit sRGB PNG. Other formats and platforms are decoded by
// Flutter correctly and pass through unchanged.

abstract final class PlatformPixels {
  /// True when Flutter must not decode [bytes] itself on this platform.
  static bool needsBridge(Uint8List bytes) =>
      NativeImageEncoder.bakeBackend == MediaBackend.androidDecoder &&
      switch (ImageProbe.sniff(bytes)) {
        SniffedFormat.avif || SniffedFormat.heic => true,
        _ => false,
      };

  /// Bytes Flutter shows with correct colours. [maxEdge] bounds the bridge's
  /// decode for previews. If the bridge fails the original is returned, and
  /// the failure is already in the diagnostics.
  static Future<Uint8List> forDisplay(
    Uint8List bytes, {
    required int maxEdge,
  }) async {
    if (!needsBridge(bytes)) return bytes;
    final png = await NativeImageEncoder.bakeUpright(
      source: bytes,
      keepMetadata: false,
      keepOriginalTime: true,
      maxEdge: maxEdge,
      colours: BakeColours.srgb, // Flutter shows the pixels as sRGB
    );
    return png ?? bytes;
  }
}
