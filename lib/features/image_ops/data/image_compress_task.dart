import 'dart:async';

import 'package:photo_manager/photo_manager.dart';

import '../../../core/capabilities/format_capabilities.dart';
import '../../../core/diagnostics/media_diagnostics.dart';
import '../../../core/isolates/heavy_work.dart';
import '../../../core/isolates/media_task.dart';
import '../../../core/isolates/task_progress.dart';
import '../../settings/providers/preferences_providers.dart';
import '../domain/image_format_policy.dart';
import 'gallery_saver.dart';
import 'image_encoder.dart';
import 'output_name.dart';
import 'source_facts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ImageCompressTask — the actual compress/convert engine, run through the
// shared TaskRunner so it surfaces in the floating Tasks badge with progress +
// cancellation.
//
// Per asset: load original → inspect it once (alpha, HDR) → resolve the target format
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
  }) : id =
           'compress-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}',
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

  /// Requested bit depth; actual HDR preservation is not yet verified.
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
  // The encode's place in the heavy-work gate: a cancel withdraws it if it
  // has not started (RUN-02), instead of letting it run to be dropped.
  HeavyWorkTicket? _ticket;

  @override
  Stream<TaskEvent> run() async* {
    final total = assetIds.length;
    if (total == 0) {
      throw ArgumentError('No images selected');
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
          final facts = await SourceInspector.inspect(src);
          // A giant image gets JPEG or HEIC whatever the batch's format
          // (RUN-01); always at full size.
          final target = ImageFormatPolicy.resolve(
            choice: format,
            hasAlpha: facts.alpha,
            caps: _caps,
            giant: facts.giant,
          );
          if (_cancelled) return;
          try {
            encoded = await ImageEncoder.encode(
              source: src,
              target: target.format,
              allowFormatFallback: format == DefaultFormat.auto,
              quality: quality,
              facts: facts,
              keepMetadata: keepMetadata,
              keepOriginalTime: keepOriginalTime,
              bitDepth: bitDepth,
              ticket: _ticket = HeavyWorkTicket(),
            );
          } on HeavyWorkWithdrawn {
            return; // cancelled while it waited its turn
          } catch (_) {
            MediaDiagnostics.record(
              MediaBackend.taskRunner,
              MediaOperation.encode,
              MediaDiagnosticCode.exception,
            );
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
          creationDate: keepOriginalTime
              ? entity.createDateTime
              : DateTime.now(),
          latitude: keepMetadata ? entity.latitude : null,
          longitude: keepMetadata ? entity.longitude : null,
        );
        if (asset != null) {
          saved++;
          outputAssetIds.add(asset.id);
        }
      } catch (_) {
        MediaDiagnostics.record(
          MediaBackend.gallery,
          MediaOperation.save,
          MediaDiagnosticCode.exception,
        );
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
    if (saved != total) {
      MediaDiagnostics.record(
        MediaBackend.taskRunner,
        MediaOperation.task,
        MediaDiagnosticCode.incompleteBatch,
      );
    }
    if (saved == 0) {
      throw StateError('No image was saved');
    }
    yield TaskProgress(progress: 1, phase: '$saved/$total');
    if (saved != total) {
      throw IncompleteBatch(saved: saved, total: total);
    }
    yield const TaskSucceeded();
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    _ticket?.withdraw();
  }

  @override
  Future<void> cleanup() async {}
}
