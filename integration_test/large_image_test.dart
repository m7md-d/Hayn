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
import 'package:hayn/features/image_ops/data/source_facts.dart';
import 'package:hayn/features/image_ops/domain/image_format_policy.dart';
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
