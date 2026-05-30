import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;
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
// ImageCropTask — applies the editor's rotate/flip/crop to the FULL-resolution
// original (not the preview), then re-encodes via the format tree and saves a
// new gallery asset. The pixel work (decode → bake EXIF orientation → rotate →
// flip → crop → PNG) runs in a background isolate so the UI never blocks; the
// lossless PNG intermediate then goes through the normal encoder so the output
// format follows policy and transparency is preserved.
//
// Cropping necessarily re-encodes (pixels change); we do it once at high
// quality, per the golden rule.
// ─────────────────────────────────────────────────────────────────────────────

class ImageCropTask extends MediaTask {
  ImageCropTask({
    required this.assetId,
    required this.rotationQuarters,
    required this.flipH,
    required this.flipV,
    required this.cropFraction,
    this.quality = 90,
    FormatCapabilities? caps,
  })  : id = 'crop-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}',
        _caps = caps ?? FormatCapabilities.detect();

  final String assetId;
  final int rotationQuarters; // 0..3, clockwise
  final bool flipH;
  final bool flipV;
  final Rect cropFraction; // 0..1 within the displayed (rotated) image
  final int quality;
  final FormatCapabilities _caps;

  @override
  final String id;

  @override
  TaskType get type => TaskType.crop;

  bool _cancelled = false;

  @override
  Stream<TaskProgress> run() async* {
    yield const TaskProgress(progress: 0, phase: '0/1');

    final entity = await AssetEntity.fromId(assetId);
    final src = await entity?.originBytes;
    if (entity == null || src == null) {
      throw StateError('Crop source unavailable');
    }
    if (_cancelled) return;

    // Pixel transform off the main isolate (package:image is pure Dart).
    final cropped = await Isolate.run(
      () => _transform(
        src,
        rotationQuarters,
        flipH,
        flipV,
        cropFraction.left,
        cropFraction.top,
        cropFraction.width,
        cropFraction.height,
      ),
    );
    if (cropped == null) throw StateError('Crop failed to decode');
    if (_cancelled) return;
    yield const TaskProgress(progress: 0.6, phase: 'encoding');

    final hasAlpha = await ImageProbe.hasAlpha(cropped);
    final target = ImageFormatPolicy.resolve(
      choice: DefaultFormat.auto,
      hasAlpha: hasAlpha,
      caps: _caps,
    );
    final encoded = await ImageEncoder.encode(
      source: cropped,
      target: target.format,
      quality: quality,
      hasAlpha: hasAlpha,
      keepMetadata: false, // cropped → original EXIF dims are stale
    );
    if (_cancelled) return;

    final saved = await GallerySaver.saveImage(
      encoded.bytes,
      filename: _outName(entity, encoded.extension),
      creationDate: entity.createDateTime,
      latitude: entity.latitude,
      longitude: entity.longitude,
    );
    if (saved == null) throw StateError('Crop save failed');
    yield const TaskProgress(progress: 1, phase: '1/1');
  }

  String _outName(AssetEntity entity, String ext) {
    final title = entity.title ?? 'image';
    final dot = title.lastIndexOf('.');
    final base = dot > 0 ? title.substring(0, dot) : title;
    return '${base}_crop.$ext';
  }

  @override
  Future<void> cancel() async => _cancelled = true;

  @override
  Future<void> cleanup() async {}
}

/// Top-level so it can run in `Isolate.run`. Applies orientation → rotate →
/// flips (matching the editor's display order) → crop, returns lossless PNG.
Uint8List? _transform(
  Uint8List src,
  int rotationQuarters,
  bool flipH,
  bool flipV,
  double fl,
  double ft,
  double fw,
  double fh,
) {
  var im = img.decodeImage(src);
  if (im == null) return null;
  im = img.bakeOrientation(im);
  if (rotationQuarters % 4 != 0) {
    im = img.copyRotate(im, angle: 90 * (rotationQuarters % 4));
  }
  if (flipH) im = img.flipHorizontal(im);
  if (flipV) im = img.flipVertical(im);

  final x = (fl * im.width).round().clamp(0, im.width - 1);
  final y = (ft * im.height).round().clamp(0, im.height - 1);
  final w = (fw * im.width).round().clamp(1, im.width - x);
  final h = (fh * im.height).round().clamp(1, im.height - y);
  im = img.copyCrop(im, x: x, y: y, width: w, height: h);
  return img.encodePng(im);
}
