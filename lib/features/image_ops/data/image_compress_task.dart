import 'dart:async';

import 'package:photo_manager/photo_manager.dart';

import '../../../core/capabilities/format_capabilities.dart';
import '../../../core/isolates/media_task.dart';
import '../../../core/isolates/task_progress.dart';
import '../../settings/providers/preferences_providers.dart';
import '../domain/image_format_policy.dart';
import 'gallery_saver.dart';
import 'image_encoder.dart';
import 'image_probe.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ImageCompressTask — the actual compress/convert engine, run through the
// shared TaskRunner so it surfaces in the floating Tasks badge with progress +
// cancellation.
//
// Per asset: load original → probe alpha → resolve the target format
// (docs/03-FORMATS.md, transparency-safe) → encode (with the encoder's own
// alpha-safe fallback) → save a NEW asset to the gallery. The original is
// untouched. Heavy work (decode/encode) happens in native/FFI off the main
// isolate, so the async loop here never blocks the UI.
// ─────────────────────────────────────────────────────────────────────────────

class ImageCompressTask extends MediaTask {
  ImageCompressTask({
    required this.assetIds,
    required this.format,
    required this.quality,
    required this.keepMetadata,
    this.keepOriginalTime = false,
    FormatCapabilities? caps,
  })  : id = 'compress-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}',
        _caps = caps ?? FormatCapabilities.detect();

  final List<String> assetIds;
  final DefaultFormat format;
  final int quality;

  /// Keep the photo's info — camera, EXIF and GPS location — on the new copy.
  final bool keepMetadata;

  /// Keep the ORIGINAL capture time on the copy. When false (default) the copy
  /// gets the current moment, so it lands at the top of the gallery timeline.
  /// Independent of [keepMetadata] so the user can keep location yet re-date.
  final bool keepOriginalTime;
  final FormatCapabilities _caps;

  @override
  final String id;

  @override
  TaskType get type => TaskType.compress;

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

      final hasAlpha = await ImageProbe.hasAlpha(src);
      final target = ImageFormatPolicy.resolve(
        choice: format,
        hasAlpha: hasAlpha,
        caps: _caps,
      );
      if (_cancelled) return;

      try {
        final encoded = await ImageEncoder.encode(
          source: src,
          target: target.format,
          quality: quality,
          hasAlpha: hasAlpha,
          keepMetadata: keepMetadata,
        );
        if (_cancelled) return;

        final asset = await GallerySaver.saveImage(
          encoded.bytes,
          filename: _outName(entity, encoded.extension),
          // Time and location are independent choices now.
          creationDate: keepOriginalTime ? entity.createDateTime : null,
          latitude: keepMetadata ? entity.latitude : null,
          longitude: keepMetadata ? entity.longitude : null,
        );
        if (asset != null) {
          saved++;
          outputAssetIds.add(asset.id);
        }
      } catch (_) {
        // Skip this asset; the rest of the batch continues.
      }

      done++;
      yield TaskProgress(progress: done / total, phase: '$done/$total');
    }

    if (_cancelled) return;
    if (saved == 0) {
      throw StateError('No image was saved');
    }
    yield TaskProgress(progress: 1, phase: '$saved/$total');
  }

  String _outName(AssetEntity entity, String ext) {
    final title = entity.title ?? 'image';
    final dot = title.lastIndexOf('.');
    final base = dot > 0 ? title.substring(0, dot) : title;
    return '$base.$ext';
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  @override
  Future<void> cleanup() async {}
}
