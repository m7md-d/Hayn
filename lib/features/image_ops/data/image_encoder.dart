import 'dart:typed_data';

import '../../../core/diagnostics/media_diagnostics.dart';

import 'package:flutter_avif/flutter_avif.dart' as avif;
import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;

import '../../../core/darklib/darklib.dart';
import '../../settings/providers/preferences_providers.dart';
import 'native_avif_encoder.dart';
import 'native_image_encoder.dart';
import 'image_probe.dart';

// Coordinates the existing backends. Non-empty output is NOT proof that HDR,
// colour, orientation or metadata survived: see docs/12-STABILIZATION.md.
// Backend and format fallback are recorded in bounded release diagnostics.

/// Longest output edge we encode. Decoding a ~200 MP image at full size is
/// ~800 MB of RGBA → an instant OOM, and it also exceeds hardware encoder limits.
/// Sources whose long edge exceeds this are downscaled to fit (normal photos,
/// incl. 48 MP at 8064 px, are untouched). Matches the native AVIF path's cap.
const int kMaxEncodeLongEdge = 8192;

/// The (maxWidth,maxHeight) cap for a source of [width]×[height], or (null,null)
/// when it's already within [kMaxEncodeLongEdge].
({int? maxWidth, int? maxHeight}) encodeCapFor(int width, int height) {
  final longEdge = width > height ? width : height;
  if (longEdge <= kMaxEncodeLongEdge || longEdge == 0) {
    return (maxWidth: null, maxHeight: null);
  }
  return (maxWidth: kMaxEncodeLongEdge, maxHeight: kMaxEncodeLongEdge);
}

class EncodedImage {
  const EncodedImage(
    this.bytes,
    this.format, {
    this.backend,
    this.requestedFormat,
    this.diagnostics = const [],
  });

  final MediaBackend? backend;
  final DefaultFormat? requestedFormat;
  final List<MediaDiagnostic> diagnostics;

  final Uint8List bytes;

  /// The format actually produced — may differ from the request if a fallback
  /// kicked in (surface this to the user).
  final DefaultFormat format;

  String get extension => switch (format) {
    DefaultFormat.avif => 'avif',
    DefaultFormat.heic => 'heic',
    DefaultFormat.webp => 'webp',
    DefaultFormat.png => 'png',
    DefaultFormat.jpeg => 'jpg',
    DefaultFormat.auto => 'jpg',
  };
}

