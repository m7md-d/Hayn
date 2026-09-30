import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:hayn/app/app.dart';
import 'package:hayn/app/l10n/app_localizations.dart';
import 'package:hayn/app/shell/swipeable_tabs.dart';
import 'package:hayn/core/darklib/darklib.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/image_probe.dart';
import 'package:hayn/features/image_ops/data/platform_pixels.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/library/presentation/asset_detail_screen.dart';
import 'package:hayn/features/library/presentation/library_screen.dart';
import 'package:hayn/features/library/presentation/providers/library_provider.dart';
import 'package:hayn/features/library/presentation/widgets/id_thumbnail.dart';
import 'package:hayn/features/onboarding/providers/onboarding_provider.dart';
import 'package:hayn/features/settings/presentation/settings_screen.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';
import 'package:hayn/features/tools/presentation/tools_screen.dart';
import 'package:hayn/features/trash/presentation/trash_screen.dart';

// Responsiveness and media speed on a PHYSICAL phone (iOS or Android). A
// simulator or emulator runs on the host's hardware, so its numbers describe
// nothing a user holds; tool/test_performance.sh refuses them. Profile mode.
//
// The library tests browse the phone's own photo library and only time it:
// no pixels, names or metadata leave the app, and nothing is written to the
// library. Conversions run on the 12 MP fixture (docs/18-PERFORMANCE.md) and
// never reach the gallery. Budgets live in [_budget]; the report carries
// every measurement, including the ones that stay within budget.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Frames come when the engine and the app ask for them, as in real use;
  // pump() only waits.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;

  setUpAll(() async {
    expect(
      Platform.environment.containsKey('SIMULATOR_DEVICE_NAME'),
      isFalse,
      reason: 'Performance runs on a physical phone only',
    );
    expect(await DarkLibCore.ensureReady(), isTrue);
    final view = binding.platformDispatcher.views.first;
    final photos = await PhotoManager.requestPermissionExtend();
    _report['device'] = {
      'model': const String.fromEnvironment('HAYN_DEVICE_MODEL'),
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'refreshHz': view.display.refreshRate,
      'logicalSize': [
        (view.physicalSize.width / view.devicePixelRatio).round(),
        (view.physicalSize.height / view.devicePixelRatio).round(),
      ],
      'devicePixelRatio': view.devicePixelRatio,
      'photoPermission': photos.name,
    };
  });

  tearDownAll(
    () => binding.reportData = {
      'performance': _report,
      'overBudget': _overBudget,
      'maxRssMb': _mb(ProcessInfo.maxRss),
    },
  );

  testWidgets('Library: mount to first screen of thumbnails', (tester) async {
    final r = _section('library.mount');
    final mount = Stopwatch()..start();
    await tester.pumpWidget(_app());
    await _waitFor(tester, () => _has(find.byType(LibraryScreen)));
    r['firstFrameMs'] = _ms(mount.elapsed);
    await _waitFor(
      tester,
      () => _library(tester).entries.isNotEmpty || _libraryEmpty(tester),
      timeout: const Duration(seconds: 30),
    );
    final entries = _library(tester).entries.length;
    r['firstPageItems'] = entries;
    if (entries == 0) {
      r['skipped'] = 'Photo library is empty or not accessible';
    } else {
      await _waitFor(tester, () => _thumbs(tester).complete);
      r['thumbnailsMs'] = _ms(mount.elapsed);
      r['visibleThumbnails'] = _thumbs(tester).visible;
      _check(r, 'thumbnailsMs', _budget.firstThumbnailsMs);
    }
    await _librarySettled(tester);
    r['libraryItems'] = _library(tester).entries.length;
    await _unmount(tester);
    _expectWithinBudget(r);
  });

  testWidgets('Library: slow scroll and fast fling', (tester) async {
    final r = _section('library.scroll');
    await _mountLibrary(tester);
    final entries = _library(tester).entries.length;
    r['libraryItems'] = entries;
    if (entries < _minLibraryItems) {
      r['skipped'] = 'Needs at least $_minLibraryItems items, has $entries';
      await _unmount(tester);
      return;
    }
    final grid = _grid(tester);
    final target = find.byType(LibraryScreen);

    // A reading pace: four drags of 600 px, 0.8 s each.
    r['slow'] = await _frames(() async {
      for (var i = 0; i < 4; i++) {
        await tester.timedDrag(
          target,
          const Offset(0, -600),
          const Duration(milliseconds: 800),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await _idle(tester, grid);
    });
    _checkFrames(r, 'slow');

    // Flicking through the library as fast as a thumb goes, then back.
    final before = grid.position.pixels;
    r['fling'] = await _frames(() async {
      for (var i = 0; i < 8; i++) {
        await tester.fling(target, const Offset(0, -500), 6000);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      await _idle(tester, grid);
    });
    r['flingDistancePx'] = (grid.position.pixels - before).round();
    _checkFrames(r, 'fling');
    final fill = Stopwatch()..start();
    await _waitFor(tester, () => _thumbs(tester).complete);
    r['thumbnailsAfterFlingMs'] = _ms(fill.elapsed);
    _check(r, 'thumbnailsAfterFlingMs', _budget.thumbnailsAfterScrollMs);

    r['flingBack'] = await _frames(() async {
      for (var i = 0; i < 8; i++) {
        await tester.fling(target, const Offset(0, 500), 6000);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      await _idle(tester, grid);
    });
    _checkFrames(r, 'flingBack');
    await _unmount(tester);
    _expectWithinBudget(r);
  });

  testWidgets('Viewer: open a photo, swipe through, close', (tester) async {
    final r = _section('viewer');
    await _mountLibrary(tester);
    final entries = _library(tester).entries.length;
    r['libraryItems'] = entries;
    if (entries < 12) {
      r['skipped'] = 'Needs at least 12 items, has $entries';
      await _unmount(tester);
      return;
    }
    final tile = _visibleTiles(
      tester,
    )[math.min(4, _visibleTiles(tester).length - 1)];

    r['open'] = await _frames(() async {
      final open = Stopwatch()..start();
      await tester.tapAt(tile.center);
      await _waitFor(tester, () => _has(find.byType(AssetDetailScreen)));
      r['openFirstFrameMs'] = _ms(open.elapsed);
      await _waitFor(tester, () => _routeSettled(tester, AssetDetailScreen));
      r['openSettledMs'] = _ms(open.elapsed);
    });
    _check(r, 'openFirstFrameMs', _budget.responseMs);
    _checkFrames(r, 'open');

    final pager = _detailPager(tester);
    // Swipe toward later photos. RTL reverses the pager, so the direction is
    // learnt from the first swipe that moves. The synthetic fling moves the
    // page past its midpoint on release, when the viewer switches the active
    // photo; the clock starts there and stops when the centred image is the
    // 1080 px one of the NEW page.
    var dx = -300.0;
    final sharp = <int>[];
    var blurry = 0;
    // Why a swipe missed the sharp image: the page type and the long edge
    // shown after 3 s. Numbers only; nothing about the photo itself.
    final missed = <String>[];
    r['swipes'] = await _frames(() async {
      for (var i = 0; i < 14 && sharp.length + blurry < 10; i++) {
        final from = pager.page!.round();
        await tester.fling(find.byType(AssetDetailScreen), Offset(dx, 0), 1500);
        final released = Stopwatch()..start();
        final to = pager.page!.round();
        if (to == from) {
          await _idle(tester, pager.position);
          dx = -dx; // wrong way at an end of the library
          continue;
        }
        if (to < from) dx = -dx; // went backwards; next swipes go forward
        try {
          await _waitFor(
            tester,
            () =>
                (pager.page! - to).abs() < .5 &&
                _centreImageEdge(tester) >= _sharpEdge,
            timeout: const Duration(seconds: 3),
          );
          sharp.add(_ms(released.elapsed));
        } on TimeoutException {
          blurry++;
          final video = _library(tester).entries[to].isVideo;
          missed.add(
            '${video ? 'video' : 'photo'}:${_centreImageEdge(tester)}px',
          );
        }
        await _idle(tester, pager.position);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    });
    _checkFrames(r, 'swipes');
    r['sharpAfterSwipeMs'] = _stats(sharp);
    r['notSharpWithin3s'] = blurry;
    r['notSharpPages'] = missed;
    if (sharp.isNotEmpty) {
      r['sharpAfterSwipeP90Ms'] = _percentile(sharp, .9);
      _check(r, 'sharpAfterSwipeP90Ms', _budget.sharpAfterSwipeMs);
    }

    r['close'] = await _frames(() async {
      final close = Stopwatch()..start();
      GoRouter.of(tester.element(find.byType(AssetDetailScreen))).pop();
      await _waitFor(tester, () => !_has(find.byType(AssetDetailScreen)));
      r['closeMs'] = _ms(close.elapsed);
    });
    _checkFrames(r, 'close');
    await _unmount(tester);
    _expectWithinBudget(r);
  });

  testWidgets('Navigation: tabs by tap and swipe, pushed screens', (
    tester,
  ) async {
    final r = _section('navigation');
    await _mountLibrary(tester);
    final l = AppLocalizations.of(tester.element(find.byType(LibraryScreen)));
    final taps = <String, IconData>{
      'tools': Icons.construction_outlined,
      'settings': Icons.settings_outlined,
      'library': Icons.photo_library_outlined,
    };
    final pages = {'library': 0, 'tools': 1, 'settings': 2};
    r['tabTaps'] = await _frames(() async {
      for (final e in taps.entries) {
        final tabs = _tabsPager(tester);
        final start = tabs.position.pixels;
        final sw = Stopwatch()..start();
        await tester.tap(_navIcon(e.value));
        await _waitFor(tester, () => tabs.position.pixels != start);
        r['${e.key}ResponseMs'] = _ms(sw.elapsed);
        _check(r, '${e.key}ResponseMs', _budget.responseMs);
        await _waitFor(
          tester,
          () => tabs.page == pages[e.key] && !_scrolling(tabs.position),
        );
        r['${e.key}SettledMs'] = _ms(sw.elapsed);
      }
    });
    _checkFrames(r, 'tabTaps');

    // Library → Tools → back, by dragging the pager as a thumb would.
    final tabs = _tabsPager(tester);
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final rtl =
        Directionality.of(tester.element(find.byType(SwipeableTabs))) ==
        TextDirection.rtl;
    final forward = Offset(rtl ? width * .6 : -width * .6, 0);
    r['tabSwipes'] = await _frames(() async {
      for (final offset in [forward, -forward, forward, -forward]) {
        await tester.timedDrag(
          find.byType(SwipeableTabs),
          offset,
          const Duration(milliseconds: 250),
        );
        await _idle(tester, tabs.position);
      }
    });
    _checkFrames(r, 'tabSwipes');

    // Settings → Trash → back: a pushed full-screen route.
    await tester.tap(_navIcon(Icons.settings_outlined));
    await _waitFor(tester, () => tabs.page == 2 && !_scrolling(tabs.position));
    r['trash'] = await _frames(() async {
      final push = Stopwatch()..start();
      await tester.tap(find.text(l.settingsTrashCell));
      await _waitFor(tester, () => _has(find.byType(TrashScreen)));
      r['trashFirstFrameMs'] = _ms(push.elapsed);
      await _waitFor(tester, () => _routeSettled(tester, TrashScreen));
      r['trashSettledMs'] = _ms(push.elapsed);
      GoRouter.of(tester.element(find.byType(TrashScreen))).pop();
      await _waitFor(tester, () => !_has(find.byType(TrashScreen)));
    });
    _check(r, 'trashFirstFrameMs', _budget.responseMs);
    _checkFrames(r, 'trash');
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(ToolsScreen, skipOffstage: false), findsOneWidget);
    await _unmount(tester);
    _expectWithinBudget(r);
  });

  // Each source converted to each target as the compress screen does it
  // (quality "balanced", metadata kept). WebP and AVIF sources are this
  // test's own outputs from the JPEG, so the JPEG row runs first.
  testWidgets('Conversion: 12 MP photo between formats', (tester) async {
    final r = _section('conversion');
    const targets = [
      DefaultFormat.jpeg,
      DefaultFormat.heic,
      DefaultFormat.webp,
      DefaultFormat.avif,
      DefaultFormat.png,
    ];
    final sources = <String, Uint8List>{
      'jpeg': await _fixture('photo-12mp.jpg'),
      'heic': await _fixture('photo-12mp.heic'),
      'png': await _fixture('photo-12mp.png'),
    };
    await _warmUp(targets);
    for (final name in ['jpeg', 'heic', 'png', 'webp', 'avif']) {
      final source = sources[name];
      if (source == null) {
        r[name] = {'skipped': 'No $name output from the JPEG row'};
        continue;
      }
      final row = <String, Object?>{'sourceKb': source.length ~/ 1024};
      for (final target in targets) {
        final sw = Stopwatch()..start();
        try {
          final facts = await SourceInspector.inspect(source);
          final out = await ImageEncoder.encode(
            source: source,
            target: target,
            quality: qualityIntFor(DefaultQuality.balanced),
            facts: facts,
            keepMetadata: true,
          );
          final ms = _ms(sw.elapsed);
          expect(ImageProbe.sniff(out.bytes).name, _sniffName(out.format));
          row[target.name] = {
            'ms': ms,
            'outKb': out.bytes.length ~/ 1024,
            'format': out.format.name,
            'backend': out.backend?.name,
            'rssMb': _mb(ProcessInfo.currentRss),
          };
          if (name == 'jpeg' &&
              (target == DefaultFormat.webp || target == DefaultFormat.avif) &&
              out.format == target) {
            sources[target.name] = out.bytes;
          }
        } on ImageEncodingFailure catch (e) {
          row[target.name] = {
            'failed': [for (final d in e.diagnostics) d.code.name],
          };
        }
      }
      r[name] = row;
    }
    // Keep the decode test's inputs.
    _converted
      ..clear()
      ..addAll(sources);
  }, timeout: const Timeout(Duration(minutes: 40)));

  // What the viewer pays to show each format: Flutter's own decode at full
  // size and at the 1080 px the viewer uses, and the app's display path
  // (Android's ImageDecoder bridge for AVIF/HEIC, IMG-13).
  testWidgets('Decode: 12 MP photo per format', (tester) async {
    final r = _section('decode');
    final sources = _converted.isNotEmpty
        ? _converted
        : {'jpeg': await _fixture('photo-12mp.jpg')};
    for (final e in sources.entries) {
      final row = <String, Object?>{};
      Future<List<int>> time(Future<void> Function() decode) async {
        final runs = <int>[];
        for (var i = 0; i < 3; i++) {
          final sw = Stopwatch()..start();
          await decode();
          runs.add(_ms(sw.elapsed));
        }
        return runs;
      }

      Future<void> flutter(Uint8List bytes, {int? width}) async {
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
        final frame = await codec.getNextFrame();
        frame.image.dispose();
        codec.dispose();
      }

      try {
        row['flutterFullMs'] = _stats(await time(() => flutter(e.value)));
        row['flutter1080Ms'] = _stats(
          await time(() => flutter(e.value, width: 1080)),
        );
      } catch (err) {
        row['flutterFailed'] = '$err';
      }
      if (PlatformPixels.needsBridge(e.value)) {
        row['appDisplayMs'] = _stats(
          await time(() async {
            final shown = await PlatformPixels.forDisplay(
              e.value,
              maxEdge: 4096,
            );
            await flutter(shown);
          }),
        );
      }
      r[e.key] = row;
    }
  });
}

// ── Budgets ────────────────────────────────────────────────────────────────

/// Initial targets (docs/18-PERFORMANCE.md). Frame budgets follow the
/// display's refresh rate; the rest are wall-clock milliseconds.
const _budget = (
  /// Share of frames whose build or raster phase overran one refresh period.
  overBudgetFramesPct: 5.0,
  firstThumbnailsMs: 1500,
  thumbnailsAfterScrollMs: 500,
  responseMs: 100,
  sharpAfterSwipeMs: 500,
);

/// Fewer items than this cannot fill eight flings.
const _minLibraryItems = 300;

/// The viewer's crisp image is 1080 px on its long edge; its placeholder 360.
const _sharpEdge = 1000;

// ── Report ─────────────────────────────────────────────────────────────────

final _report = <String, Object?>{};
final _overBudget = <String>[];
final _converted = <String, Uint8List>{};

Map<String, Object?> _section(String name) =>
    _report[name] = <String, Object?>{};

void _flag(Map<String, Object?> r, String message) =>
    ((r['overBudget'] ??= <String>[]) as List<String>).add(message);

void _check(Map<String, Object?> r, String key, num budget) {
  final value = r[key] as num?;
  if (value != null && value > budget) _flag(r, '$key: $value > $budget');
}

void _checkFrames(Map<String, Object?> r, String key) {
  final f = r[key]! as Map<String, Object?>;
  final pct = f['overBudgetPct'] as num?;
  if (pct != null && pct > _budget.overBudgetFramesPct) {
    _flag(
      r,
      '$key frames over ${f['budgetMs']} ms: $pct% > '
      '${_budget.overBudgetFramesPct}%',
    );
  }
}

void _expectWithinBudget(Map<String, Object?> r) {
  final over = (r['overBudget'] as List<String>?) ?? const [];
  _overBudget.addAll(over);
  expect(over, isEmpty, reason: 'Over budget');
}

int _ms(Duration d) => d.inMilliseconds;
int _mb(int bytes) => bytes ~/ (1024 * 1024);

int _percentile(List<int> values, double p) {
  final sorted = [...values]..sort();
  return sorted[((sorted.length - 1) * p).round()];
}

Map<String, Object?> _stats(List<int> values) => values.isEmpty
    ? const {}
    : {
        'runs': values,
        'median': _percentile(values, .5),
        'max': values.reduce(math.max),
      };

// ── Frames ─────────────────────────────────────────────────────────────────

/// Frame timings while [action] runs. The engine hands them over in batches,
/// so older ones are flushed first and the last batch is awaited after.
Future<Map<String, Object?>> _frames(Future<void> Function() action) async {
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  final timings = <ui.FrameTiming>[];
  void watch(List<ui.FrameTiming> t) => timings.addAll(t);
  SchedulerBinding.instance.addTimingsCallback(watch);
  final sw = Stopwatch()..start();
  try {
    await action();
  } finally {
    sw.stop();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    SchedulerBinding.instance.removeTimingsCallback(watch);
  }
  return _summarize(timings, sw.elapsed);
}

Map<String, Object?> _summarize(List<ui.FrameTiming> frames, Duration took) {
  final hz = SchedulerBinding
      .instance
      .platformDispatcher
      .views
      .first
      .display
      .refreshRate;
  final budgetUs = 1e6 / hz;
  if (frames.isEmpty) return {'frames': 0, 'actionMs': _ms(took)};
  List<int> us(Duration Function(ui.FrameTiming) f) =>
      [for (final t in frames) f(t).inMicroseconds]..sort();
  final build = us((t) => t.buildDuration);
  final raster = us((t) => t.rasterDuration);
  final worst = [
    for (final t in frames)
      math.max(t.buildDuration.inMicroseconds, t.rasterDuration.inMicroseconds),
  ]..sort();
  double ms(int v) => (v / 100).round() / 10;
  int p(List<int> s, double q) => s[((s.length - 1) * q).round()];
  final over = worst.where((w) => w > budgetUs).length;
  final starts = [
    for (final t in frames) t.timestampInMicroseconds(ui.FramePhase.vsyncStart),
  ]..sort();
  final span = starts.last - starts.first;
  return {
    'frames': frames.length,
    'actionMs': _ms(took),
    'refreshHz': hz,
    'budgetMs': ms(budgetUs.round()),
    'fps': span > 0 ? ((frames.length - 1) * 1e6 / span).round() : null,
    'buildP50Ms': ms(p(build, .5)),
    'buildP90Ms': ms(p(build, .9)),
    'buildP99Ms': ms(p(build, .99)),
    'buildMaxMs': ms(build.last),
    'rasterP50Ms': ms(p(raster, .5)),
    'rasterP90Ms': ms(p(raster, .9)),
    'rasterP99Ms': ms(p(raster, .99)),
    'rasterMaxMs': ms(raster.last),
    'overBudget': over,
    'overBudgetPct': (over * 1000 / frames.length).round() / 10,
    'overTwiceBudget': worst.where((w) => w > 2 * budgetUs).length,
  };
}

// ── App ────────────────────────────────────────────────────────────────────

Widget _app() => ProviderScope(
  overrides: [
    onboardingCompletedProvider.overrideWith(
      () => OnboardingNotifier(initial: true),
    ),
  ],
  child: const HaynApp(),
);

Future<void> _mountLibrary(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  await _waitFor(tester, () => _has(find.byType(LibraryScreen)));
  await _waitFor(
    tester,
    () => _library(tester).entries.isNotEmpty || _libraryEmpty(tester),
    timeout: const Duration(seconds: 30),
  );
  if (_library(tester).entries.isNotEmpty) {
    await _waitFor(tester, () => _thumbs(tester).complete);
  }
  await _librarySettled(tester);
}

/// The first page (100 items) comes before the index spine that spans the
/// whole library; wait until the count holds still for two seconds.
Future<void> _librarySettled(WidgetTester tester) async {
  var count = -1;
  final still = Stopwatch();
  await _waitFor(tester, () {
    final s = _library(tester);
    if (s.isLoading || s.entries.length != count) {
      count = s.entries.length;
      still
        ..reset()
        ..start();
    }
    return still.elapsed > const Duration(seconds: 2);
  }, timeout: const Duration(seconds: 60));
}

Future<void> _unmount(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await Future<void>.delayed(const Duration(milliseconds: 300));
}

LibraryState _library(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(LibraryScreen)),
).read(libraryProvider);

bool _libraryEmpty(WidgetTester tester) {
  final s = _library(tester);
  return !s.isLoading &&
      (s.permissionStatus == LibraryPermissionStatus.denied ||
          (s.permissionStatus != LibraryPermissionStatus.unknown &&
              s.entries.isEmpty));
}

bool _has(Finder f) => f.evaluate().isNotEmpty;

/// Polls every 4 ms. The condition reads the widget tree, so the time is the
/// frame that built the change; its raster follows within one frame.
Future<void> _waitFor(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final sw = Stopwatch()..start();
  while (!done()) {
    if (sw.elapsed > timeout) {
      throw TimeoutException('Condition not met', timeout);
    }
    await tester.pump(const Duration(milliseconds: 4));
  }
}

bool _scrolling(ScrollPosition p) =>
    p.isScrollingNotifier.value || p.activity is! IdleScrollActivity;

Future<void> _idle(WidgetTester tester, Object pager) async {
  final position = pager is ScrollPosition
      ? pager
      : (pager as ScrollableState).position;
  await _waitFor(tester, () => !_scrolling(position));
}

bool _routeSettled(WidgetTester tester, Type screen) {
  final route = ModalRoute.of(tester.element(find.byType(screen)));
  return route?.animation?.status == AnimationStatus.completed;
}

ScrollableState _grid(WidgetTester tester) => tester
    .stateList<ScrollableState>(
      find.descendant(
        of: find.byType(LibraryScreen),
        matching: find.byType(Scrollable),
      ),
    )
    .firstWhere((s) => s.position.axis == Axis.vertical);

PageController _detailPager(WidgetTester tester) => tester
    .widget<PageView>(
      find
          .descendant(
            of: find.byType(AssetDetailScreen),
            matching: find.byType(PageView),
          )
          .first,
    )
    .controller!;

PageController _tabsPager(WidgetTester tester) => tester
    .widget<PageView>(
      find
          .descendant(
            of: find.byType(SwipeableTabs),
            matching: find.byType(PageView),
          )
          .first,
    )
    .controller!;

Finder _navIcon(IconData icon) => find.descendant(
  of: find.byKey(const ValueKey('nav-bar')),
  matching: find.byIcon(icon),
);

Rect _screen(WidgetTester tester) =>
    Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

/// Grid tiles on screen, top to bottom.
List<Rect> _visibleTiles(WidgetTester tester) {
  final screen = _screen(tester);
  final rects = <Rect>[
    for (final e
        in find
            .descendant(
              of: find.byType(LibraryScreen),
              matching: find.byType(IdThumbnail),
            )
            .evaluate())
      if (e.renderObject case final RenderBox box
          when box.attached && box.hasSize)
        box.localToGlobal(Offset.zero) & box.size,
  ].where((r) => screen.deflate(1).contains(r.center)).toList();
  rects.sort((a, b) => a.top != b.top ? a.top.compareTo(b.top) : 0);
  return rects;
}

/// Grid thumbnails on screen, and how many already show decoded pixels.
({int visible, int loaded, bool complete}) _thumbs(WidgetTester tester) {
  final screen = _screen(tester);
  var visible = 0;
  var loaded = 0;
  for (final e
      in find
          .descendant(
            of: find.byType(LibraryScreen),
            matching: find.byType(IdThumbnail),
          )
          .evaluate()) {
    final box = e.renderObject;
    if (box is! RenderBox || !box.attached || !box.hasSize) continue;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (!rect.overlaps(screen)) continue;
    visible++;
    if (_showsPixels(e)) loaded++;
  }
  return (
    visible: visible,
    loaded: loaded,
    complete: visible > 0 && loaded == visible,
  );
}

bool _showsPixels(Element root) {
  var found = false;
  void visit(Element e) {
    if (found) return;
    final w = e.widget;
    if (w is RawImage && w.image != null) {
      found = true;
      return;
    }
    e.visitChildElements(visit);
  }

  visit(root);
  return found;
}

/// Long edge of the decoded image at the centre of the viewer, or 0.
int _centreImageEdge(WidgetTester tester) {
  final centre = _screen(tester).center;
  var edge = 0;
  for (final e
      in find
          .descendant(
            of: find.byType(AssetDetailScreen),
            matching: find.byType(RawImage),
          )
          .evaluate()) {
    final image = (e.widget as RawImage).image;
    final box = e.renderObject;
    if (image == null || box is! RenderBox || !box.attached) continue;
    if (!(box.localToGlobal(Offset.zero) & box.size).contains(centre)) continue;
    edge = math.max(edge, math.max(image.width, image.height));
  }
  return edge;
}

// ── Media ──────────────────────────────────────────────────────────────────

/// `http://127.0.0.1:<port>` on Android (adb reverse), `documents` on iOS
/// (copied into the app container by the script).
const _fixtureBase = String.fromEnvironment('HAYN_PERF_FIXTURES');

Future<Uint8List> _fixture(String name) async {
  expect(_fixtureBase, isNotEmpty, reason: 'Run via tool/test_performance.sh');
  if (_fixtureBase == 'documents') {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/perf-fixtures/$name').readAsBytes();
  }
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(
      Uri.parse('$_fixtureBase/$name'),
    )).close();
    expect(response.statusCode, HttpStatus.ok, reason: name);
    return await consolidateHttpClientResponseBytes(response);
  } finally {
    client.close();
  }
}

/// First use of each engine loads code and allocates pools; a small encode
/// per target keeps that out of the timed runs.
Future<void> _warmUp(List<DefaultFormat> targets) async {
  final src = await _fixture('photo-12mp.jpg');
  final small = await _downscale(src, 640);
  for (final t in targets) {
    try {
      await ImageEncoder.encode(
        source: small,
        target: t,
        quality: 80,
        facts: await SourceInspector.inspect(small),
        keepMetadata: true,
      );
    } on ImageEncodingFailure {
      // Reported by the timed run.
    }
  }
}

Future<Uint8List> _downscale(Uint8List bytes, int width) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
  final image = (await codec.getNextFrame()).image;
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  codec.dispose();
  return png!.buffer.asUint8List();
}

String _sniffName(DefaultFormat f) => switch (f) {
  DefaultFormat.jpeg || DefaultFormat.auto => 'jpeg',
  DefaultFormat.heic => 'heic',
  DefaultFormat.webp => 'webp',
  DefaultFormat.avif => 'avif',
  DefaultFormat.png => 'png',
};
