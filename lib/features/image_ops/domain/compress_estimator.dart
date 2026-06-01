import 'dart:math' as math;

import '../../settings/providers/preferences_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CompressEstimator — predicts the output size of a (possibly huge) compress
// batch WITHOUT encoding everything. Pure + dependency-free (no Flutter, no IO),
// so the whole model is unit-testable; the costly bits (a few real proxy
// encodes used to calibrate it) are injected by the caller as [BppSample]s.
//
// Why a real model and not a flat ratio: the same dimensions + source size can
// land anywhere — a 1000×1000 PNG might shrink to 10 KB or 200 KB purely by
// content. So the predictor is built on three signals that DO track content:
//   1. pixels                     — output roughly scales with area.
//   2. source bits-per-pixel      — sourceBytes*8/pixels: how much detail the
//      (srcBpp)                     source actually retains (a busy photo has a
//                                   high srcBpp; a flat one is tiny). This is the
//                                   single best cheap proxy for "compressibility".
//   3. source family              — a lossless PNG's bytes overstate detail vs a
//                                   JPEG's, so its srcBpp is damped.
//
// Pipeline:
//   • prior()   — instant, metadata-only (index data). Good for 10k items with
//                 zero IO; returned with a WIDE band (we don't pretend to know).
//   • calibrate() — fold in a handful of measured (predicted vs real) ratios to
//                 correct the model's bias for THIS batch + codec + device, and
//                 TIGHTEN the band. Robust (median) so one weird sample can't
//                 skew it. The caller decides how to obtain samples (e.g. tiny
//                 multi-scale proxy encodes) and how many (adaptive / time-boxed)
//                 — this layer just consumes the ratios.
// All constants below are starting priors; calibration is what makes it accurate
// on real content, so they only need to be in the right ballpark.
// ─────────────────────────────────────────────────────────────────────────────

enum SourceFamily { jpeg, heif, avif, webp, png, other }

extension SourceFamilyFromMime on SourceFamily {
  static SourceFamily of(String? mime, {String? ext}) {
    final m = (mime ?? '').toLowerCase();
    final e = (ext ?? '').toLowerCase();
    bool has(String s) => m.contains(s) || e == s || e == 'j$s';
    if (m.contains('jpeg') || m.contains('jpg') || e == 'jpg' || e == 'jpeg') {
      return SourceFamily.jpeg;
    }
    if (has('png')) return SourceFamily.png;
    if (m.contains('hei') || e == 'heic' || e == 'heif') return SourceFamily.heif;
    if (m.contains('avif') || e == 'avif') return SourceFamily.avif;
    if (m.contains('webp') || e == 'webp') return SourceFamily.webp;
    return SourceFamily.other;
  }
}

class EstimateItem {
  const EstimateItem({
    required this.pixels,
    required this.sourceBytes,
    required this.family,
    this.hasAlpha = false,
  });

  final int pixels;
  final int sourceBytes;
  final SourceFamily family;
  final bool hasAlpha;

  /// Source bits-per-pixel — the cheap content/compressibility signal.
  double get sourceBpp => pixels <= 0 ? 0 : (sourceBytes * 8) / pixels;
}

/// One measured calibration point: the sampled item, what the prior model
/// predicted for it, and what a real encode actually produced (both in bytes at
/// full-res scale — the caller scales a proxy measurement up to full res). The
/// item rides along so calibration can correct PER CONTENT STRATUM, not just
/// globally (a batch of heavy RAW + tiny images needs different corrections).
class BppSample {
  const BppSample({
    required this.item,
    required this.predicted,
    required this.actual,
  });
  final EstimateItem item;
  final int predicted;
  final int actual;
}

class SizeEstimate {
  const SizeEstimate({
    required this.low,
    required this.expected,
    required this.high,
    required this.confidence,
  });

  final int low; // bytes — optimistic
  final int expected; // bytes — best guess
  final int high; // bytes — pessimistic
  final double confidence; // 0..1 (rises as the band tightens)

  double savingsFraction(int originalBytes) =>
      originalBytes <= 0 ? 0 : (1 - expected / originalBytes).clamp(-1.0, 1.0);
}

abstract final class CompressEstimator {
  // Reference output bits-per-pixel for a "typical" photo at quality 80, per
  // target codec. Calibration scales these to reality; they only set the prior.
  static double _baseBpp(DefaultFormat target) => switch (target) {
        DefaultFormat.jpeg => 1.8,
        DefaultFormat.heic => 1.0,
        DefaultFormat.avif => 0.7,
        DefaultFormat.webp => 1.3,
        DefaultFormat.png => 6.0, // lossless — content-bound, very rough
        DefaultFormat.auto => 1.0, // resolved before here in practice
      };