abstract final class ImageEncoder {
  /// Encode [source] to [target] at [quality] (0–100). On encoder failure walks
  /// [fallbackChain]. Returns the bytes + the format actually produced. Throws
  /// if all permitted encoders fail. Format changes require explicit permission;
  /// backend recovery within the requested format remains allowed. A preservation
  /// rejection is terminal. Diagnostics accompany success or failure.
  static Future<EncodedImage> encode({
    required Uint8List source,
    required DefaultFormat target,
    required int quality,
    required bool? hasAlpha,
    required bool keepMetadata,
    bool allowFormatFallback = false,
    bool keepOriginalTime = true,
    int bitDepth = 0,
    int? maxWidth,
    int? maxHeight,
  }) => MediaDiagnostics.trace((trace) async {
    if (target == DefaultFormat.auto ||
        (target == DefaultFormat.jpeg && hasAlpha != false)) {
      MediaDiagnostics.record(
        MediaBackend.imageEncoder,
        MediaOperation.encode,
        MediaDiagnosticCode.preservationRejected,
      );
      throw ImageEncodingFailure(target, trace.events);
    }
    final candidates = allowFormatFallback
        ? fallbackChain(target, hasAlpha)
        : [target];
    for (final fmt in candidates) {
      if (fmt != target) {
        MediaDiagnostics.record(
          MediaBackend.imageEncoder,
          MediaOperation.encode,
          MediaDiagnosticCode.formatFallback,
        );
      }
      EncodedImage? encoded;
      try {
        encoded = await _tryEncode(
          source: source,
          format: fmt,
          quality: quality,
          hasAlpha: hasAlpha,
          keepMetadata: keepMetadata,
          keepOriginalTime: keepOriginalTime,
          bitDepth: bitDepth,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        );
      } on DarkLibPreservationFailure {
        // Retrying another codec must not turn a preservation veto into success.
        throw ImageEncodingFailure(target, trace.events);
      }
      if (encoded != null) {
        if (!_matchesFormat(encoded.bytes, fmt)) {
          MediaDiagnostics.record(
            encoded.backend ?? MediaBackend.imageEncoder,
            MediaOperation.encode,
            MediaDiagnosticCode.outputFormatMismatch,
          );
          continue;
        }
        if (hasAlpha == true) {
          final outputAlpha = await ImageProbe.hasAlpha(encoded.bytes);
          if (outputAlpha != true) {
            MediaDiagnostics.record(
              encoded.backend ?? MediaBackend.imageEncoder,
              MediaOperation.encode,
              outputAlpha == false
                  ? MediaDiagnosticCode.alphaLost
                  : MediaDiagnosticCode.alphaUnverified,
            );
            continue;
          }
        } else if (hasAlpha == null) {
          MediaDiagnostics.record(
            MediaBackend.imageEncoder,
            MediaOperation.probe,
            MediaDiagnosticCode.alphaUnverified,
          );
        }
        return EncodedImage(
          encoded.bytes,
          encoded.format,
          backend: encoded.backend,
          requestedFormat: target,
          diagnostics: trace.events,
        );
      }
    }
    throw ImageEncodingFailure(target, trace.events);
  });

  /// Ordered formats to attempt: requested first, then alpha-aware fallbacks.
  /// PNG is the final alpha-capable candidate; JPEG is opaque. An
  /// alpha image never lists JPEG. Pure + unit-testable.
  static List<DefaultFormat> fallbackChain(
    DefaultFormat target,
    bool? hasAlpha,
  ) {
    final out = <DefaultFormat>[];
    void add(DefaultFormat f) {
      if (f == DefaultFormat.auto) return;
      if (hasAlpha != false && f == DefaultFormat.jpeg) {
        return; // never flatten on fallback
      }
      if (!out.contains(f)) out.add(f);
    }

    add(target);
    add(DefaultFormat.webp); // mid fallback (cheap, wide support on Android)
    if (hasAlpha != false) {
      add(DefaultFormat.png); // alpha-safe floor, always available
    } else {
      add(DefaultFormat.jpeg); // opaque floor, always available
      add(DefaultFormat.png); // last resort
    }
    return out;
  }

