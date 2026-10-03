import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hayn/core/capabilities/format_capabilities.dart';
import 'package:hayn/core/darklib/darklib.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/region_image.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/image_ops/domain/image_format_policy.dart';
import 'package:hayn/features/image_ops/presentation/widgets/region_tiles.dart';
import 'package:hayn/features/library/presentation/full_res_image.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';

// RUN-01: time and peak memory of a ~200 MP photo converted at FULL size, as
// users with 200 MP cameras need (user decision 2026-10-02: no downscale and
// no refusal). Run by `HAYN_PERF_LARGE=1 tool/test_performance.sh`, on a
// physical phone only. It measures the code as it is, to size the work; it has
// no budgets yet. A step prints a line before it starts, so a run the system
// kills still shows where. Nothing touches the gallery.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final report = <String, Object?>{};
  tearDownAll(() => binding.reportData = {'large': report});

  testWidgets('Large: 200 MP photo between formats at full size', (_) async {
    expect(await DarkLibCore.ensureReady(), isTrue);
    report['device'] = {
      'model': const String.fromEnvironment('HAYN_DEVICE_MODEL'),
      'memTotalMb': _memTotalMb(),
    };
    final source = await _fixture('photo-200mp.jpg');
    final size = await _size(source);
    report['source'] = {
      'kb': source.length ~/ 1024,
      'size': '${size.$1}x${size.$2}',
      'rssMb': _mb(ProcessInfo.currentRss),
    };
    // What the viewer pays on zoom: Flutter decodes the original at full
    // size (no cache size), and the same at the 4096 px other previews use.
    for (final (name, width) in [
      ('displayFull', null),
      ('display4096', 4096),
    ]) {
      debugPrint('LARGE start $name');
      report[name] = await _peak(() async {
        final codec = await ui.instantiateImageCodec(
          source,
          targetWidth: width,
        );
        final frame = await codec.getNextFrame();
        final size = '${frame.image.width}x${frame.image.height}';
        frame.image.dispose();
        codec.dispose();
        return {'size': size};
      });
      debugPrint('LARGE done $name: ${report[name]}');
    }
    // The viewer's own provider on zoom, bounded (RUN-01).
    debugPrint('LARGE start viewerZoom');
    report['viewerZoom'] = await _peak(() async {
      final done = Completer<String>();
      final stream = fullResImage(source).resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener((info, _) {
        done.complete('${info.image.width}x${info.image.height}');
        info.dispose();
      }, onError: (e, _) => done.completeError(e));
      stream.addListener(listener);
      final size = await done.future;
      stream.removeListener(listener);
      return {'size': size};
    });
    debugPrint('LARGE done viewerZoom: ${report['viewerZoom']}');
    // The viewer reads by tiles instead (PERF-03): open, then every tile the
    // full-screen view needs at ×2 and at ×8 on the centre, as RegionTiles
    // plans them, all held at once. Nothing is decoded whole.
    debugPrint('LARGE start regionOpen');
    RegionImage? region;
    report['regionOpen'] = await _peak(() async {
      region = await RegionImage.open(source);
      return {'opened': region != null};
    });
    debugPrint('LARGE done regionOpen: ${report['regionOpen']}');
    if (region != null) {
      final view = ui.PlatformDispatcher.instance.views.first;
      final screen = view.physicalSize / view.devicePixelRatio;
      final image = Size(region!.width.toDouble(), region!.height.toDouble());
      final box = Size(screen.width, screen.width * image.height / image.width);
      for (final zoom in [2, 8]) {
        final name = 'regionZoom$zoom';
        debugPrint('LARGE start $name');
        report[name] = await _peak(() async {
          final seen = Size(screen.width / zoom, screen.height / zoom);
          final plan = planTiles(
            image: image,
            box: box,
            visible: Rect.fromCenter(
              center: box.center(Offset.zero),
              width: seen.width,
              height: seen.height,
            ).intersect(Offset.zero & box),
            screenPxPerLocal: zoom * view.devicePixelRatio,
            baseLongEdge: 1080,
          )!;
          // A row at a time, as RegionTiles asks.
          final rows = <int, List<PlannedTile>>{};
          for (final t in plan.tiles) {
            (rows[t.row] ??= []).add(t);
          }
          final tiles = <ui.Image>[];
          final pending = rows.values.toList();
          Future<void> decodeRow(List<PlannedTile> row) async {
            row.sort((a, b) => a.col.compareTo(b.col));
            final out = await region!.tiles(
              Rect.fromLTRB(
                row.first.rect.left,
                row.first.rect.top,
                row.last.rect.right,
                row.first.rect.bottom,
              ),
              [for (final t in row.skip(1)) t.rect.left],
              plan.sample,
            );
            tiles.addAll(out ?? const []);
          }

          // Two rows in flight, as RegionTiles keeps them.
          Future<void> worker() async {
            while (pending.isNotEmpty) {
              await decodeRow(pending.removeAt(0));
            }
          }

          await Future.wait([worker(), worker()]);
          for (final t in tiles) {
            t.dispose();
          }
          return {
            'sample': plan.sample,
            'tiles': plan.tiles.length,
            'decoded': tiles.length,
          };
        });
        debugPrint('LARGE done $name: ${report[name]}');
      }
      await region!.close();
    }
    final facts = await SourceInspector.inspect(source);
    // What the plan makes of it (RUN-01): giant, so Auto and a batch's WebP
    // resolve to HEIC/JPEG.
    final caps = FormatCapabilities.detect();
    report['plan'] = {
      'giant': facts.giant,
      for (final choice in [DefaultFormat.auto, DefaultFormat.webp])
        choice.name: ImageFormatPolicy.resolve(
          choice: choice,
          hasAlpha: facts.alpha,
          caps: caps,
          giant: facts.giant,
        ).format.name,
    };
    expect(facts.giant, isTrue);
    // The user's choice for giant images first (JPEG, HEIC: platform
    // encoders); PNG last, since its plugin path kills the app (2026-10-02).
    for (final target in [
      DefaultFormat.jpeg,
      DefaultFormat.heic,
      DefaultFormat.webp,
      DefaultFormat.avif,
      DefaultFormat.png,
    ]) {
      debugPrint('LARGE start ${target.name}');
      final before = ProcessInfo.currentRss;
      var peak = before;
      final sampler = Timer.periodic(const Duration(milliseconds: 20), (_) {
        final now = ProcessInfo.currentRss;
        if (now > peak) peak = now;
      });
      final sw = Stopwatch()..start();
      final row = <String, Object?>{'rssBeforeMb': _mb(before)};
      try {
        final out = await ImageEncoder.encode(
          source: source,
          target: target,
          quality: qualityIntFor(DefaultQuality.balanced),
          facts: facts,
          keepMetadata: true,
        );
        row['ms'] = sw.elapsedMilliseconds;
        final outSize = await _size(out.bytes);
        row.addAll({
          'format': out.format.name,
          'backend': out.backend?.name,
          'outKb': out.bytes.length ~/ 1024,
          'size': '${outSize.$1}x${outSize.$2}',
          'fullSize': outSize == size,
          'diagnostics': [for (final d in out.diagnostics) d.code.name],
        });
      } on ImageEncodingFailure catch (e) {
        row['ms'] = sw.elapsedMilliseconds;
        row['failed'] = [for (final d in e.diagnostics) d.code.name];
      } finally {
        sampler.cancel();
      }
      row['peakRssMb'] = _mb(peak);
      row['peakAboveBeforeMb'] = _mb(peak - before);
      report[target.name] = row;
      debugPrint('LARGE done ${target.name}: $row');
    }
  }, timeout: const Timeout(Duration(minutes: 60)));
}

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

