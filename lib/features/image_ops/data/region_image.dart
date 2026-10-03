import 'dart:async';
import 'dart:io' show File;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/darklib/darklib.dart';
import '../../../core/diagnostics/media_diagnostics.dart';
import 'image_probe.dart';
import 'native_image_encoder.dart';

// One image read by regions for display (PERF-03, docs/23-LARGE-IMAGES.md §4):
// the zoomed viewer and the compare screen ask for the tiles in view, at the
// detail the zoom needs, and never decode a whole image to show it.
//
// Android only (`RegionDecoders.kt`). The platform decoder reads stored
// pixels, so the orientation goes with the call, from DarkLib's `inspect`; a
// HEIC also takes its profile's space, which Android's decoder ignores
// (IMG-21). Elsewhere, or for a file the platform cannot read by regions
// (AVIF on this phone, GIF), [open] returns null with the reason recorded,
// and the caller shows its bounded rendition instead: iOS is a Mac task
// (M-07).

class RegionImage {
  RegionImage._(this._id, this.width, this.height);

  /// A reader over platform decoder [id], for tests that answer the channel.
  @visibleForTesting
  RegionImage.forTest(int id, int width, int height)
    : this._(id, width, height);

  static const MethodChannel channel = MethodChannel('hayn/region');

  final int _id;

  /// Upright size, orientation applied.
  final int width;
  final int height;

  bool _closed = false;

  /// Whether this platform reads images by regions.
  static bool get available =>
      NativeImageEncoder.bakeBackend == MediaBackend.androidDecoder;

  /// A region reader over [bytes]; null when unavailable or unreadable.
  /// The caller closes it.
  static Future<RegionImage?> open(Uint8List bytes) async {
    if (!available) return null;
    File? file;
    try {
      final facts = await DarkLibCore.inspect(bytes);
      if (facts == null) {
        // Without DarkLib the orientation is unknown: tiles could be turned.
        return _unavailable(MediaDiagnosticCode.unavailable);
      }
      final space = ImageProbe.sniff(bytes) == SniffedFormat.heic
          ? await DarkLibCore.profileSpace(bytes)
          : null;
      final dir = await getTemporaryDirectory();
      file = File(
        '${dir.path}/hayn-region-${DateTime.now().microsecondsSinceEpoch}',
      );
      await file.writeAsBytes(bytes);
      final res = await channel.invokeMapMethod<String, Object?>('open', {
        'path': file.path,
        'orientation': facts.orientation,
        if (space != null)
          'space': Float32List.fromList([...space.toXyzD50, ...space.transfer]),
      });
      // The platform owns the file from here; it deletes it on failure too.
      file = null;
      final id = res?['id'], w = res?['width'], h = res?['height'];
      if (id is! int || w is! int || h is! int) {
        return _unavailable(MediaDiagnosticCode.unavailable);
      }
      return RegionImage._(id, w, h);
    } catch (_) {
      return _unavailable(MediaDiagnosticCode.exception);
    } finally {
      try {
        await file?.delete();
      } catch (_) {
        // A leftover in the cache directory is not a failed display.
      }
    }
  }

  static RegionImage? _unavailable(MediaDiagnosticCode code) {
    MediaDiagnostics.record(
      MediaBackend.androidRegion,
      MediaOperation.display,
      code,
    );
    return null;
  }

  /// The upright rectangle [rect] (full-size pixels, right and bottom
  /// exclusive) sampled down by [sample], a power of two. Null once closed
  /// or on failure.
  Future<ui.Image?> tile(Rect rect, int sample) async =>
      (await tiles(rect, const [], sample))?.firstOrNull;

  /// [row] decoded once, then cut at the full-size x positions [cuts] into
  /// tiles, left to right: a JPEG region costs the compressed data before
  /// it whatever its width, so a row of tiles costs about what one does.
  Future<List<ui.Image>?> tiles(Rect row, List<double> cuts, int sample) async {
    if (_closed) return null;
    List<Object?>? res;
    try {
      res = await channel.invokeListMethod<Object?>('tiles', {
        'id': _id,
        'rect': Int32List.fromList([
          row.left.round(),
          row.top.round(),
          row.right.round(),
          row.bottom.round(),
        ]),
        'cuts': Int32List.fromList([for (final x in cuts) x.round()]),
        'sample': sample,
      });
    } catch (_) {
      res = null;
    }
    if (_closed || res == null) return null;
    final out = <ui.Image>[];
    for (final t in res) {
      final m = t is Map ? t : null;
      final w = m?['width'], h = m?['height'], pixels = m?['pixels'];
      if (w is! int || h is! int || pixels is! Uint8List) {
        for (final image in out) {
          image.dispose();
        }
        return null;
      }
      final done = Completer<ui.Image>();
      // Premultiplied RGBA from Android's ARGB_8888, as rgba8888 expects.
      ui.decodeImageFromPixels(
        pixels,
        w,
        h,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      out.add(await done.future);
    }
    return out;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await channel.invokeMethod<void>('close', {'id': _id});
    } catch (_) {
      // The platform closes its oldest decoders past a few anyway.
    }
  }
}
