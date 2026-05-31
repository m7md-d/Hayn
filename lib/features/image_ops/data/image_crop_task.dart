import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'dart:ui' as ui;

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
import 'output_name.dart';

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

  @override
  String? get sourceAssetId => assetId;

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

    // Decode through the PLATFORM ENGINE (ui.instantiateImageCodec), which on
    // iOS natively decodes HEIC/HEIF (and JPEG/PNG/WebP) — package:image can't.
    // It also bakes EXIF orientation into the pixels, so the transform below
    // works in upright coordinates that match the on-screen preview. We get
    // raw RGBA + dimensions and hand those to the isolate for the pixel work.
    final decoded = await _decodeRgba(src);
    if (decoded == null) throw StateError('Crop failed to decode');
    if (_cancelled) return;

    // Pixel transform off the main isolate (package:image is pure Dart).
    // Copy fields into locals so the closure captures only sendable values
    // (Uint8List + primitives), never `this`.
    final rgba = decoded.rgba;
    final w = decoded.width;
    final h = decoded.height;
    final rq = rotationQuarters;
    final fh = flipH;
    final fv = flipV;
    final fl = cropFraction.left;
    final ft = cropFraction.top;
    final fw = cropFraction.width;
    final fhgt = cropFraction.height;
    final cropped = await Isolate.run(
      () => transformRgba(rgba, w, h, rq, fh, fv, fl, ft, fw, fhgt),
    );
    if (cropped == null) throw StateError('Crop failed to encode');
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
      filename: await outputFilename(entity, encoded.extension, suffix: 'crop'),
      creationDate: entity.createDateTime,
      latitude: entity.latitude,
      longitude: entity.longitude,
    );
    if (saved == null) throw StateError('Crop save failed');
    outputAssetIds.add(saved.id);
    yield const TaskProgress(progress: 1, phase: '1/1');
  }

  /// Decode [src] to raw RGBA + dimensions via the platform engine (handles
  /// HEIC on iOS, with EXIF orientation already applied). Null on failure.
  Future<({Uint8List rgba, int width, int height})?> _decodeRgba(
      Uint8List src) async {
    try {
      final codec = await ui.instantiateImageCodec(src);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = image.width;
      final h = image.height;
      image.dispose();
      codec.dispose();
      if (bd == null) return null;
      return (rgba: bd.buffer.asUint8List(), width: w, height: h);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cancel() async => _cancelled = true;

  @override
  Future<void> cleanup() async {}
}

/// Top-level so it can run in `Isolate.run`. Builds an image from raw RGBA
/// (the engine already applied EXIF orientation — no baking) then rotate →
/// flips (matching the editor's display order) → crop, returns lossless PNG.
/// Exposed (not private) so it's unit-testable with synthetic raw pixels.
Uint8List? transformRgba(
  Uint8List rgba,
  int width,
  int height,
  int rotationQuarters,
  bool flipH,
  bool flipV,
  double fl,
  double ft,
  double fw,
  double fh,
) {
  if (rgba.length < width * height * 4) return null;
  // Cheap opacity check on the raw alpha bytes. The engine always hands us
  // RGBA, but for an opaque photo (every alpha == 255) we drop the alpha so the
  // PNG → HEIC encode doesn't ship a useless alpha channel (which iOS warns
  // about and which doubles decode memory + grows the file).
  var opaque = true;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 255) {
      opaque = false;
      break;
    }
  }
  var im = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  if (opaque) im = im.convert(numChannels: 3);
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