/// Width and height from the header, without decoding the pixels.
Future<(int, int)> _size(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final size = (descriptor.width, descriptor.height);
  descriptor.dispose();
  buffer.dispose();
  return size;
}

int? _memTotalMb() {
  try {
    final line = File(
      '/proc/meminfo',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('MemTotal:'));
    return int.parse(line.split(RegExp(r'\s+'))[1]) ~/ 1024;
  } catch (_) {
    return null; // iOS has no /proc
  }
}

int _mb(int bytes) => bytes ~/ (1024 * 1024);

/// Runs [body], sampling RSS every 20 ms: its result plus time and peak.
Future<Map<String, Object?>> _peak(
  Future<Map<String, Object?>> Function() body,
) async {
  final before = ProcessInfo.currentRss;
  var peak = before;
  final sampler = Timer.periodic(const Duration(milliseconds: 20), (_) {
    final now = ProcessInfo.currentRss;
    if (now > peak) peak = now;
  });
  final sw = Stopwatch()..start();
  Map<String, Object?> row;
  try {
    row = await body();
  } catch (e) {
    row = {'failed': e.runtimeType.toString()};
  }
  sampler.cancel();
  return {
    ...row,
    'ms': sw.elapsedMilliseconds,
    'peakRssMb': _mb(peak),
    'peakAboveBeforeMb': _mb(peak - before),
  };
}
