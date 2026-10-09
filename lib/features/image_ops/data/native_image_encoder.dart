import 'dart:io' show File, Platform;

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

  /// The Android bridge writes its PNG to a file (PERF-02): read and remove.
  static Future<Uint8List?> _readTemp(String? path) async {
    if (path == null) return null;
    final file = File(path);
    try {
      return await file.readAsBytes();
    } finally {
      try {
        await file.delete();
      } catch (_) {
        // A leftover in the cache directory is not a failed image.
      }
    }
  }

  /// Android's HEIC from bands and 512 tiles (RUN-01): memory bounded by a
  /// band whatever the size, where the plugin's HeifWriter needs the whole
  /// image in one graphics buffer. Every HEIC on Android since IMG-24: the
  /// plugin fed HeifWriter RGB_565 through a GL texture, banding every
  /// image and crashing the GPU driver at an odd width. The pixels
  /// stay as stored and [orientation] (an EXIF code, 0 = none) goes into the
  /// container. No metadata, no profile and no alpha are written: the caller
  /// carries the first two and sends only opaque, SDR sources. Null when
  /// unavailable or failed, with a diagnostic.
  static Future<HeicTilesOutput?> encodeHeicTiles({
    required Uint8List source,
    required int quality,
    required int orientation,
    int depth = 8,
  }) async {
    try {
      final res = await channel
          .invokeMapMethod<String, Object?>('encodeHeicTiles', {
            'bytes': source,
            'quality': quality,
            'orientation': orientation,
            'depth': depth,
          });
      final bytes = await _readTemp(res?['path'] as String?);
      if (bytes == null || bytes.isEmpty) {
        MediaDiagnostics.record(
          MediaBackend.androidHeic,
          MediaOperation.encode,
          MediaDiagnosticCode.emptyOutput,
        );
        return null;
      }
      return HeicTilesOutput(
        bytes,
        codec: res!['codec'] as String? ?? '',
        rateMode: res['rateMode'] as String? ?? '',
      );
    } on MissingPluginException {
      MediaDiagnostics.record(
        MediaBackend.androidHeic,
        MediaOperation.encode,
        MediaDiagnosticCode.unavailable,
      );
      return null;
    } catch (_) {
      MediaDiagnostics.record(
        MediaBackend.androidHeic,
        MediaOperation.encode,
        MediaDiagnosticCode.exception,
      );
      return null;
    }
  }

  /// Android's JPEG (IMG-24): ImageDecoder's upright ARGB_8888 pixels,
  /// encoded by Bitmap.compress (libjpeg-turbo), where flutter_image_compress
  /// decoded into RGB_565. The values stay as the decoder reads them, tagged
  /// at most with the bitmap's space: the caller carries the source's
  /// profile, which names them and replaces that tag, and on request the
  /// rest (EXIF orientation set upright).
  /// Opaque sources only (a transparent one is flattened before). Null when
  /// unavailable or failed, with a diagnostic.
  static Future<Uint8List?> encodeJpeg({
    required Uint8List source,
    required int quality,
    bool toSdr = false,
  }) async {
    try {
      final out = await _readTemp(
        await channel.invokeMethod<String>('bakeUprightFile', {
          'bytes': source,
          'toSdr': toSdr,
          'colours': BakeColours.raw.name,
          'jpegQuality': quality.clamp(1, 100),
        }),
      );
      if (out == null || out.isEmpty) {
        MediaDiagnostics.record(
          MediaBackend.androidJpeg,
          MediaOperation.encode,
          MediaDiagnosticCode.emptyOutput,
        );
        return null;
      }
      return out;
    } on MissingPluginException {
      MediaDiagnostics.record(
        MediaBackend.androidJpeg,
        MediaOperation.encode,
        MediaDiagnosticCode.unavailable,
      );
      return null;
    } catch (_) {
      MediaDiagnostics.record(
        MediaBackend.androidJpeg,
        MediaOperation.encode,
        MediaDiagnosticCode.exception,
      );
      return null;
    }
  }

  /// Android selects the ImageDecoder bridge; tests may flip it.
  @visibleForTesting
  static bool onAndroid = Platform.isAndroid;

  /// Whether [encodeHeicTiles] can write 10 bits (HEVC Main10, Android 13+;
  /// IMG-23). Asked once; false where unknown.
  static Future<bool> heicTenBit() => _heicTenBit ??= () async {
    try {
      return await channel.invokeMethod<bool>('heicTenBit') ?? false;
    } catch (_) {
      return false;
    }
  }();
  static Future<bool>? _heicTenBit;

  @visibleForTesting
  static void resetHeicTenBit() => _heicTenBit = null;

  /// Running on Android (flipped by tests through [onAndroid]).
  static bool get android => onAndroid;

  /// Android: HEIC comes from [encodeHeicTiles] and JPEG from [encodeJpeg],
  /// neither writing a profile or EXIF.
  static bool get androidHeic => onAndroid;

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
  /// [HeifAlpha] (IMG-15), and [colours] decides what the values mean:
  /// [BakeColours.keep] keeps the source's colour space, and DarkLib carries
  /// the source's profile onto the PNG, with [keepMetadata] the rest of its
  /// metadata, the EXIF orientation set upright since the pixels already are
  /// (null when that fails). [BakeColours.srgb] converts to sRGB for display,
  /// a HEIC included: Android's decoder ignores its profile (IMG-21), so the
  /// profile's space from DarkLib goes with the call and Android names the
  /// values with it before converting. [BakeColours.raw] returns the values
  /// as the decoder reads them, untagged, for a caller that carries the
  /// source's profile itself (the crop). The PNG arrives as a file
  /// (PERF-02), so a large one never sits whole on the Java heap.
  static Future<Uint8List?> bakeUpright({
    required Uint8List source,
    required bool keepMetadata,
    required bool keepOriginalTime,
    bool toSdr = false,
    int maxEdge = 0,
    BakeColours colours = BakeColours.keep,
  }) async {
    final backend = bakeBackend;
    try {
      final android = backend == MediaBackend.androidDecoder;
      final space = android && colours == BakeColours.srgb
          ? await DarkLibCore.profileSpace(source)
          : null;
      final args = {
        'bytes': source,
        'keepMetadata': keepMetadata,
        'keepOriginalTime': keepOriginalTime,
        'toSdr': toSdr,
        'maxEdge': maxEdge,
        'colours': colours.name,
        if (space != null)
          'space': Float32List.fromList([...space.toXyzD50, ...space.transfer]),
      };
      final res = android
          ? await _readTemp(
              await channel.invokeMethod<String>('bakeUprightFile', args),
            )
          : await channel.invokeMethod<Uint8List>('bakeUpright', args);
      if (res == null || res.isEmpty) {
        MediaDiagnostics.record(
          backend,
          MediaOperation.bake,
          MediaDiagnosticCode.emptyOutput,
        );
        return null;
      }
      if (!android) return res;
      final upright = await HeifAlpha.restore(source, res);
      // sRGB pixels need no profile, the source's would mislabel them; raw
      // ones get it from the caller.
      if (colours != BakeColours.keep) return upright;
      // Kept pixels are in the source's colour space: its profile always
      // goes with them (IMG-08/18), the rest of its metadata on request.
      final carried = await DarkLibCore.transplantMetadata(
        source: source,
        target: upright,
      );
      final result = carried == null || keepMetadata
          ? carried
          : await DarkLibCore.stripMetadata(carried);
      if (result == null) {
        MediaDiagnostics.record(
          backend,
          MediaOperation.transplant,
          MediaDiagnosticCode.unavailable,
        );
      }
      return result;
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

/// What the values of [NativeImageEncoder.bakeUpright]'s PNG mean (Android;
/// iOS returns ImageIO's rendition whatever is asked).
enum BakeColours {
  /// The source's colour space, its profile carried onto the PNG.
  keep,

  /// Converted to sRGB, untagged: what Flutter shows.
  srgb,

  /// As the decoder reads them, untagged; the caller names them.
  raw,
}

/// What [NativeImageEncoder.encodeHeicTiles] made, and with which encoder
/// and rate mode (recorded with measurements, rule 6).
class HeicTilesOutput {
  const HeicTilesOutput(
    this.bytes, {
    required this.codec,
    required this.rateMode,
  });
  final Uint8List bytes;
  final String codec;

  /// "qp" (a fixed QP per tile, Android 12+), "cq" or "vbr".
  final String rateMode;
}
