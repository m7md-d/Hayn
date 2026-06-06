import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/darklib/darklib.dart';
import '../../../core/isolates/media_task.dart';
import '../../../core/isolates/task_progress.dart';
import 'gallery_saver.dart';
import 'image_probe.dart';
import 'metadata.dart';
import 'native_image_stripper.dart';
import 'output_name.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StripMetadataTask — saves a metadata-free copy of each selected image
// (EXIF/GPS/camera/comments removed). JPEG/PNG are stripped losslessly; other
// formats are re-encoded once at high quality (see MetadataStripper).
//
// Deliberately does NOT carry date/GPS to the new asset — removing them is the
// whole point. The original is untouched.
// ─────────────────────────────────────────────────────────────────────────────

class StripMetadataTask extends MediaTask {
  StripMetadataTask({required this.assetIds})
      : id = 'strip-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

  final List<String> assetIds;

  @override
  final String id;

  @override
  TaskType get type => TaskType.stripMetadata;

  @override
  String? get sourceAssetId => assetIds.isNotEmpty ? assetIds.first : null;

  @override
  int get itemCount => assetIds.length;

  bool _cancelled = false;

  @override
  Stream<TaskProgress> run() async* {
    final total = assetIds.length;
    if (total == 0) {
      yield const TaskProgress(progress: 1, phase: '0/0');
      return;
    }

    var done = 0;
    var saved = 0;
    var unsupported = 0; // formats with no lossless stripper (HEIC/AVIF/…)
    for (final assetId in assetIds) {
      if (_cancelled) return;
      yield TaskProgress(progress: done / total, phase: '$done/$total');

      final entity = await AssetEntity.fromId(assetId);
      final src = await entity?.originBytes;
      if (_cancelled) return;
      if (entity == null || src == null) {
        done++;
        continue;
      }

      // Lossless ONLY (never re-encode/inflate). DarkLib (Rust) is tried first:
      // it strips JPEG/PNG/WebP AND — the win for Android — AVIF/HEIF, on every
      // platform. If it's unavailable or bails on an odd container, we fall back
      // to the legacy pure-Dart stripper (JPEG/PNG/WebP) and then the iOS-only
      // native ImageIO strip (HEIC/AVIF). A container nobody can edit losslessly
      // is reported as unsupported — never re-encoded.
      List<int> bytes = const [];
      String ext = 'jpg';
      final fmt = ImageProbe.sniff(src);

      final dl = await DarkLibCore.stripMetadata(src);
      if (_cancelled) return;
      if (kDebugMode) {
        debugPrint(
          '[Strip] fmt=$fmt in=${src.length} darklib=${dl == null ? 'null' : '${dl.length}B'}',
        );
      }
      if (dl != null) {
        bytes = dl;
        ext = _extFor(fmt);
      } else {
        final dart = MetadataStripper.strip(src);
        if (dart != null) {
          bytes = dart.bytes;
          ext = dart.ext;
        } else if (fmt == SniffedFormat.heic || fmt == SniffedFormat.avif) {
          final native = await NativeImageStripper.strip(src);
          if (_cancelled) return;
          if (native != null) {
            bytes = native;
            ext = fmt == SniffedFormat.avif ? 'avif' : 'heic';
          }
        }
      }
      if (bytes.isEmpty) {
        if (kDebugMode) debugPrint('[Strip] UNSUPPORTED fmt=$fmt');
        unsupported++;
        done++;
        yield TaskProgress(progress: done / total, phase: '$done/$total');
        continue;
      }

      try {
        final asset = await GallerySaver.saveImage(
          Uint8List.fromList(bytes),
          filename: await outputFilename(entity, ext, suffix: 'clean'),
          // No date/GPS — this is the strip tool.
        );
        if (asset != null) {
          saved++;
          outputAssetIds.add(asset.id);
        }
      } catch (_) {
        // Skip; continue the batch.
      }

      done++;
      yield TaskProgress(progress: done / total, phase: '$done/$total');
    }

    if (_cancelled) return;
    if (saved == 0) {
      // Nothing saved: if it was purely unsupported formats, surface a helpful
      // hint (use Compress for HEIC) rather than a generic failure.
      if (unsupported > 0) throw const StripUnsupportedFormat();
      throw StateError('Nothing was stripped');
    }
    yield TaskProgress(progress: 1, phase: '$saved/$total');
  }

  // Container is preserved by a lossless strip, so the output extension matches
  // the source format.
  static String _extFor(SniffedFormat f) => switch (f) {
        SniffedFormat.jpeg => 'jpg',
        SniffedFormat.png => 'png',
        SniffedFormat.webp => 'webp',
        SniffedFormat.heic => 'heic',
        SniffedFormat.avif => 'avif',
        _ => 'jpg',
      };

  @override
  Future<void> cancel() async => _cancelled = true;

  @override
  Future<void> cleanup() async {}
}
