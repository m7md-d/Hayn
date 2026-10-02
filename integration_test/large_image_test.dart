import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hayn/core/darklib/darklib.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/image_ops/data/source_facts.dart';
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
    final facts = await SourceInspector.inspect(source);
    for (final target in [
      DefaultFormat.jpeg,
      DefaultFormat.webp,
      DefaultFormat.png,
      DefaultFormat.heic,
      DefaultFormat.avif,
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
