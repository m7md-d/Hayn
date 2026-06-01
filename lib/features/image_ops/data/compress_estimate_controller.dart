import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../data/index/index_providers.dart';
import '../../settings/providers/preferences_providers.dart';
import '../domain/compress_estimator.dart';
import 'image_encoder.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CompressEstimateController — turns the pure CompressEstimator into a live, IO
// driven estimate for a (possibly huge) selection.
//
// Dynamic by batch size (so accuracy scales with how much we can afford):
//   • N ≤ 24      → sample EVERY item → essentially exact.
//   • 24 < N ≤ 400 → up to 24 stratified samples.
//   • N > 400      → up to 16 stratified samples.
// In every case a wall-clock budget caps sampling, so even 10k stays snappy and
// we never block on a stuck file.
//
// Each sample is measured WITHOUT a full encode: we downscale the original to
// two tiny sizes, encode both at the target settings, and fit a power law
// (bytes ∝ pixels^p) to extrapolate the full-resolution size — so a 48 MP photo
// costs two sub-128px encodes, not one giant one. Those measurements calibrate
// the per-stratum model (CompressEstimator.calibrate), and their timing yields a
// rough compress-time ETA. Everything is cancellable; the instant metadata prior
// shows first and refines live.
// ─────────────────────────────────────────────────────────────────────────────

class EstimateResult {
  const EstimateResult({
    required this.size,
    required this.refining,
    this.etaSeconds,
  });
  final SizeEstimate size;
  final bool refining; // still sampling
  final double? etaSeconds; // rough total compress time (null until measured)
}

class CompressEstimateController {
  CompressEstimateController(this.ref);
  final WidgetRef ref;

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  static const _budget = Duration(milliseconds: 1500);
  static const _scaleA = 128; // tiny proxy
  static const _scaleB = 256; // second scale for the power-law fit

  Future<void> run({
    required List<String> ids,
    required DefaultFormat target,
    required int quality,
    required void Function(EstimateResult) onUpdate,
  }) async {
    final facts = await ref.read(mediaIndexDatabaseProvider).estimateFactsFor(ids);
    if (_cancelled) return;
    if (facts.isEmpty) {
      onUpdate(const EstimateResult(
        size: SizeEstimate(low: 0, expected: 0, high: 0, confidence: 0),
        refining: false,
      ));
      return;
    }

    final items = [
      for (final f in facts)
        EstimateItem(
          pixels: f.width * f.height,
          sourceBytes: f.sizeBytes,
          family: SourceFamilyFromMime.of(f.mimeType, ext: _ext(f.title)),
        ),
    ];

    // 1) Instant metadata-only prior.
    var current = CompressEstimator.prior(items, target, quality);
    onUpdate(EstimateResult(size: current, refining: true));
    if (_cancelled) return;

    // 2) Dynamic sample budget, covering content strata.
    final n = items.length;
    final maxSamples = n <= 24 ? n : (n <= 400 ? 24 : 16);
    final indices = CompressEstimator.selectSampleIndices(items, maxSamples);

    final samples = <BppSample>[];
    final clock = Stopwatch()..start();
    var encMs = 0.0, encMp = 0.0;
    var didSelfTest = false;

    for (final i in indices) {
      if (_cancelled) return;
      if (samples.isNotEmpty && clock.elapsed > _budget) break;
      final m = await _sampleOne(facts[i], items[i], target, quality);
      if (_cancelled) return;
      if (m == null) continue;
      samples.add(BppSample(
        item: items[i],
        predicted:
            CompressEstimator.predictItemBytes(items[i], target, quality),
        actual: m.fullBytes,
      ));
      encMs += m.ms;
      encMp += m.proxyMp;
      current = CompressEstimator.calibrate(items, target, quality, samples);
      onUpdate(EstimateResult(
        size: current,
        refining: true,
        etaSeconds: _eta(items, encMs, encMp),
      ));

      // Debug accuracy self-test: once, encode the FIRST sampled item at FULL
      // resolution and log proxy-extrapolation vs reality, so accuracy can be
      // checked + tuned on a real device.
      if (kDebugMode && !didSelfTest) {
        didSelfTest = true;
        unawaited(_selfTest(facts[i], items[i], target, quality, m.fullBytes));
      }
    }

    if (_cancelled) return;
    onUpdate(EstimateResult(
      size: current,
      refining: false,
      etaSeconds: _eta(items, encMs, encMp),
    ));
  }

