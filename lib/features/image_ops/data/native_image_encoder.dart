import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/darklib/darklib.dart';
import '../../../core/diagnostics/media_diagnostics.dart';
import 'heif_alpha.dart';

// ImageIO platform adapter. Absent plugins, failed calls and empty results
// remain distinguishable in release diagnostics. Null permits fallback.
// Preservation needs independent validation; copying properties alone is not
// proof of unchanged orientation, colour or HDR (docs/12-STABILIZATION.md).

abstract final class NativeImageEncoder {
  // Shares the lossless-strip channel; the native side multiplexes by method.
  static const MethodChannel channel = MethodChannel('hayn/metadata');

  /// Encode [source] to [format] ('heic' | 'jpeg' | 'png') at [quality] (0–100).
  /// Flags request metadata, capture time and bit depth from the native code.
  /// Their semantic preservation is not guaranteed by this adapter. [toSdr]
  /// decodes an SDR rendition (ImageIO tone mapping, iOS 17+) and never
  /// copies a gain map.
  static Future<Uint8List?> encode({
    required Uint8List source,
    required String format,
    required int quality,
    required bool keepMetadata,
    bool keepOriginalTime = true,
    int bitDepth = 0,
    bool toSdr = false,
  }) async {
    try {
      final res = await channel.invokeMethod<Uint8List>('encodeImage', {
        'bytes': source,
        'format': format,
        'quality': quality,
        'keepMetadata': keepMetadata,
        'keepOriginalTime': keepOriginalTime,
        'bitDepth': bitDepth,
        'toSdr': toSdr,
      });
      if (res == null || res.isEmpty) {
        MediaDiagnostics.record(
          MediaBackend.imageIO,
          MediaOperation.encode,
          MediaDiagnosticCode.emptyOutput,
        );
        return null;
      }
      return res;
    } on MissingPluginException {
      MediaDiagnostics.record(
        MediaBackend.imageIO,
        MediaOperation.encode,
        MediaDiagnosticCode.unavailable,
      );
      return null;
    } catch (_) {
      MediaDiagnostics.record(
        MediaBackend.imageIO,
        MediaOperation.encode,
        MediaDiagnosticCode.exception,
      );
      return null;
    }
  }

  /// Android selects the ImageDecoder bridge; tests may flip it.
  @visibleForTesting
  static bool onAndroid = Platform.isAndroid;

  /// The engine behind [bakeUpright] on this platform.
  static MediaBackend get bakeBackend =>
      onAndroid ? MediaBackend.androidDecoder : MediaBackend.imageIO;

  /// Ask the platform for upright 8-bit PNG pixels: ImageIO on iOS, Android's
  /// ImageDecoder on Android (IMG-13). A lossless PNG encoder does not prove
  /// a lossless decode/colour/HDR conversion from the original image. [toSdr]
  /// requests an SDR rendition: ImageIO tone maps PQ/HLG (iOS 17+); Android
  /// has no verified tone mapper and returns null for them. A gain-map source
  /// decodes its SDR base. [maxEdge] > 0 lets Android sample a preview down
  /// (the long edge stays at least maxEdge); iOS ignores it.
  ///
  /// Android specifics: a transparent HEIC gets its alpha back through
  /// [HeifAlpha] (IMG-15). The pixels keep the source's colour space and
  /// profile unless [srgb] asks for sRGB (what Flutter shows or crops). The
  /// bridge itself carries no metadata, so [keepMetadata] carries the
  /// source's onto its PNG through DarkLib, the EXIF orientation set upright
  /// since the pixels already are; when that fails the result is null.
  static Future<Uint8List?> bakeUpright({
    required Uint8List source,
    required bool keepMetadata,
    required bool keepOriginalTime,
    bool toSdr = false,
    int maxEdge = 0,
    bool srgb = false,
  }) async {
    final backend = bakeBackend;
    try {
      final res = await channel.invokeMethod<Uint8List>('bakeUpright', {
        'bytes': source,
        'keepMetadata': keepMetadata,
        'keepOriginalTime': keepOriginalTime,
        'toSdr': toSdr,
        'maxEdge': maxEdge,
        'srgb': srgb,
      });
      if (res == null || res.isEmpty) {
        MediaDiagnostics.record(
          backend,
          MediaOperation.bake,
          MediaDiagnosticCode.emptyOutput,
        );
        return null;
      }
      if (backend != MediaBackend.androidDecoder) return res;
      final upright = await HeifAlpha.restore(source, res);
      if (!keepMetadata) return upright;
      final carried = await DarkLibCore.transplantMetadata(
        source: source,
        target: upright,
      );
      if (carried == null) {
        MediaDiagnostics.record(
          backend,
          MediaOperation.transplant,
          MediaDiagnosticCode.unavailable,
        );
      }
      return carried;
    } on MissingPluginException {
      MediaDiagnostics.record(
        backend,
        MediaOperation.bake,
        MediaDiagnosticCode.unavailable,
      );
      return null;
    } catch (_) {
      MediaDiagnostics.record(
        backend,
        MediaOperation.bake,
        MediaDiagnosticCode.exception,
      );
      return null;
    }
  }
}
