import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:hayn/app/app.dart';
import 'package:hayn/core/darklib/darklib.dart';
import 'package:hayn/features/image_ops/data/gallery_saver.dart';
import 'package:hayn/features/image_ops/data/native_image_encoder.dart';
import 'package:hayn/features/image_ops/data/region_image.dart';
import 'package:hayn/features/image_ops/presentation/compress_screen.dart';
import 'package:hayn/features/image_ops/presentation/widgets/region_tiles.dart';
import 'package:hayn/features/library/presentation/asset_detail_screen.dart';
import 'package:hayn/features/library/presentation/library_screen.dart';
import 'package:hayn/features/onboarding/providers/onboarding_provider.dart';
import 'package:hayn/shared/widgets/comparison_viewer.dart';

// The zoomed viewer and the compare screen on iOS (M-07, PERF-03): an AVIF is
// read by regions through DarkLib, every other format keeps its bounded
// decode. The real app, with images this test saves into Photos: the
// performance photo, a checkerboard whose 4 px squares the 1080 px rendition
// cannot show, and AVIF copies of both from DarkLib and at 8 bits. It opens
// only those, never the library's own photos.
//
// On the iPhone (profile, as tool/test_performance.sh runs; the saved images
// stay in its Photos, named hayn-region-*): copy photo-12mp.jpg and the two
// 8-bit AVIFs into Documents/preservation-fixtures with `devicectl device copy
// to`, then `flutter drive --profile --keep-app-running -d <id> --driver
// test_driver/integration_test.dart --target integration_test/ios_region_test.dart`.
// Artifacts land in Documents/preservation-results.
// On a simulator: tool/test_ios_preservation.sh integration_test/ios_region_test.dart
// with CARGO_PROFILE_DEV_OPT_LEVEL=3 (its debug build encodes AV1 for minutes).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final saved = <String, String>{}; // name → asset id
  final bytes = <String, Uint8List>{};

  setUpAll(() async {
    expect(Platform.isIOS, isTrue, reason: 'This suite requires iOS');
    expect(await DarkLibCore.ensureReady(), isTrue);
    final permission = await PhotoManager.requestPermissionExtend();
    expect(permission.isAuth, isTrue, reason: 'Runner must grant Photos');
    final photo = await _fixture('photo-12mp.jpg');
    final checker = _checkerboard(3600, 2700);
    Future<Uint8List> avif(Uint8List source, int quality) async =>
        (await DarkLibCore.transcode(
          source,
          format: DarkLibFormat.avif,
          quality: quality,
          keepMetadata: true,
        ))!.bytes;
    bytes['photo.jpg'] = photo;
    bytes['photo.avif'] = await avif(photo, 80);
    bytes['checker.jpg'] = checker;
    bytes['checker.avif'] = await avif(checker, 100);
    // DarkLib's AVIFs are 10-bit, which Photos makes no thumbnail for
    // (IMG-23), so the viewer never shows them. The same two images at 8 bits
    // (ravif 0.11.3, depth 8, quality 90, speed 8; made on the Mac) carry
    // the viewer and compare checks until DarkLib writes 8-bit.
    bytes['checker-8bit.avif'] = await _fixture('checker-8bit.avif');
    bytes['photo-8bit.avif'] = await _fixture('photo-8bit.avif');
    // A run saves into the owner's Photos on a phone: an earlier run's copy,
    // among the newest images, is used again instead of piling up.
    final newest = await (await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate)],
      ),
    )).first.getAssetListPaged(page: 0, size: 60);
    final earlier = {for (final a in newest) await a.titleAsync: a.id};
    for (final e in bytes.entries) {
      await _artifact(e.key, e.value);
      final filename = 'hayn-region-${e.key}';
      if (earlier[filename] case final id?) {
        saved[e.key] = id;
        continue;
      }
      final asset = await GallerySaver.saveImage(e.value, filename: filename);
      expect(asset, isNotNull, reason: 'Photos refused ${e.key}');
      saved[e.key] = asset!.id;
    }
    _log(
      'reused ${saved.values.where(earlier.containsValue).length} of '
      '${saved.length} images from an earlier run',
    );
  });

  // What Photos gives back for each saved file: the viewer and the compare
  // screen start from its thumbnail, the tiles from its original. Recorded
  // for all before any is judged: each needs a thumbnail, and an AVIF's
  // original must come back as saved (Photos adds to a JPEG's).
  testWidgets('Photos: thumbnails and originals of the saved files', (_) async {
    final wrong = <String>[];
    for (final e in saved.entries) {
      final entity = (await AssetEntity.fromId(e.value))!;
      String thumb;
      try {
        final t = await entity.thumbnailDataWithSize(
          const ThumbnailSize.square(1080),
        );
        thumb = t == null ? 'null' : '${t.length} bytes';
      } catch (error) {
        thumb = 'throws ${error.toString().split('\n').first}';
      }
      if (!thumb.endsWith('bytes')) wrong.add('${e.key}: no thumbnail');
      final origin = await entity.originBytes;
      final same = listEquals(origin, bytes[e.key]);
      if (!same && e.key.endsWith('.avif')) wrong.add('${e.key}: changed');
      final region = origin == null ? null : await RegionImage.open(origin);
      _log(
        'photos ${e.key}: thumbnail $thumb; original ${origin?.length} '
        'bytes${same ? '' : ' (changed)'}; region '
        '${region == null ? 'none' : '${region.width}x${region.height}'}',
      );
      await region?.close();
    }
    expect(wrong, isEmpty);
  });

  // Only AVIF has a reader on iOS; the rest return null and keep their
  // bounded decode. Put back together, the AVIF's tiles are what Apple's
  // own decoder shows: rav1d with its arm64 assembly against ImageIO.
  testWidgets('Region reader: AVIF opens, JPEG does not', (_) async {
    expect(await RegionImage.open(bytes['photo.jpg']!), isNull);
    expect(await RegionImage.open(bytes['checker.jpg']!), isNull);
    final whole = await _regionWhole(bytes['checker.avif']!);
    final imageIO = await NativeImageEncoder.bakeUpright(
      source: bytes['checker.avif']!,
      keepMetadata: false,
      keepOriginalTime: false,
    );
    // ImageIO writes a 10-bit AVIF out as a 16-bit PNG.
    final decoded = img
        .decodePng(imageIO!)!
        .convert(format: img.Format.uint8, numChannels: 4);
    _expectSameImage(
      _Shown(decoded.width, decoded.height, decoded.getBytes()),
      whole,
    );
    // The P3 photo: one band of tiles across it, compared on the host,
    // where ImageIO converts to sRGB (test_native/compare_region_tiles.swift).
    // A band, since a debug build carries 48 MB of tiles over FFI slowly.
    final region = (await RegionImage.open(bytes['photo.avif']!))!;
    final w = region.width;
    const top = 1280, height = 512;
    final band = await _read(
      (await region.tile(
        Rect.fromLTRB(0, top.toDouble(), w.toDouble(), top + height.toDouble()),
        1,
      ))!,
    );
    await region.close();
    expect((band.width, band.height), (w, height));
    await _artifact('photo-region-${w}x$height-at$top.rgba', band.rgba);
  });

  for (final name in [
    'checker-8bit.avif',
    'checker.jpg',
    'photo-8bit.avif',
    'photo.jpg',
  ]) {
    final tiled = name.endsWith('.avif');
    testWidgets('Viewer: $name zoomed ${tiled ? 'by tiles' : 'as before'}', (
      tester,
    ) async {
      await _openApp(tester);
      final router = GoRouter.of(tester.element(find.byType(LibraryScreen)));
      router.push('/asset/${Uri.encodeComponent(saved[name]!)}');
      await _waitFor(
        tester,
        () => find.byType(AssetDetailScreen).evaluate().isNotEmpty,
      );
      await _pumpFor(tester, const Duration(seconds: 2)); // hi-res settles
      final centre = tester.getCenter(find.byType(AssetDetailScreen));
      final sw = Stopwatch()..start();
      await tester.tapAt(centre);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(centre);
      await _pumpFor(tester, const Duration(milliseconds: 600)); // zoom anim
      expect(tester.takeException(), isNull);
      if (name.startsWith('checker')) {
        var score = (0, 0);
        for (var i = 0; i < 100; i++) {
          if (i > 0) await _pumpFor(tester, const Duration(milliseconds: 100));
          if (tiled && find.byType(RegionTiles).evaluate().isEmpty) continue;
          score = await _viewerScore(tester, tiled: tiled);
          if (score.$2 > 0 && score.$1 >= score.$2 * 0.98) break;
        }
        _log(
          'viewer $name: ${score.$1} of ${score.$2} squares right, '
          '${sw.elapsedMilliseconds} ms after the double tap',
        );
        expect(score.$2, greaterThan(100));
        expect(score.$1 / score.$2, greaterThan(0.98), reason: '$score');
      } else {
        await _pumpFor(tester, const Duration(seconds: 3));
      }
      expect(
        find.byType(RegionTiles).evaluate().length,
        tiled ? 1 : 0,
        reason: tiled ? 'AVIF reads by tiles' : 'no tiles for $name on iOS',
      );
      expect(tester.takeException(), isNull);
      router.pop();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(AssetDetailScreen), findsNothing);
      // The reader closed with the page: nothing of it in the cache.
      final dir = await getTemporaryDirectory();
      final left = [
        for (final f in dir.listSync())
          if (f.path.split('/').last.startsWith('darklib-region-') ||
              f.path.split('/').last.startsWith('hayn-region-'))
            f.path.split('/').last,
      ];
      expect(left, isEmpty, reason: 'left in the cache: $left');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  // The compare screen: "before" is the AVIF, read by tiles; "after" the
  // encode in the saved default format. Both show and zoom without error;
  // the "before" half must show every square.
  for (final name in ['checker-8bit.avif', 'checker.jpg']) {
    testWidgets('Compare: $name shows both panes and zooms', (tester) async {
      await _openApp(tester);
      final router = GoRouter.of(tester.element(find.byType(LibraryScreen)));
      router.push('/compress', extra: [saved[name]!]);
      final viewer = find.byType(HaynComparisonViewer);
      await _waitFor(tester, () => viewer.evaluate().isNotEmpty);
      // The encode is done once "after" has no progress indicator left.
      await _waitFor(
        tester,
        () => find
            .descendant(
              of: viewer,
              matching: find.byType(CircularProgressIndicator),
            )
            .evaluate()
            .isEmpty,
        timeout: const Duration(minutes: 2),
      );
      await _pumpFor(tester, const Duration(seconds: 1));
      final tiles = find.descendant(
        of: viewer,
        matching: find.byType(RegionTiles),
      );
      _log('compare $name: ${tiles.evaluate().length} tiled pane(s)');
      expect(
        tiles.evaluate().length,
        greaterThanOrEqualTo(name.endsWith('.avif') ? 1 : 0),
      );
      // Left of the split handle, which takes the taps on the middle.
      final r = tester.getRect(viewer);
      final at = Offset(r.left + r.width * 0.25, r.center.dy);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await _pumpFor(tester, const Duration(milliseconds: 600));
      var before = (0, 0), after = (0, 0);
      for (var i = 0; i < 100; i++) {
        if (i > 0) await _pumpFor(tester, const Duration(milliseconds: 100));
        (before, after) = await _compareScore(tester);
        if (before.$2 > 0 && before.$1 >= before.$2 * 0.98) break;
      }
      _log(
        'compare $name zoomed: before ${before.$1}/${before.$2}, '
        'after ${after.$1}/${after.$2}',
      );
      expect(tester.takeException(), isNull);
      expect(before.$2, greaterThan(30));
      if (name.endsWith('.avif')) {
        expect(before.$1 / before.$2, greaterThan(0.98), reason: '$before');
      }
      router.pop();
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(CompressScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

void _log(String line) => debugPrint('ios_region: $line');

Future<void> _openApp(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        onboardingCompletedProvider.overrideWith(
          () => OnboardingNotifier(initial: true),
        ),
      ],
      child: const HaynApp(),
    ),
  );
  await _waitFor(
    tester,
    () => find.byType(LibraryScreen).evaluate().isNotEmpty,
  );
}

/// Real time passes (decodes and FFI calls run) while frames pump.
Future<void> _pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    expect(DateTime.now().isBefore(end), isTrue, reason: 'timed out');
    await _pumpFor(tester, const Duration(milliseconds: 100));
  }
}

/// The squares of [_checkerboard] seen through the viewer: points on a
/// grid over the middle of the screen, mapped back to image pixels through
/// the image's frame (the zoom included), kept 1.5 px from a square's
/// edges. Right when a white square shows above 200 and a black one below
/// 55. [tiled] maps through the RegionTiles box, otherwise through the
/// bounded original's Image.
Future<(int, int)> _viewerScore(WidgetTester tester, {required bool tiled}) {
  final frame = tiled
      ? find.byType(RegionTiles)
      : find.descendant(
          of: find.byType(AssetDetailScreen),
          matching: find.byWidgetPredicate(
            (w) => w is Image && w.image is ResizeImage,
          ),
        );
  final page = tester.getRect(find.byType(AssetDetailScreen));
  final area = Rect.fromCenter(
    center: page.center,
    width: page.width * 0.6,
    height: page.height * 0.4,
  );
  return _score(tester, find.byType(AssetDetailScreen), frame.first, area);
}

/// The compare viewer's two halves, chrome left out: the labels at the
/// top, the split line and its handle in the middle.
Future<((int, int), (int, int))> _compareScore(WidgetTester tester) async {
  final viewer = find.byType(HaynComparisonViewer);
  final r = tester.getRect(viewer);
  final frames = find.descendant(
    of: viewer,
    matching: find.byType(RegionTiles),
  );
  // "before" maps through its tiles, "after" through the same matrix: the
  // panes share one frame, so the first tile box serves both.
  final frame = frames.evaluate().isNotEmpty
      ? frames.first
      : find.descendant(of: viewer, matching: find.byType(Image)).first;
  final top = r.top + r.height * 0.2, bottom = r.bottom - r.height * 0.1;
  final before = await _score(
    tester,
    viewer,
    frame,
    Rect.fromLTRB(r.left + 8, top, r.center.dx - 30, bottom),
    step: 2, // the panes are small: a denser grid
  );
  final after = await _score(
    tester,
    viewer,
    frame,
    Rect.fromLTRB(r.center.dx + 30, top, r.right - 8, bottom),
    step: 2,
  );
  return (before, after);
}

Future<(int, int)> _score(
  WidgetTester tester,
  Finder page,
  Finder frame,
  Rect area, {
  double step = 6,
}) async {
  final box = tester.renderObject<RenderBox>(frame);
  var boundary = tester.renderObject(page);
  // A RepaintBoundary's own capture: debugLayer is gone in profile.
  while (boundary is! RenderRepaintBoundary) {
    boundary = boundary.parent!;
  }
  final shotBox = boundary;
  final dpr = tester.view.devicePixelRatio;
  final shot = (await tester.runAsync(
    () async => _read(await shotBox.toImage(pixelRatio: dpr)),
  ))!;
  var right = 0, total = 0;
  for (var gy = area.top; gy < area.bottom; gy += step) {
    for (var gx = area.left; gx < area.right; gx += step) {
      final local = box.globalToLocal(Offset(gx, gy));
      final ix = local.dx * 3600 / box.size.width;
      final iy = local.dy * 2700 / box.size.height;
      if (ix < 0 || iy < 0 || ix >= 3600 || iy >= 2700) continue;
      // Squares' edges sit at 2 + 4k on both axes.
      double edge(double v) {
        final m = (v - 2) % 4;
        return m < 2 ? m : 4 - m;
      }

      if (edge(ix) < 1.5 || edge(iy) < 1.5) continue;
      final white = (((ix + 2) ~/ 4) + ((iy + 2) ~/ 4)).isOdd;
      final s = shotBox.globalToLocal(Offset(gx, gy)) * dpr;
      if (s.dx < 0 || s.dy < 0 || s.dx >= shot.width || s.dy >= shot.height) {
        continue;
      }
      final v = shot.pixel(s.dx.floor(), s.dy.floor())[0];
      total++;
      if (white ? v > 200 : v < 55) right++;
    }
  }
  return (right, total);
}

class _Shown {
  const _Shown(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;

  List<int> pixel(int x, int y) {
    final i = (y * width + x) * 4;
    return rgba.sublist(i, i + 4);
  }
}

Future<_Shown> _read(ui.Image image) async {
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  final shown = _Shown(image.width, image.height, data!.buffer.asUint8List());
  image.dispose();
  return shown;
}

/// [bytes] put back together from its full-size region tiles, straight
/// RGBA, upright.
Future<_Shown> _regionWhole(Uint8List bytes) async {
  final region = await RegionImage.open(bytes);
  expect(region, isNotNull, reason: 'no region reader');
  try {
    final w = region!.width, h = region.height;
    final rgba = Uint8List(w * h * 4);
    for (var y0 = 0; y0 < h; y0 += 512) {
      for (var x0 = 0; x0 < w; x0 += 512) {
        final rect = Rect.fromLTRB(
          x0.toDouble(),
          y0.toDouble(),
          (x0 + 512).clamp(0, w).toDouble(),
          (y0 + 512).clamp(0, h).toDouble(),
        );
        final tile = await _read((await region.tile(rect, 1))!);
        expect((tile.width, tile.height), (rect.width, rect.height));
        for (var y = 0; y < tile.height; y++) {
          rgba.setRange(
            ((y0 + y) * w + x0) * 4,
            ((y0 + y) * w + x0 + tile.width) * 4,
            tile.rgba,
            y * tile.width * 4,
          );
        }
      }
    }
    return _Shown(w, h, rgba);
  } finally {
    await region?.close();
  }
}

/// Same size and near-identical pixels.
void _expectSameImage(_Shown a, _Shown b) {
  expect((b.width, b.height), (a.width, a.height));
  var total = 0, samples = 0, worst = 0;
  for (var y = 0; y < a.height; y += 7) {
    for (var x = 0; x < a.width; x += 7) {
      final p = a.pixel(x, y), q = b.pixel(x, y);
      for (var c = 0; c < 3; c++) {
        final d = (p[c] - q[c]).abs();
        total += d;
        if (d > worst) worst = d;
        samples++;
      }
    }
  }
  _log(
    'region vs ImageIO: mean ${(total / samples).toStringAsFixed(2)}, '
    'max $worst',
  );
  expect(total / samples, lessThan(4));
}

/// A JPEG checkerboard of 4 px black and white squares, [w]×[h], shifted
/// 2 px off the 4 px grid.
Uint8List _checkerboard(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  for (final p in image) {
    final v = (((p.x + 2) ~/ 4) + ((p.y + 2) ~/ 4)).isOdd ? 255 : 0;
    p
      ..r = v
      ..g = v
      ..b = v;
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}

Future<Uint8List> _fixture(String name) async {
  final documents = await getApplicationDocumentsDirectory();
  return File('${documents.path}/preservation-fixtures/$name').readAsBytes();
}

Future<void> _artifact(String name, List<int> bytes) async {
  final documents = await getApplicationDocumentsDirectory();
  final directory = Directory('${documents.path}/preservation-results');
  await directory.create(recursive: true);
  await File('${directory.path}/$name').writeAsBytes(bytes);
}