  // Quality → bpp multiplier (monotonic). 80 is the reference (×1). Higher
  // quality costs disproportionately more bits; lower saves a lot.
  static double _qualityFactor(int quality) {
    final q = quality.clamp(1, 100);
    return math.pow(q / 80.0, 1.6).toDouble().clamp(0.15, 3.5);
  }

  // Typical source bits-per-pixel per family, used to normalise srcBpp into a
  // 0.3–3.0 "complexity" multiplier. PNG is lossless so its bytes overstate
  // detail → a high reference + extra damping.
  static double _refSourceBpp(SourceFamily f) => switch (f) {
        SourceFamily.jpeg => 2.2,
        SourceFamily.heif => 1.4,
        SourceFamily.avif => 1.0,
        SourceFamily.webp => 1.6,
        SourceFamily.png => 8.0,
        SourceFamily.other => 2.0,
      };

  /// Per-item predicted output bytes from metadata alone.
  static int predictItemBytes(
    EstimateItem item,
    DefaultFormat target,
    int quality,
  ) {
    if (item.pixels <= 0) return 0;
    final ref = _refSourceBpp(item.family);
    // Output bpp grows SUB-linearly with source detail (a codec spends fewer
    // extra bits as detail rises), so a 0.8 power tracks reality far better than
    // a linear ratio — which keeps per-item prediction/reality ratios flat and
    // lets calibration converge from few samples.
    var complexity = math.pow(item.sourceBpp / ref, 0.8).toDouble();
    // Lossless sources: their size weakly predicts LOSSY output — pull the
    // complexity toward 1 so a fat PNG doesn't explode the estimate.
    if (item.family == SourceFamily.png) {
      complexity = 1 + (complexity - 1) * 0.35;
    }
    complexity = complexity.clamp(0.3, 3.0);

    var bpp = _baseBpp(target) * _qualityFactor(quality) * complexity;
    if (item.hasAlpha && target != DefaultFormat.jpeg) {
      bpp *= 1.12; // an alpha channel adds a little
    }
    var bytes = (item.pixels * bpp / 8).round();

    // Sanity floor; and a lossy re-encode at/below the source's codec tier
    // shouldn't be predicted LARGER than the source (clamp the common case,
    // but allow growth when converting from a lossy source to PNG).
    bytes = math.max(bytes, 512);
    if (target != DefaultFormat.png && item.sourceBytes > 0) {
      bytes = math.min(bytes, (item.sourceBytes * 1.2).round());
    }
    return bytes;
  }

  /// Instant, metadata-only estimate for the whole batch (wide band).
  static SizeEstimate prior(
    List<EstimateItem> items,
    DefaultFormat target,
    int quality,
  ) {
    var total = 0;
    for (final it in items) {
      total += predictItemBytes(it, target, quality);
    }
    // No samples yet → the prior is uncertain. ±45% band, low confidence.
    return SizeEstimate(
      low: (total * 0.55).round(),
      expected: total,
      high: (total * 1.45).round(),
      confidence: 0.25,
    );
  }

  // Content tier from source bits-per-pixel — the axis along which the
  // prediction-vs-reality ratio varies most, so we calibrate within each tier.
  static int _bppTier(double bpp) =>
      bpp < 1.2 ? 0 : (bpp < 2.6 ? 1 : (bpp < 4.0 ? 2 : 3));
  static String _fineKey(EstimateItem it) =>
      '${it.family.index}:${_bppTier(it.sourceBpp)}';
  static String _coarseKey(EstimateItem it) => '${_bppTier(it.sourceBpp)}';

