import 'package:flutter/services.dart';

import '../../../core/diagnostics/media_diagnostics.dart';

// ImageIO platform adapter. Absent plugins, failed calls and empty results
// remain distinguishable in release diagnostics. Null permits fallback.
// Preservation needs independent validation; copying properties alone is not
// proof of unchanged orientation, colour or HDR (docs/12-STABILIZATION.md).

abstract final class NativeImageEncoder {
  // Shares the lossless-strip channel; the native side multiplexes by method.
  static const MethodChannel channel = MethodChannel('hayn/metadata');

  /// Encode [source] to [format] ('heic' | 'jpeg' | 'png') at [quality] (0–100).
  /// Flags request metadata, capture time and bit depth from the native code.
  /// Their semantic preservation is not guaranteed by this adapter.
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

  /// Ask ImageIO for upright PNG pixels. A lossless PNG encoder does not prove
  /// a lossless decode/colour/HDR conversion from the original image.
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
      if (res == null || res.isEmpty) {
        MediaDiagnostics.record(
          MediaBackend.imageIO,
          MediaOperation.bake,
          MediaDiagnosticCode.emptyOutput,
        );
        return null;
      }
      return res;
    } on MissingPluginException {
      MediaDiagnostics.record(
        MediaBackend.imageIO,
        MediaOperation.bake,
        MediaDiagnosticCode.unavailable,
      );
      return null;
    } catch (_) {
      MediaDiagnostics.record(
        MediaBackend.imageIO,
        MediaOperation.bake,
        MediaDiagnosticCode.exception,
      );
      return null;
    }
  }
}