  /// Measure one item via two tiny proxies + a power-law extrapolation to full
  /// resolution. Returns null on any failure (the sample is just skipped).
  Future<({int fullBytes, double ms, double proxyMp})?> _sampleOne(
    ({String id, int width, int height, int sizeBytes, String? mimeType, String? title}) f,
    EstimateItem it,
    DefaultFormat target,
    int quality,
  ) async {
    try {
      final entity = await AssetEntity.fromId(f.id);
      final origin = await entity?.originBytes;
      if (origin == null || _cancelled) return null;
      final a = await _measureProxy(origin, f, target, quality, _scaleA);
      final b = await _measureProxy(origin, f, target, quality, _scaleB);
      if (a == null || b == null) return null;

      final full = it.pixels.toDouble();
      double fullBytes;
      if (b.pixels > a.pixels && a.bytes > 0 && b.bytes > 0) {
        // bytes ∝ pixels^p through the two points; clamp p to a sane range.
        final p = (math.log(b.bytes / a.bytes) / math.log(b.pixels / a.pixels))
            .clamp(0.5, 1.2);
        final coef = b.bytes / math.pow(b.pixels, p);
        fullBytes = coef * math.pow(full, p);
      } else {
        fullBytes = b.bytes * (full / b.pixels); // area fallback
      }
      return (
        fullBytes: fullBytes.round().clamp(1, 1 << 31),
        ms: a.ms + b.ms,
        proxyMp: (a.pixels + b.pixels) / 1e6,
      );
    } catch (_) {
      return null;
    }
  }

  Future<({double bytes, double pixels, double ms})?> _measureProxy(
    Uint8List origin,
    ({String id, int width, int height, int sizeBytes, String? mimeType, String? title}) f,
    DefaultFormat target,
    int quality,
    int scale,
  ) async {
    try {
      // Downscale to a tiny PNG (lossless), then encode at the target settings.
      final small = await fic.FlutterImageCompress.compressWithList(
        origin,
        minWidth: scale,
        minHeight: scale,
        format: fic.CompressFormat.png,
        quality: 100,
      );
      if (small.isEmpty || _cancelled) return null;
      final sw = Stopwatch()..start();
      final enc = await ImageEncoder.encode(
        source: small,
        target: target,
        quality: quality,
        hasAlpha: false,
        keepMetadata: false,
      );
      sw.stop();
      final s = math.min(scale / f.width, scale / f.height).clamp(0.0, 1.0);
      final px = (f.width * f.height) * s * s;
      return (
        bytes: enc.bytes.length.toDouble(),
        pixels: px <= 0 ? 1.0 : px,
        ms: sw.elapsedMicroseconds / 1000.0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Rough total compress time. Proxy throughput is overhead-heavy, so full-res
  /// runs slower per megapixel — scale it down. Best-effort; the band/ETA are
  /// labelled approximate in the UI.
  double? _eta(List<EstimateItem> items, double encMs, double encMp) {
    if (encMp <= 0 || encMs <= 0) return null;
    final proxyMpPerMs = encMp / encMs;
    final fullMpPerMs = proxyMpPerMs * 0.6;
    final totalMp = items.fold<double>(0, (s, it) => s + it.pixels / 1e6);
    if (fullMpPerMs <= 0) return null;
    return (totalMp / fullMpPerMs) / 1000.0; // seconds
  }

  Future<void> _selfTest(
    ({String id, int width, int height, int sizeBytes, String? mimeType, String? title}) f,
    EstimateItem it,
    DefaultFormat target,
    int quality,
    int proxyEstimatedFull,
  ) async {
    try {
      final origin = await (await AssetEntity.fromId(f.id))?.originBytes;
      if (origin == null) return;
      final real = await ImageEncoder.encode(
        source: origin,
        target: target,
        quality: quality,
        hasAlpha: false,
        keepMetadata: false,
      );
      final realBytes = real.bytes.length;
      final err = (proxyEstimatedFull - realBytes).abs() / realBytes * 100;
      debugPrint('hayn/estimate self-test: ${f.id} '
          'proxy→${proxyEstimatedFull}B vs real ${realBytes}B '
          '(${err.toStringAsFixed(1)}% off, ${target.techName} q$quality)');
    } catch (_) {
      // best effort
    }
  }

  static String _ext(String? title) {
    final t = title ?? '';
    final dot = t.lastIndexOf('.');
    return (dot >= 0 && dot < t.length - 1) ? t.substring(dot + 1) : '';
  }
}
