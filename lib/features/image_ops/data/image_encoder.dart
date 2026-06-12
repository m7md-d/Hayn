import 'package:flutter/foundation.dart';
import 'package:flutter_avif/flutter_avif.dart' as avif;
import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;

import '../../../core/darklib/darklib.dart';
import '../../settings/providers/preferences_providers.dart';
import 'native_avif_encoder.dart';
import 'native_image_encoder.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ImageEncoder — turns source image bytes into a target format, honouring the
// "detect, don't assume" rule (CLAUDE.md §2/§7): instead of trusting a
// capability map, it ATTEMPTS the requested encoder and, if the device can't
// produce it (e.g. HEIC needs a hardware encoder; WebP encode is Android-only
// in flutter_image_compress), walks an ordered fallback that NEVER drops alpha.
//
// Engines (in attempt order per format):
//   • AVIF       → hardware AV1 (Android MediaCodec) + DarkLib metadata
//                  transplant → DarkLib (rav1e: metadata/HDR/grid-tiling) →
//                  flutter_avif (software libaom; covers HEIC sources via the
//                  platform decode).
//   • WebP       → DarkLib (every platform, in-file metadata) →
//                  flutter_image_compress (encode is Android-only).
//   • HEIC/JPEG/PNG → NativeImageEncoder (iOS ImageIO) first, with
//                  flutter_image_compress as the fallback. The native path
//                  avoids the "AlphaLast" warning and carries real camera
//                  metadata (the plugin only did EXIF for JPEG).
// All engines run their heavy work off the Dart main isolate (FFI thread /
// platform thread), so callers don't need to spawn an isolate for the encode.
//
// Metadata: DarkLib carries EXIF/XMP/ICC in-file for AVIF/WebP; the native
// HEIC/JPEG path copies the source's full property set. On the plugin fallback,
// keepExif is JPEG-only — see [_supportsKeepExif]. Date+GPS are also preserved
// at the gallery-asset level by the saver.
// ─────────────────────────────────────────────────────────────────────────────

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
    bool keepOriginalTime = true,
    int bitDepth = 0,
    int? maxWidth,
    int? maxHeight,
  }) async {
    for (final fmt in fallbackChain(target, hasAlpha)) {
      final bytes = await _tryEncode(
        source: source,
        format: fmt,
        quality: quality,
        keepMetadata: keepMetadata,
        keepOriginalTime: keepOriginalTime,
        bitDepth: bitDepth,
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
    bool keepOriginalTime = true,
    int bitDepth = 0,
    int? maxWidth,
    int? maxHeight,
  }) async {
    try {
      if (format == DefaultFormat.avif) {
        // Hardware AV1 (Android MediaCodec) → real .avif, royalty-free + fast,
        // instead of software libaom. It self-validates its output and returns
        // null on iOS / older SoCs / any failure → we fall back to the software
        // paths below. The hardware encoder can't write in-file metadata, so
        // DarkLib transplants the source's EXIF/XMP/ICC into its output by
        // lossless container surgery (works for ANY source incl. HEIC — extract
        // is container-level, no decode needed). Transplant failure just means
        // the bytes come back unchanged — never worse than before.
        final hw =
            await NativeAvifEncoder.encode(source: source, quality: quality);
        if (hw != null && hw.isNotEmpty) {
          if (!keepMetadata) return hw;
          return await DarkLibCore.transplantMetadata(
                source: source,
                target: hw,
              ) ??
              hw;
        }

        // DarkLib software AVIF (rav1e): carries EXIF/XMP/ICC properly, keeps
        // an HDR gain map on AVIF→AVIF, synthesises ICC from nclx, and tiles
        // huge opaque images as an ImageGrid instead of failing. Covers every
        // source it can decode (JPEG/PNG/WebP/AVIF); HEIC sources return null
        // here and continue to the flutter_avif path, which decodes via the
        // platform.
        final dark = await DarkLibCore.transcode(
          source,
          format: DarkLibFormat.avif,
          quality: quality,
          keepMetadata: keepMetadata,
          maxEdge: maxWidth ?? 0,
        );
        if (dark != null && dark.isNotEmpty) return dark;
        // Lower quantizer = higher quality. Map 0–100 → ~[55..12].
        final maxQ = (63 - quality * 0.5).round().clamp(12, 55);
        final minQ = (maxQ - 12).clamp(0, maxQ);
        // flutter_avif mishandles orientation + date, so we bake the rotation
        // into the pixels natively and hand it an already-upright LOSSLESS PNG
        // whose embedded EXIF is exactly what we want; it just copies that EXIF
        // in → correct orientation + time + camera metadata, with PNG lossless so
        // only the AVIF pass is lossy. (This is per-image, one-at-a-time in the
        // task — NOT the cause of the earlier OOM, which was the estimate's
        // sampling loop.) Off-iOS the bake is null → keepExif:false fallback.
        final baked = await NativeImageEncoder.bakeUpright(
          source: source,
          keepMetadata: keepMetadata,
          keepOriginalTime: keepOriginalTime,
        );
        final input = baked ?? source;
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

      // WebP: DarkLib first — it encodes WebP on EVERY platform (the plugin's
      // WebP encode is Android-only, so an iOS WebP request used to silently
      // fall away to another format) and it carries EXIF/XMP/ICC inside the
      // file, which the plugin never did for WebP. HEIC sources return null and
      // fall through to the plugin.
      if (format == DefaultFormat.webp) {
        final dark = await DarkLibCore.transcode(
          source,
          format: DarkLibFormat.webp,
          quality: quality,
          keepMetadata: keepMetadata,
          maxEdge: maxWidth ?? 0,
        );
        if (dark != null && dark.isNotEmpty) return dark;
      }

      final noCap = maxWidth == null && maxHeight == null;

      // PNG output: viewers ignore EXIF orientation, so bake it into the pixels
      // (lossless) rather than leave a tag that shows sideways. The bake also
      // carries the corrected metadata. Falls through to the plugin off-iOS
      // (Android applies orientation on decode).
      if (noCap && format == DefaultFormat.png) {
        final baked = await NativeImageEncoder.bakeUpright(
          source: source,
          keepMetadata: keepMetadata,
          keepOriginalTime: keepOriginalTime,
        );
        if (baked != null && baked.isNotEmpty) return baked;
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
    } catch (e) {
      // Encoder unavailable / failed on this device → let the chain continue —
      // but never swallow the reason invisibly (CLAUDE.md §7): surface it in
      // debug builds so a misbehaving encoder is diagnosable.
      if (kDebugMode) debugPrint('[ImageEncoder] $format failed: $e');
      return null;
    }
  }

  /// flutter_image_compress only carries EXIF through for JPEG (keepExif on
  /// AVIF double-rotates — see the encode path). WebP/AVIF metadata is now
  /// handled upstream by DarkLib (in-file EXIF/XMP/ICC); this flag only governs
  /// the plugin fallback. Capture date + GPS are preserved at the gallery-asset
  /// level by the saver regardless.
  static bool _supportsKeepExif(DefaultFormat f) => f == DefaultFormat.jpeg;
}
