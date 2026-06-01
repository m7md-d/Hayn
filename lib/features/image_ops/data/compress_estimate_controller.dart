import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../data/index/index_providers.dart';
import '../../settings/providers/preferences_providers.dart';
import '../domain/compress_estimator.dart';
import 'image_encoder.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CompressEstimateController — live, accurate, memory-safe estimate for a
// (possibly huge) selection.
//
// Accuracy: each sample is a REAL full-resolution encode of the original at the
// chosen settings — exactly what the task produces — so there's ZERO
// extrapolation bias. (Downscaled proxies/thumbnails were 2.5–3× too big at high
// quality because shrinking an image concentrates detail and inflates its
// bits-per-pixel.) Those real encodes also time the device per format, so the
// ETA is truthful (a light WebP ≠ a heavy AVIF).
//
// Memory: samples run STRICTLY one-at-a-time, awaited, with a hard count + a
// wall-clock budget, and iOS tmp exports are released at the end. There's no
// fire-and-forget work that could stack full-res encodes (that — a debug
// self-test left unawaited — is what OOM-killed a select-all-10k run).
//
// Dynamic by N (≤24 → encode all ≈ exact; larger → up to [_maxSamples]
// stratified, slow formats getting fewer but each exact, the prior covering the
// remainder). Cancellable; the instant prior shows first and refines live.
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

    for (final i in indices) {
      if (_cancelled) return;
      if (samples.isNotEmpty && clock.elapsed > _budget) break;
      final m = await _sampleOne(facts[i].id, target, quality);
      if (_cancelled) return;
      if (m == null) continue;
      samples.add(BppSample(
        item: items[i],
        predicted:
            CompressEstimator.predictItemBytes(items[i], target, quality),
        actual: m.bytes,
      ));
      totalMs += m.ms;
      totalMp += items[i].pixels / 1e6;
      current = CompressEstimator.calibrate(items, target, quality, samples);
      onUpdate(EstimateResult(
        size: current,
        refining: true,
        etaSeconds: _eta(items, totalMs, totalMp),
      ));
    }

    // Release the originals iOS exported to tmp while sampling.
    await PhotoManager.clearFileCache();
    if (_cancelled) return;
    onUpdate(EstimateResult(
      size: current,
      refining: false,
      etaSeconds: _eta(items, totalMs, totalMp),
    ));
  }

  /// One REAL full-resolution encode → exact output bytes + real encode time.
  /// keepMetadata:false keeps the sample light (metadata adds only a few KB,
  /// irrelevant to a size class). Null on any failure (sample skipped).
  Future<({int bytes, double ms})?> _sampleOne(
    String id,
    DefaultFormat target,
    int quality,
  ) async {
    try {
      final origin = await (await AssetEntity.fromId(id))?.originBytes;
      if (origin == null || _cancelled) return null;
      final sw = Stopwatch()..start();
      final enc = await ImageEncoder.encode(
        source: origin,
        target: target,
        quality: quality,
        hasAlpha: false,
        keepMetadata: false,
      );
      sw.stop();
      if (enc.bytes.isEmpty) return null;
      return (bytes: enc.bytes.length, ms: sw.elapsedMicroseconds / 1000.0);
    } catch (_) {
      return null;
    }
  }

  /// Total compress time from REAL per-megapixel encode timing (per format, per
  /// device) — no fudge. Null until we have a sample.
  double? _eta(List<EstimateItem> items, double totalMs, double totalMp) {
    if (totalMp <= 0 || totalMs <= 0) return null;
    final msPerMp = totalMs / totalMp;
    final batchMp = items.fold<double>(0, (s, it) => s + it.pixels / 1e6);
    return (batchMp * msPerMp) / 1000.0;
  }

  static String _ext(String? title) {
    final t = title ?? '';
    final dot = t.lastIndexOf('.');
    return (dot >= 0 && dot < t.length - 1) ? t.substring(dot + 1) : '';
  }
}
