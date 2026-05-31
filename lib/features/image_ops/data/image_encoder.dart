import 'dart:typed_data';

import 'package:flutter_avif/flutter_avif.dart' as avif;
import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;

import '../../settings/providers/preferences_providers.dart';
import 'native_image_encoder.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ImageEncoder — turns source image bytes into a target format, honouring the
// "detect, don't assume" rule (CLAUDE.md §2/§7): instead of trusting a
// capability map, it ATTEMPTS the requested encoder and, if the device can't
// produce it (e.g. HEIC needs a hardware encoder; WebP encode is Android-only
// in flutter_image_compress), walks an ordered fallback that NEVER drops alpha.
//
// Engines:
//   • AVIF       → flutter_avif.encodeAvif (libaom, royalty-free; multithread).
//   • HEIC/JPEG  → NativeImageEncoder (iOS ImageIO) first, flutter_image_compress
//                  as the fallback. The native path avoids the "AlphaLast"
//                  warning and carries real camera EXIF into HEIC.
//   • WebP/PNG   → flutter_image_compress (libwebp / system).
// Both run their heavy work off the Dart main isolate (FFI thread / platform
// thread), so callers don't need to spawn an isolate just for the encode.
//
// Metadata: the native HEIC/JPEG path copies the source's full property set when
// keepMetadata is set. On the plugin fallback, keepExif is JPEG-only (and AVIF
// keeps date+GPS at the gallery-asset level, not in-file) — see
// [_supportsKeepExif].
// ─────────────────────────────────────────────────────────────────────────────

class EncodedImage {
  const EncodedImage(this.bytes, this.format);

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
  /// only if even the universal floor (PNG/JPEG) fails.
  static Future<EncodedImage> encode({
    required Uint8List source,
    required DefaultFormat target,
    required int quality,
    required bool hasAlpha,
    required bool keepMetadata,
    int? maxWidth,
    int? maxHeight,
  }) async {
    for (final fmt in fallbackChain(target, hasAlpha)) {
      final bytes = await _tryEncode(
        source: source,
        format: fmt,
        quality: quality,
        keepMetadata: keepMetadata,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
      if (bytes != null && bytes.isNotEmpty) return EncodedImage(bytes, fmt);
    }
    throw StateError('No image encoder succeeded for $target');
  }

  /// Ordered formats to attempt: requested first, then alpha-aware fallbacks.
  /// PNG is the always-available alpha-safe floor; JPEG the opaque floor. An
  /// alpha image never lists JPEG. Pure + unit-testable.
  static List<DefaultFormat> fallbackChain(DefaultFormat target, bool hasAlpha) {
    final out = <DefaultFormat>[];
    void add(DefaultFormat f) {
      if (f == DefaultFormat.auto) return;
      if (hasAlpha && f == DefaultFormat.jpeg) return; // never flatten on fallback
      if (!out.contains(f)) out.add(f);
    }

    add(target);
    add(DefaultFormat.webp); // mid fallback (cheap, wide support on Android)
    if (hasAlpha) {
      add(DefaultFormat.png); // alpha-safe floor, always available
    } else {
      add(DefaultFormat.jpeg); // opaque floor, always available
      add(DefaultFormat.png); // last resort
    }
    return out;
  }

  static Future<Uint8List?> _tryEncode({
    required Uint8List source,
    required DefaultFormat format,
    required int quality,
    required bool keepMetadata,
    int? maxWidth,
    int? maxHeight,
  }) async {
    try {
      if (format == DefaultFormat.avif) {
        // Lower quantizer = higher quality. Map 0–100 → ~[55..12].
        final maxQ = (63 - quality * 0.5).round().clamp(12, 55);
        final minQ = (maxQ - 12).clamp(0, maxQ);
        final out = await avif.encodeAvif(
          source,
          minQuantizer: minQ,
          maxQuantizer: maxQ,
          minQuantizerAlpha: minQ,
          maxQuantizerAlpha: maxQ,
          // flutter_avif is SOFTWARE libaom (no hardware path), so encoding is
          // CPU-bound — use more threads + a faster speed to cut the wait.
          maxThreads: 8,
          speed: 8,
          // IMPORTANT: keepExif MUST stay false. The package decodes with
          // ui.instantiateImageCodec (which already BAKES EXIF orientation into
          // the pixels) but, when keepExif is true, ALSO copies the original
          // Orientation tag into the output — so viewers rotate a second time
          // and the photo comes out sideways. Dropping in-file EXIF here is
          // consistent with our other formats; capture date + GPS are still
          // carried at the gallery-asset level by the saver.
          keepExif: false,
        );
        return out;
      }

      final cf = switch (format) {
        DefaultFormat.heic => fic.CompressFormat.heic,
        DefaultFormat.webp => fic.CompressFormat.webp,
        DefaultFormat.png => fic.CompressFormat.png,
        DefaultFormat.jpeg => fic.CompressFormat.jpeg,
        DefaultFormat.avif || DefaultFormat.auto => null,
      };
      if (cf == null) return null;

      // Prefer our own ImageIO encoder for HEIC/JPEG: it avoids the plugin's
      // "opaque image with AlphaLast" warning and carries real camera EXIF into
      // HEIC. Only when there's no downscale cap (a cap falls through to the
      // plugin, which scales). Native returns null off-iOS / on any failure, so
      // the plugin below stays the safety net.
      final noCap = maxWidth == null && maxHeight == null;
      if (noCap &&
          (format == DefaultFormat.heic || format == DefaultFormat.jpeg)) {
        final native = await NativeImageEncoder.encode(
          source: source,
          format: format == DefaultFormat.heic ? 'heic' : 'jpeg',
          quality: quality.clamp(1, 100),
          keepMetadata: keepMetadata,
        );
        if (native != null && native.isNotEmpty) return native;
      }

      // Huge default bounds = "keep original dimensions"; a real cap only when
      // the caller asks for one. flutter_image_compress scales DOWN to fit.
      return fic.FlutterImageCompress.compressWithList(
        source,
        format: cf,
        quality: quality.clamp(1, 100),
        minWidth: maxWidth ?? 1000000,
        minHeight: maxHeight ?? 1000000,
        keepExif: keepMetadata && _supportsKeepExif(format),
      );
    } catch (_) {
      // Encoder unavailable / failed on this device → let the chain continue.
      return null;
    }
  }

  /// flutter_image_compress only carries EXIF through for JPEG. AVIF now drops
  /// in-file EXIF too (keepExif there double-rotates — see the encode path);
  /// HEIC/WebP/PNG would need a manual transplant. Capture date + GPS are
  /// preserved at the gallery-asset level by the saver regardless.
  static bool _supportsKeepExif(DefaultFormat f) => f == DefaultFormat.jpeg;
}
