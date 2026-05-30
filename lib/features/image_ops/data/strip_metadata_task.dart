import 'dart:async';

import 'package:photo_manager/photo_manager.dart';

import '../../../core/isolates/media_task.dart';
import '../../../core/isolates/task_progress.dart';
import 'gallery_saver.dart';
import 'metadata.dart';

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

      // Lossless ONLY. A null result means "no safe pure-Dart stripper for this
      // format" (e.g. HEIC) — we skip it rather than re-encode and inflate it.
      final result = MetadataStripper.strip(src);
      if (result == null) {
        unsupported++;
        done++;
        yield TaskProgress(progress: done / total, phase: '$done/$total');
        continue;
      }

      try {
        final asset = await GallerySaver.saveImage(
          result.bytes,
          filename: _outName(entity, result.ext),
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

  String _outName(AssetEntity entity, String ext) {
    final title = entity.title ?? 'image';
    final dot = title.lastIndexOf('.');
    final base = dot > 0 ? title.substring(0, dot) : title;
    return '${base}_clean.$ext';
  }

  @override
  Future<void> cancel() async => _cancelled = true;

  @override
  Future<void> cleanup() async {}
}
