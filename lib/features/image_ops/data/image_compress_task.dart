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
import 'output_name.dart';

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
    this.bitDepth = 0,
    this.precomputedId,
    this.precomputed,
    FormatCapabilities? caps,
  })  : id = 'compress-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}',
        _caps = caps ?? FormatCapabilities.detect();

  final List<String> assetIds;
  final DefaultFormat format;
  final int quality;

  /// The compress screen already encoded ONE image (the active preview) with
  /// these exact settings. We reuse those bytes for [precomputedId] instead of
  /// re-encoding — saving a second (slow, for AVIF) pass and a re-export of the
  /// original. The bytes are byte-for-byte what this task would produce, so the
  /// chosen format + metadata + time are already baked in. The screen only
  /// passes these when its settings signature still matches, so they can't drift.
  final String? precomputedId;
  final EncodedImage? precomputed;

  /// Keep the photo's info — camera, EXIF and GPS location — on the new copy.
  final bool keepMetadata;

  /// Target output bit depth: 0 = match source (preserves HDR), 8 = force SDR.
  final int bitDepth;

  /// Release iOS's tmp-exported originals every this many images (memory).
  static const int _cacheClearEvery = 12;

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
      if (_cancelled) return;
      if (entity == null) {
        done++;
        continue;
      }

      // Reuse the preview's finished encode for the active image; otherwise
      // load + probe + encode. The reuse path skips `originBytes` entirely, so
      // it neither re-exports the original nor runs a second encode.
      EncodedImage? encoded;
      if (precomputed != null && assetId == precomputedId) {
        encoded = precomputed;
      } else {
        final src = await entity.originBytes;
        if (_cancelled) return;
        if (src != null) {
          final hasAlpha = await ImageProbe.hasAlpha(src);
          final target = ImageFormatPolicy.resolve(
            choice: format,
            hasAlpha: hasAlpha,
            caps: _caps,
          );
          if (_cancelled) return;
          // Huge images (≈200 MP) would OOM the decode — cap the long edge.
          final cap = encodeCapFor(entity.width, entity.height);
          try {
            encoded = await ImageEncoder.encode(
              source: src,
              target: target.format,
              quality: quality,
              hasAlpha: hasAlpha,
              keepMetadata: keepMetadata,
              keepOriginalTime: keepOriginalTime,
              bitDepth: bitDepth,
              maxWidth: cap.maxWidth,
              maxHeight: cap.maxHeight,
            );
          } catch (_) {
            encoded = null;
          }
        }
      }
      if (_cancelled) return;
      if (encoded == null) {
        done++;
        if (done % _cacheClearEvery == 0) await PhotoManager.clearFileCache();
        continue;
      }

      try {
        final asset = await GallerySaver.saveImage(
          encoded.bytes,
          filename: await outputFilename(entity, encoded.extension),
          // Time + location are independent choices. When the user opts OUT of
          // keeping the original time we must pass `now` EXPLICITLY, not null —
          // PhotoKit falls back to the file's embedded EXIF date on null, which
          // is why an AVIF copy kept its original time. `now` forces the asset
          // to the top of the timeline regardless of any in-file date.
          creationDate:
              keepOriginalTime ? entity.createDateTime : DateTime.now(),
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
      // Memory hygiene for big batches: on iOS, reading originBytes EXPORTS each
      // original to a tmp file — left unchecked a 10k run piles those up (disk +
      // RAM) and the OS kills us. Release them every batch. Processing is already
      // strictly one-at-a-time, so peak memory stays ~a single image.
      if (done % _cacheClearEvery == 0) {
        await PhotoManager.clearFileCache();
      }
      yield TaskProgress(progress: done / total, phase: '$done/$total');
    }

    await PhotoManager.clearFileCache();
    if (_cancelled) return;
    if (saved == 0) {
      throw StateError('No image was saved');
    }
    yield TaskProgress(progress: 1, phase: '$saved/$total');
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  @override
  Future<void> cleanup() async {}
}
