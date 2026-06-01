import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../data/index/index_providers.dart';
import '../../settings/providers/preferences_providers.dart';
import '../domain/compress_estimator.dart';
import 'image_encoder.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CompressEstimateController — live, MEMORY-SAFE estimate for a (possibly huge)
// selection.
//
// Memory matters: a full-resolution decode of a 48 MP photo is ~190 MB of RGBA,
// so sampling by full encodes (or by holding big intermediates) OOM-kills the
// app on a large batch. Instead we sample a PhotoKit-managed THUMBNAIL (decoded
// + downscaled natively, never the full image into Dart) at [_thumb] px and
// encode THAT at the target settings — light + bounded. The thumbnail is large
// enough (≈4 MP) to sit above the "tiny-proxy inflates detail" regime that made
// 256 px proxies ~3× too big at high quality.
//
//   • per-item full bytes ≈ fullPixels × (thumbBytes·8 / thumbPixels)  (bpp scale)
//   • ETA scales the real per-format thumbnail encode time up by the pixel ratio,
//     so a light WebP and a heavy AVIF get truthful, different times.
//
// Dynamic by N (≤24 → all; larger → up to [_maxSamples] stratified), capped by a
// wall-clock budget. Cancellable; the instant prior shows first, refines live.
// A debug self-test logs thumbnail-extrapolation vs a real full encode so the
// model can be tuned on real device content.
// ─────────────────────────────────────────────────────────────────────────────

class EstimateResult {
  const EstimateResult({
    required this.size,
    required this.refining,
    this.etaSeconds,
  });
  final SizeEstimate size;
  final bool refining;
  final double? etaSeconds;
}

class CompressEstimateController {
  CompressEstimateController(this.ref);
  final WidgetRef ref;

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  static const _budget = Duration(milliseconds: 2500);
  static const _maxSamples = 16;
  static const _thumb = 2048; // sampling thumbnail box (px)

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

    var current = CompressEstimator.prior(items, target, quality);
    onUpdate(EstimateResult(size: current, refining: true));
    if (_cancelled) return;

    final n = items.length;
    final cap = n <= 24 ? n : _maxSamples;
    final indices = CompressEstimator.selectSampleIndices(items, cap);

    final samples = <BppSample>[];
    final clock = Stopwatch()..start();
    var totalMs = 0.0, totalMp = 0.0;
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
      totalMs += m.fullMs;
      totalMp += items[i].pixels / 1e6;
      current = CompressEstimator.calibrate(items, target, quality, samples);
      onUpdate(EstimateResult(
        size: current,
        refining: true,
        etaSeconds: _eta(items, totalMs, totalMp),
      ));

      if (kDebugMode && !didSelfTest) {
        didSelfTest = true;
        unawaited(_selfTest(facts[i].id, items[i], target, quality, m.fullBytes));
      }
    }

    if (_cancelled) return;
    onUpdate(EstimateResult(
      size: current,
      refining: false,
      etaSeconds: _eta(items, totalMs, totalMp),
    ));
  }

  /// Encode a native THUMBNAIL (memory-light) and scale its bits-per-pixel up to
  /// the full image. Returns the extrapolated full bytes + an extrapolated full
  /// encode time. Null on failure (sample skipped).
  Future<({int fullBytes, double fullMs})?> _sampleOne(
    ({String id, int width, int height, int sizeBytes, String? mimeType, String? title}) f,
    EstimateItem it,
    DefaultFormat target,
    int quality,
  ) async {
    try {
      final entity = await AssetEntity.fromId(f.id);
      // PhotoKit decodes + downscales natively; we never pull the full image
      // into Dart, so memory stays bounded even for 48 MP originals.
      final thumb = await entity
          ?.thumbnailDataWithSize(const ThumbnailSize(_thumb, _thumb));
      if (thumb == null || thumb.isEmpty || _cancelled) return null;

      final sw = Stopwatch()..start();
      final enc = await ImageEncoder.encode(
        source: thumb,
        target: target,
        quality: quality,
        hasAlpha: false,
        keepMetadata: false,
      );
      sw.stop();
      if (enc.bytes.isEmpty) return null;

      final scale = math.min(_thumb / f.width, _thumb / f.height).clamp(0.0, 1.0);
      final thumbPx = (f.width * f.height) * scale * scale;
      if (thumbPx <= 0) return null;
      final bpp = enc.bytes.length * 8 / thumbPx;
      final fullBytes = (it.pixels * bpp / 8).round().clamp(1, 1 << 31);
      // Encode time scales ~linearly with pixels for a given format/device.
      final ms = sw.elapsedMicroseconds / 1000.0;
      final fullMs = ms * (it.pixels / thumbPx);
      return (fullBytes: fullBytes, fullMs: fullMs);
    } catch (_) {
      return null;
    }
  }

  double? _eta(List<EstimateItem> items, double totalMs, double totalMp) {
    if (totalMp <= 0 || totalMs <= 0) return null;
    final msPerMp = totalMs / totalMp;
    final batchMp = items.fold<double>(0, (s, it) => s + it.pixels / 1e6);
    return (batchMp * msPerMp) / 1000.0;
  }

  /// Debug only: compare the thumbnail extrapolation against ONE real full
  /// encode so accuracy can be checked + tuned on a device.
  Future<void> _selfTest(
    String id,
    EstimateItem it,
    DefaultFormat target,
    int quality,
    int estimatedFull,
  ) async {
    try {
      final origin = await (await AssetEntity.fromId(id))?.originBytes;
      if (origin == null) return;
      final real = await ImageEncoder.encode(
        source: origin,
        target: target,
        quality: quality,
        hasAlpha: false,
        keepMetadata: false,
      );
      final realBytes = real.bytes.length;
      if (realBytes == 0) return;
      final err = (estimatedFull - realBytes).abs() / realBytes * 100;
      debugPrint('hayn/estimate self-test: thumb→${estimatedFull}B vs '
          'real ${realBytes}B (${err.toStringAsFixed(1)}% off, '
          '${target.techName} q$quality)');
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
