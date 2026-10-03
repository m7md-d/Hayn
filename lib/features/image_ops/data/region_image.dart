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
// Two readers behind one interface, by what the format allows:
// - AVIF, on every platform: DarkLib (`engine::codec::region`). A grid
//   decodes only the cells in view; one item is decoded once into raw files
//   in the cache directory, read back a tile at a time. Upright, sRGB.
// - JPEG, HEIF, PNG, WebP on Android: BitmapRegionDecoder
//   (`RegionDecoders.kt`). It reads stored pixels, so the orientation goes
//   with the call, from DarkLib's `inspect`; a HEIC also takes its profile's
//   space, which Android's decoder ignores (IMG-21).
// Anything else (those formats on iOS, M-07; GIF; a refused AVIF such as
// PQ) makes [RegionImage.open] return null with the reason recorded, and the
// caller shows its bounded rendition instead.

abstract class RegionImage {
  RegionImage();

  /// A reader over Android region decoder [id], for tests that answer
  /// [channel].
  @visibleForTesting
  factory RegionImage.forTest(int id, int width, int height) =
      _PlatformRegion._;

  /// Android's region decoders (`RegionDecoders.kt`).
  static const MethodChannel channel = MethodChannel('hayn/region');

  /// Upright size, orientation applied.
  int get width;
  int get height;

  /// A region reader over [bytes]; null when none reads it, recorded. The
  /// caller closes it.
  static Future<RegionImage?> open(Uint8List bytes) {
    if (ImageProbe.sniff(bytes) == SniffedFormat.avif) {
      return _DarkLibRegion.open(bytes);
    }
    if (NativeImageEncoder.bakeBackend != MediaBackend.androidDecoder) {
      return Future.value();
    }
    return _PlatformRegion.open(bytes);
  }

  /// The upright rectangle [rect] (full-size pixels, right and bottom
  /// exclusive) sampled down by [sample], a power of two. Null once closed
  /// or on failure.
  Future<ui.Image?> tile(Rect rect, int sample) async =>
      (await tiles(rect, const [], sample))?.firstOrNull;

  /// [row] decoded once, then cut at the full-size x positions [cuts] into
  /// tiles, left to right: a JPEG region costs the compressed data before
  /// it whatever its width, and a grid cell serves its whole row, so a row
  /// of tiles costs about what one does.
  Future<List<ui.Image>?> tiles(Rect row, List<double> cuts, int sample);

  Future<void> close();

  /// The bytes in a fresh file in the app's cache directory, for a reader
  /// that opens a path.
  static Future<File> _tempFile(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/hayn-region-${DateTime.now().microsecondsSinceEpoch}',
    );
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Premultiplied 8-bit RGBA tiles as images.
  static Future<List<ui.Image>> _images(
    Iterable<({int width, int height, Uint8List pixels})> tiles,
  ) async {
    final out = <ui.Image>[];
    for (final t in tiles) {
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        t.pixels,
        t.width,
        t.height,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      out.add(await done.future);
    }
    return out;
  }
}

/// AVIF through DarkLib, on every platform.
class _DarkLibRegion extends RegionImage {
  _DarkLibRegion(this._reader) : width = _reader.width, height = _reader.height;

  final RegionReader _reader;

  @override
  final int width;
  @override
  final int height;

  bool _closed = false;

  static Future<RegionImage?> open(Uint8List bytes) async {
    File? file;
    try {
      file = await RegionImage._tempFile(bytes);
      final reader = await DarkLibCore.openRegion(
        path: file.path,
        cacheDir: file.parent.path,
      );
      // DarkLib recorded why when it refused.
      return reader == null ? null : _DarkLibRegion(reader);
    } catch (_) {
      MediaDiagnostics.record(
        MediaBackend.darklib,
        MediaOperation.display,
        MediaDiagnosticCode.exception,
      );
      return null;
    } finally {
      try {
        await file?.delete(); // the reader holds the bytes
      } catch (_) {
        // A leftover in the cache directory is not a failed display.
      }
    }
  }

  @override
  Future<List<ui.Image>?> tiles(Rect row, List<double> cuts, int sample) async {
    if (_closed) return null;
    final res = await DarkLibCore.regionTiles(
      _reader,
      rect: [
        row.left.round(),
        row.top.round(),
        row.right.round(),
        row.bottom.round(),
      ],
      cuts: [for (final x in cuts) x.round()],
      sample: sample,
    );
    if (_closed || res == null) return null;
    return RegionImage._images(
      res.map((t) => (width: t.width, height: t.height, pixels: t.rgba)),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _reader.dispose(); // its cache files go with it
  }
}

/// Android's BitmapRegionDecoder (`RegionDecoders.kt`).
class _PlatformRegion extends RegionImage {
  _PlatformRegion._(this._id, this.width, this.height);

  final int _id;

  @override
  final int width;
  @override
  final int height;

  bool _closed = false;

  static Future<RegionImage?> open(Uint8List bytes) async {
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
      file = await RegionImage._tempFile(bytes);
      final res = await RegionImage.channel.invokeMapMethod<String, Object?>(
        'open',
        {
          'path': file.path,
          'orientation': facts.orientation,
          if (space != null)
            'space': Float32List.fromList([
              ...space.toXyzD50,
              ...space.transfer,
            ]),
        },
      );
      // The platform owns the file from here; it deletes it on failure too.
      file = null;
      final id = res?['id'], w = res?['width'], h = res?['height'];
      if (id is! int || w is! int || h is! int) {
        return _unavailable(MediaDiagnosticCode.unavailable);
      }
      return _PlatformRegion._(id, w, h);
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

  @override
  Future<List<ui.Image>?> tiles(Rect row, List<double> cuts, int sample) async {
    if (_closed) return null;
    List<Object?>? res;
    try {
      res = await RegionImage.channel.invokeListMethod<Object?>('tiles', {
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
    final tiles = <({int width, int height, Uint8List pixels})>[];
    for (final t in res) {
      final m = t is Map ? t : null;
      final w = m?['width'], h = m?['height'], pixels = m?['pixels'];
      if (w is! int || h is! int || pixels is! Uint8List) return null;
      tiles.add((width: w, height: h, pixels: pixels));
    }
    return RegionImage._images(tiles);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await RegionImage.channel.invokeMethod<void>('close', {'id': _id});
    } catch (_) {
      // The platform closes its oldest decoders past a few anyway.
    }
  }
}