  static Future<EncodedImage?> _tryEncode({
    required Uint8List source,
    required DefaultFormat format,
    required int quality,
    required bool? hasAlpha,
    required bool keepMetadata,
    bool keepOriginalTime = true,
    int bitDepth = 0,
    int? maxWidth,
    int? maxHeight,
  }) async {
    var backend = MediaBackend.androidAvif;
    try {
      if (format == DefaultFormat.avif) {
        // Hardware output is followed by a best-effort metadata transplant.
        // This path still needs independent preservation verification.
        // Android's current bitmap/YUV path has no alpha plane.
        final hw = hasAlpha == false
            ? await NativeAvifEncoder.encode(source: source, quality: quality)
            : null;
        if (hw != null && hw.isNotEmpty) {
          if (!keepMetadata) return EncodedImage(hw, format, backend: backend);
          final withMetadata = await DarkLibCore.transplantMetadata(
            source: source,
            target: hw,
          );
          if (withMetadata == null || withMetadata.isEmpty) {
            MediaDiagnostics.record(
              MediaBackend.darklib,
              MediaOperation.transplant,
              MediaDiagnosticCode.preservationUnverified,
            );
          }
          return EncodedImage(
            withMetadata == null || withMetadata.isEmpty ? hw : withMetadata,
            format,
            backend: backend,
          );
        }

        // DarkLib software AVIF. Preservation limitations remain in phase B.
        backend = MediaBackend.darklib;
        final dark = await DarkLibCore.transcode(
          source,
          format: DarkLibFormat.avif,
          quality: quality,
          keepMetadata: keepMetadata,
          maxEdge: maxWidth ?? 0,
        );
        if (dark != null && dark.isNotEmpty) {
          return EncodedImage(dark, format, backend: backend);
        }

        // Platform decode bridge for sources DarkLib cannot decode directly.
        // PNG encoding does not prove preservation of source HDR or colour.
        final baked = await NativeImageEncoder.bakeUpright(
          source: source,
          keepMetadata: keepMetadata,
          keepOriginalTime: keepOriginalTime,
        );
        if (baked != null && baked.isNotEmpty) {
          final bridged = await DarkLibCore.transcode(
            baked,
            format: DarkLibFormat.avif,
            quality: quality,
            keepMetadata: keepMetadata,
            maxEdge: maxWidth ?? 0,
          );
          if (bridged != null && bridged.isNotEmpty) {
            return EncodedImage(bridged, format, backend: backend);
          }
        }

        // Lower quantizer = higher quality. Map 0–100 → ~[55..12].
        final maxQ = (63 - quality * 0.5).round().clamp(12, 55);
        final minQ = (maxQ - 12).clamp(0, maxQ);
        // Transitional software fallback; its EXIF handling is limited.
        final input = baked ?? source;
        backend = MediaBackend.flutterAvif;
        final out = await avif.encodeAvif(
          input,
          minQuantizer: minQ,
          maxQuantizer: maxQ,
          minQuantizerAlpha: minQ,
          maxQuantizerAlpha: maxQ,
          // flutter_avif is SOFTWARE libaom (no hardware path), so encoding is
          // CPU-bound — use more threads + a faster speed to cut the wait.
          maxThreads: 8,
          speed: 8,
          keepExif: baked != null && keepMetadata,
        );
        return _result(out, format, backend);
      }

      final cf = switch (format) {
        DefaultFormat.heic => fic.CompressFormat.heic,
        DefaultFormat.webp => fic.CompressFormat.webp,
        DefaultFormat.png => fic.CompressFormat.png,
        DefaultFormat.jpeg => fic.CompressFormat.jpeg,
        DefaultFormat.avif || DefaultFormat.auto => null,
      };
      if (cf == null) return null;

      // WebP: DarkLib first — it encodes WebP on EVERY platform (the plugin's
      // WebP encode is Android-only, so an iOS WebP request used to silently
      // fall away to another format) and it carries EXIF/XMP/ICC inside the
      // file, which the plugin never did for WebP. A HEIC source fails the
      // direct transcode and goes over the same platform-decode bridge as AVIF
      // (bakeUpright → DarkLib); off-iOS the bake is null and the plugin below
      // handles it (Android decodes HEIC platform-side).
      if (format == DefaultFormat.webp) {
        backend = MediaBackend.darklib;
        final dark = await DarkLibCore.transcode(
          source,
          format: DarkLibFormat.webp,
          quality: quality,
          keepMetadata: keepMetadata,
          maxEdge: maxWidth ?? 0,
        );
        if (dark != null && dark.isNotEmpty) {
          return EncodedImage(dark, format, backend: backend);
        }
        final baked = await NativeImageEncoder.bakeUpright(
          source: source,
          keepMetadata: keepMetadata,
          keepOriginalTime: keepOriginalTime,
        );
        if (baked != null && baked.isNotEmpty) {
          final bridged = await DarkLibCore.transcode(
            baked,
            format: DarkLibFormat.webp,
            quality: quality,
            keepMetadata: keepMetadata,
            maxEdge: maxWidth ?? 0,
          );
          if (bridged != null && bridged.isNotEmpty) {
            return EncodedImage(bridged, format, backend: backend);
          }
        }
      }

      final noCap = maxWidth == null && maxHeight == null;

      // Prefer upright platform pixels for PNG; source preservation remains
      // subject to the colour/HDR limitations in the stabilization plan.
      if (noCap && format == DefaultFormat.png) {
        final baked = await NativeImageEncoder.bakeUpright(
          source: source,
          keepMetadata: keepMetadata,
          keepOriginalTime: keepOriginalTime,
        );
        if (baked != null && baked.isNotEmpty) {
          return EncodedImage(baked, format, backend: MediaBackend.imageIO);
        }
      }

      // Prefer our own ImageIO encoder for HEIC/JPEG: it avoids the plugin's
      // "opaque image with AlphaLast" warning and carries real camera metadata
      // (the plugin only did EXIF for JPEG), keeping the orientation TAG (which
      // HEIC/JPEG viewers honour). Native returns null off-iOS / on failure, so
      // the plugin below stays the safety net.
      const nativeFormats = {DefaultFormat.heic, DefaultFormat.jpeg};
      if (noCap && nativeFormats.contains(format)) {
        final native = await NativeImageEncoder.encode(
          source: source,
          format: format == DefaultFormat.heic ? 'heic' : 'jpeg',
          quality: quality.clamp(1, 100),
          keepMetadata: keepMetadata,
          keepOriginalTime: keepOriginalTime,
          // Only HEIC honours a forced depth; JPEG is 8-bit anyway.
          bitDepth: format == DefaultFormat.heic ? bitDepth : 0,
        );
        if (native != null && native.isNotEmpty) {
          return EncodedImage(native, format, backend: MediaBackend.imageIO);
        }
      }

      // Huge default bounds = "keep original dimensions"; a real cap only when
      // the caller asks for one. flutter_image_compress scales DOWN to fit.
      backend = MediaBackend.imageCompress;
      final out = await fic.FlutterImageCompress.compressWithList(
        source,
        format: cf,
        quality: quality.clamp(1, 100),
        minWidth: maxWidth ?? 1000000,
        minHeight: maxHeight ?? 1000000,
        keepExif: keepMetadata && _supportsKeepExif(format),
      );
      return _result(out, format, backend);
    } on DarkLibPreservationFailure {
      rethrow;
    } catch (_) {
      MediaDiagnostics.record(
        backend,
        MediaOperation.encode,
        MediaDiagnosticCode.exception,
      );
      return null;
    }
  }

