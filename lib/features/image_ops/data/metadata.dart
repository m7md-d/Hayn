import 'dart:typed_data';

import 'package:exif/exif.dart';

import 'image_probe.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Metadata read + strip.
//
// Reading (for "here's what will be removed"): a header parse via package:exif,
// so it works even for HEIC (where a full pixel decode isn't available).
//
// Stripping is LOSSLESS-ONLY and lives in DarkLib (`DarkLibCore.stripMetadata`,
// every platform) with the iOS native writer as a HEIC/AVIF fallback. It keeps
// an orientation-only EXIF so the image stays upright (IMG-07). The former
// pure-Dart JPEG/PNG/WebP editor duplicated that path, had the orientation bug,
// and was removed; this file keeps only the cheap entry-point gate.
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown by [StripMetadataTask] when nothing could be stripped because every
/// input was in a format with no lossless editor (GIF/BMP/TIFF), or a specific
/// file DarkLib refused to edit safely. The UI maps this to a helpful, localised
/// hint instead of a raw error string.
class StripUnsupportedFormat implements Exception {
  const StripUnsupportedFormat();
}

class MetadataSummary {
  const MetadataSummary({
    required this.hasGps,
    required this.hasDate,
    required this.hasCamera,
    required this.tagCount,
  });

  final bool hasGps;
  final bool hasDate;
  final bool hasCamera;
  final int tagCount;

  bool get isEmpty => tagCount == 0;

  static const empty = MetadataSummary(
    hasGps: false,
    hasDate: false,
    hasCamera: false,
    tagCount: 0,
  );
}

abstract final class MetadataReader {
  static Future<MetadataSummary> read(Uint8List bytes) async {
    try {
      final tags = await readExifFromBytes(bytes);
      if (tags.isEmpty) return MetadataSummary.empty;
      bool any(bool Function(String) p) => tags.keys.any(p);
      return MetadataSummary(
        hasGps: any((k) => k.startsWith('GPS')),
        hasDate: any((k) => k.contains('DateTime')),
        hasCamera:
            tags.containsKey('Image Make') || tags.containsKey('Image Model'),
        tagCount: tags.length,
      );
    } catch (_) {
      return MetadataSummary.empty;
    }
  }
}

abstract final class MetadataStripper {
  /// Whether the strip PIPELINE can handle [bytes] losslessly. DarkLib strips
  /// JPEG/PNG/WebP/HEIC/AVIF on every platform, with the iOS native writer as a
  /// HEIC/AVIF fallback. GIF/BMP/TIFF still
  /// have no lossless editor. Cheap (magic-byte sniff only) — lets callers warn
  /// up front before enqueuing. A specific file DarkLib can't safely edit is
  /// still caught at run time (the task reports [StripUnsupportedFormat]).
  static bool canStrip(Uint8List bytes) => switch (ImageProbe.sniff(bytes)) {
        SniffedFormat.jpeg ||
        SniffedFormat.png ||
        SniffedFormat.webp ||
        SniffedFormat.heic ||
        SniffedFormat.avif =>
          true,
        _ => false,
      };
}