  /// Refine the prior with measured (predicted vs actual) pairs.
  ///
  /// Heterogeneity is the hard part: 20 heavy RAW shots and 20 tiny images need
  /// DIFFERENT corrections. So we don't apply one global factor — we fit a
  /// trimmed ratio-of-sums (Σactual/Σpredicted) per CONTENT STRATUM
  /// (family × source-bpp tier), with a coarser tier and then a global factor as
  /// fallbacks when a stratum is thin. Each item is corrected by the finest
  /// stratum that has enough samples. Outliers are trimmed so one broken encode
  /// can't skew a stratum. The band/confidence come from the overall ratio
  /// spread, shrunk by sample count.
  static SizeEstimate calibrate(
    List<EstimateItem> items,
    DefaultFormat target,
    int quality,
    List<BppSample> samples,
  ) {
    final base = prior(items, target, quality);
    final usable = [for (final s in samples) if (s.predicted > 0) s];
    if (usable.isEmpty) return base;

    final allRatios = [for (final s in usable) s.actual / s.predicted]..sort();
    final med = _median(allRatios);
    if (!med.isFinite || med <= 0) return base;

    // Accumulate Σactual / Σpredicted per stratum (and globally) over the
    // non-outlier samples.
    final fineA = <String, double>{}, fineP = <String, double>{};
    final fineN = <String, int>{};
    final coarseA = <String, double>{}, coarseP = <String, double>{};
    final coarseN = <String, int>{};
    var globA = 0.0, globP = 0.0;
    final kept = <double>[];
    for (final s in usable) {
      final r = s.actual / s.predicted;
      if (r < med / 3 || r > med * 3) continue; // trim
      kept.add(r);
      globA += s.actual;
      globP += s.predicted;
      final fk = _fineKey(s.item);
      fineA[fk] = (fineA[fk] ?? 0) + s.actual;
      fineP[fk] = (fineP[fk] ?? 0) + s.predicted;
      fineN[fk] = (fineN[fk] ?? 0) + 1;
      final ck = _coarseKey(s.item);
      coarseA[ck] = (coarseA[ck] ?? 0) + s.actual;
      coarseP[ck] = (coarseP[ck] ?? 0) + s.predicted;
      coarseN[ck] = (coarseN[ck] ?? 0) + 1;
    }
    if (kept.isEmpty) return base;
    final globAlpha = globP > 0 ? globA / globP : med;

    double alphaFor(EstimateItem it) {
      final fk = _fineKey(it);
      if ((fineN[fk] ?? 0) >= 2 && (fineP[fk] ?? 0) > 0) return fineA[fk]! / fineP[fk]!;
      final ck = _coarseKey(it);
      if ((coarseN[ck] ?? 0) >= 2 && (coarseP[ck] ?? 0) > 0) {
        return coarseA[ck]! / coarseP[ck]!;
      }
      return globAlpha;
    }

    var expected = 0.0;
    for (final it in items) {
      expected += predictItemBytes(it, target, quality) * alphaFor(it);
    }
    final exp = expected.round();

    // Band from the overall spread, narrowing with more samples.
    final rel = _relativeSpread(kept..sort(), globAlpha);
    final half = (rel / math.sqrt(kept.length)).clamp(0.04, 0.5);
    final confidence = (1 - half).clamp(0.0, 0.97);

    return SizeEstimate(
      low: (exp * (1 - half)).round(),
      expected: exp,
      high: (exp * (1 + half)).round(),
      confidence: confidence,
    );
  }

  /// Choose WHICH items to sample, covering content strata first so a
  /// heterogeneous batch (heavy RAW + tiny) is always represented, capped at
  /// [maxSamples]. When the batch is no bigger than the cap, every item is
  /// returned — i.e. "encode them all", which the small-N strategy uses for an
  /// (essentially) exact total. Within a stratum, picks are spread by pixel size
  /// so big and small members are both seen. Pure → unit-testable.
  static List<int> selectSampleIndices(
    List<EstimateItem> items,
    int maxSamples,
  ) {
    final n = items.length;
    if (maxSamples >= n) return [for (var i = 0; i < n; i++) i];
    if (maxSamples <= 0) return const [];

    final byStratum = <String, List<int>>{};
    for (var i = 0; i < n; i++) {
      (byStratum[_fineKey(items[i])] ??= []).add(i);
    }
    // Spread each stratum's members by pixel size (so we don't only sample the
    // small ones), and round-robin across strata until the cap is hit.
    final queues = <List<int>>[];
    for (final idxs in byStratum.values) {
      idxs.sort((a, b) => items[a].pixels.compareTo(items[b].pixels));
      queues.add(_spread(idxs));
    }
    final picked = <int>[];
    var added = true;
    while (picked.length < maxSamples && added) {
      added = false;
      for (final q in queues) {
        if (q.isEmpty) continue;
        picked.add(q.removeAt(0));
        added = true;
        if (picked.length >= maxSamples) break;
      }
    }
    return picked;
  }

  /// Reorder so consumption from the front samples the extremes then the middle
  /// (largest, smallest, then the rest) — good coverage from few picks.
  static List<int> _spread(List<int> sortedBySize) {
    final out = <int>[];
    var lo = 0, hi = sortedBySize.length - 1;
    var takeHi = true;
    while (lo <= hi) {
      out.add(takeHi ? sortedBySize[hi--] : sortedBySize[lo++]);
      takeHi = !takeHi;
    }
    return out;
  }

  static double _median(List<double> sorted) {
    final n = sorted.length;
    if (n == 0) return double.nan;
    return n.isOdd
        ? sorted[n ~/ 2]
        : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }

  /// Median absolute deviation, relative to the centre — a robust spread.
  static double _relativeSpread(List<double> sorted, double centre) {
    if (centre <= 0) return 0.5;
    final devs = <double>[for (final r in sorted) (r - centre).abs()]..sort();
    final mad = _median(devs);
    return (mad / centre).clamp(0.0, 1.0);
  }
}