  // Container identity only, not proof of complete decoding or HDR fidelity.
  static bool _matchesFormat(Uint8List bytes, DefaultFormat format) =>
      ImageProbe.sniff(bytes) ==
      switch (format) {
        DefaultFormat.avif => SniffedFormat.avif,
        DefaultFormat.heic => SniffedFormat.heic,
        DefaultFormat.webp => SniffedFormat.webp,
        DefaultFormat.png => SniffedFormat.png,
        DefaultFormat.jpeg => SniffedFormat.jpeg,
        DefaultFormat.auto => SniffedFormat.unknown,
      };

  static EncodedImage? _result(
    Uint8List bytes,
    DefaultFormat format,
    MediaBackend backend,
  ) {
    if (bytes.isEmpty) {
      MediaDiagnostics.record(
        backend,
        MediaOperation.encode,
        MediaDiagnosticCode.emptyOutput,
      );
      return null;
    }
    return EncodedImage(bytes, format, backend: backend);
  }

  /// The plugin can request JPEG EXIF copying. This is not a full metadata,
  /// orientation, colour or HDR preservation contract.
  static bool _supportsKeepExif(DefaultFormat f) => f == DefaultFormat.jpeg;
}

class ImageEncodingFailure implements Exception {
  ImageEncodingFailure(this.requestedFormat, List<MediaDiagnostic> diagnostics)
    : diagnostics = List.unmodifiable(diagnostics);
  final DefaultFormat requestedFormat;
  final List<MediaDiagnostic> diagnostics;

  @override
  String toString() => 'No image encoder succeeded for ${requestedFormat.name}';
}
