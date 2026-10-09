import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;
import 'package:image/image.dart' as img;

import '../../../core/darklib/darklib.dart';
import '../../../core/diagnostics/media_diagnostics.dart';
import 'image_probe.dart';
import 'native_image_encoder.dart';

// JPEG has no alpha. Choosing JPEG for a transparent image is the user's
// permission to drop it (user decision, 2026-09-29), so the image is composited
// onto white, the usual export convention, before any JPEG engine runs. Doing
// it here keeps every platform on the same picture: the engines would drop the
// channel differently (Rust keeps the hidden colours, Android turns them black).

abstract final class AlphaFlatten {
  /// Opaque, upright PNG of [source] over white; null when nothing decodes it.
  /// [toSdr] asks the iOS bridge for the SDR rendition of an HDR source.
  /// [alpha] is the source's transparency: when it is known present, a
  /// decode that shows none is refused (`alphaLost`), since compositing it
  /// would show the hidden colours instead of white. Android's HEIF decoder
  /// ignores the alpha plane and returns an alpha channel opaque everywhere
  /// (IMG-15), so the decoded values are compared, not the channel.
  static Future<Uint8List?> toOpaquePng(
    Uint8List source, {
    required bool toSdr,
    bool? alpha,
  }) async {
    final readable = await _readable(source, toSdr: toSdr);
    if (readable == null) return null;
    if (alpha == true &&
        !identical(readable, source) &&
        !await ImageProbe.keepsAlpha(
          source: source,
          output: readable,
          backend: MediaBackend.imageEncoder,
          operation: MediaOperation.bake,
        )) {
      return null;
    }
    // DarkLib composites in Rust: seconds faster per 12 MP image than
    // package:image (PERF-01). Dart remains for what DarkLib cannot decode
    // (GIF, BMP, TIFF) and for when the library is unavailable; DarkLib's
    // wrapper records either case (darklib.bake.*).
    final rust = await DarkLibCore.flattenOnWhite(readable);
    if (rust != null) return rust;
    return Isolate.run(() => flattenOnWhite(readable));
  }

  /// Bytes package:image can decode: the source itself, or a PNG from DarkLib
  /// (AVIF), ImageIO (HEIC) or the platform plugin (Android HEIC), in turn.
  static Future<Uint8List?> _readable(
    Uint8List source, {
    required bool toSdr,
  }) async {
    switch (ImageProbe.sniff(source)) {
      case SniffedFormat.png ||
          SniffedFormat.webp ||
          SniffedFormat.gif ||
          SniffedFormat.bmp ||
          SniffedFormat.tiff:
        return source;
      case SniffedFormat.jpeg ||
          SniffedFormat.heic ||
          SniffedFormat.avif ||
          SniffedFormat.unknown:
        break;
    }
    final dark = await DarkLibCore.transcode(
      source,
      format: DarkLibFormat.png,
      quality: 100,
      keepMetadata: false,
    );
    if (dark != null) return dark.bytes;
    final baked = await NativeImageEncoder.bakeUpright(
      source: source,
      keepMetadata: false,
      keepOriginalTime: true,
      toSdr: toSdr,
    );
    if (baked != null) return baked;
    // Not on Android: the plugin decodes an opaque image into RGB_565 there.
    if (NativeImageEncoder.android) return null;
    try {
      final out = await fic.FlutterImageCompress.compressWithList(
        source,
        format: fic.CompressFormat.png,
        minWidth: 1000000,
        minHeight: 1000000,
      );
      return out.isEmpty ? null : out;
    } catch (_) {
      return null; // The caller records the failed flatten.
    }
  }
}

/// Top-level so it runs in `Isolate.run` and in tests. Bakes EXIF orientation,
/// composites over white and returns an opaque 8-bit PNG; null when [bytes]
/// do not decode.
Uint8List? flattenOnWhite(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final upright = img
      .bakeOrientation(decoded)
      .convert(format: img.Format.uint8, numChannels: 4);
  final white = img.Image(
    width: upright.width,
    height: upright.height,
    numChannels: 3,
  )..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(white, upright);
  return img.encodePng(white);
}
