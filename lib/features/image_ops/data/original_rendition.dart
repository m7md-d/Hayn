import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Rect;

import 'platform_pixels.dart';
import 'region_image.dart';

// A display rendition made from the original itself, for where the library
// gives no thumbnail (UI-10: iOS Photos makes none for a 10-bit AVIF, which is
// DarkLib's default depth and stays so by the user's decision). Screens must
// show whatever the library holds, so they fall back to this.

abstract final class OriginalRendition {
  /// [original] as PNG bytes Flutter shows, the long edge from [maxEdge] to
  /// twice it (or the image's own, if smaller): the whole image sampled from its region reader (AVIF on every
  /// platform, the rest on Android; upright, sRGB), else the display bridge
  /// ([PlatformPixels]). Null when nothing reads it.
  static Future<Uint8List?> png(
    Uint8List original, {
    required int maxEdge,
  }) async {
    final region = await RegionImage.open(original);
    if (region == null) {
      final shown = await PlatformPixels.forDisplay(original, maxEdge: maxEdge);
      return shown.isEmpty ? null : shown;
    }
    try {
      final image = await region.tile(
        Rect.fromLTWH(0, 0, region.width.toDouble(), region.height.toDouble()),
        sampleFor(region.width, region.height, maxEdge),
      );
      if (image == null) return null;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      await region.close();
    }
  }

  /// The power of two that brings the long edge to at least [maxEdge].
  static int sampleFor(int width, int height, int maxEdge) {
    final longEdge = math.max(width, height);
    var sample = 1;
    while (longEdge ~/ (sample * 2) >= maxEdge) {
      sample *= 2;
    }
    return sample;
  }
}
