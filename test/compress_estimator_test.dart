import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/features/image_ops/domain/compress_estimator.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';

// Typical source bits-per-pixel at full content detail, per family. A lossless
// PNG stores the SAME photo at far more bytes than a JPEG, so source size alone
// can't equate them — the estimator must read it relative to the family.
const _familyFactor = <SourceFamily, double>{
  SourceFamily.jpeg: 3.5,
  SourceFamily.heif: 2.2,
  SourceFamily.avif: 1.5,
  SourceFamily.webp: 2.6,
  SourceFamily.png: 11.0,
  SourceFamily.other: 3.0,
};

// The REAL output depends on the underlying content detail (d ∈ 0.2..1),
// recovered here from source bpp ÷ family factor — so the SAME photo in PNG or
// JPEG yields the same truth. The estimator never sees `d`; it must infer it
// from (sourceBytes, family) and a few samples. kTrue/contentExp/noise are
// unknown to the model on purpose.
double _trueBytes(
  EstimateItem it,
  int quality, {
  required double kTrue,
  required double contentExp,
  required double noise,
}) {
  final d = (it.sourceBpp / _familyFactor[it.family]!).clamp(0.05, 1.2);
  final qf = math.pow(quality / 80.0, 1.4).toDouble();
  final bpp = kTrue * math.pow(d, contentExp).toDouble() * qf;
  return it.pixels * bpp / 8 * noise;
}

EstimateItem _mk(SourceFamily family, double d, int pixels) => EstimateItem(
      pixels: pixels,
      sourceBytes: (pixels * d * _familyFactor[family]! / 8).round(),
      family: family,
    );

List<EstimateItem> _batch(int n, {int seed = 7}) {
  final rnd = math.Random(seed);
  const families = SourceFamily.values;
  return List.generate(n, (i) {
    final pixels = (0.5e6 + rnd.nextDouble() * 11.5e6).round();
    final d = 0.2 + rnd.nextDouble() * 0.8; // content detail
    return _mk(families[rnd.nextInt(families.length)], d, pixels);
  });
}

// Stratified sample selection by source bits-per-pixel — what the on-device
// controller does, so calibration sees every content tier (the "20 heavy + 20
// tiny" case).
List<BppSample> _stratifiedSamples(
  List<EstimateItem> items,
  DefaultFormat target,
  int quality,
  int k,
  double Function(EstimateItem) truth,
) {
  final sorted = [...items]..sort((a, b) => a.sourceBpp.compareTo(b.sourceBpp));
  final out = <BppSample>[];
  for (var i = 0; i < k; i++) {
    final it = sorted[(i * sorted.length ~/ k).clamp(0, sorted.length - 1)];
    out.add(BppSample(
      item: it,
      predicted: CompressEstimator.predictItemBytes(it, target, quality),
      actual: truth(it).round(),
    ));
  }
  return out;
}

void main() {
  group('CompressEstimator.prior (metadata-only)', () {
    test('scales ~linearly with pixels at equal source bpp', () {
      EstimateItem item(int px) => EstimateItem(
          pixels: px, sourceBytes: (px * 2 / 8).round(), family: SourceFamily.jpeg);
      final small =
          CompressEstimator.predictItemBytes(item(1000000), DefaultFormat.heic, 80);
      final big =
          CompressEstimator.predictItemBytes(item(4000000), DefaultFormat.heic, 80);
      expect(big / small, closeTo(4, 0.2));
    });

    test('increases monotonically with quality', () {
      const it = EstimateItem(
          pixels: 4000000, sourceBytes: 1000000, family: SourceFamily.jpeg);
      final q30 = CompressEstimator.predictItemBytes(it, DefaultFormat.heic, 30);
      final q60 = CompressEstimator.predictItemBytes(it, DefaultFormat.heic, 60);
      final q90 = CompressEstimator.predictItemBytes(it, DefaultFormat.heic, 90);
      expect(q30, lessThan(q60));
      expect(q60, lessThan(q90));
    });

    test('a fat lossless PNG does not explode the estimate', () {
      const png = EstimateItem(
          pixels: 1000000, sourceBytes: 1000000, family: SourceFamily.png);
      final est =
          CompressEstimator.predictItemBytes(png, DefaultFormat.heic, 80);
      expect(est, lessThan(700000));
      expect(est, greaterThan(20000));
    });

    test('content signal: a busier source predicts a bigger output', () {
      EstimateItem withBpp(double bpp) => EstimateItem(
          pixels: 4000000,
          sourceBytes: (4000000 * bpp / 8).round(),
          family: SourceFamily.jpeg);
      final flat =
          CompressEstimator.predictItemBytes(withBpp(0.8), DefaultFormat.heic, 80);
      final busy =
          CompressEstimator.predictItemBytes(withBpp(4.0), DefaultFormat.heic, 80);
      expect(busy, greaterThan(flat));
    });
  });

  group('CompressEstimator.calibrate (accuracy vs a synthetic codec)', () {
    test('recovers the true TOTAL within 8% on a heterogeneous batch', () {
      final items = _batch(200);
      const target = DefaultFormat.heic;
      const q = 80;
      final rnd = math.Random(3);
      double truth(EstimateItem it) => _trueBytes(it, q,
          kTrue: 0.42, contentExp: 0.85, noise: 0.85 + rnd.nextDouble() * 0.3);
      final trueTotal = items.fold<double>(0, (s, it) => s + truth(it));

      final samples = _stratifiedSamples(items, target, q, 20, truth);
      final est = CompressEstimator.calibrate(items, target, q, samples);
      final err = (est.expected - trueTotal).abs() / trueTotal;
      expect(err, lessThan(0.08),
          reason: 'off by ${(err * 100).toStringAsFixed(1)}%');
      expect(trueTotal, greaterThanOrEqualTo(est.low.toDouble()));
      expect(trueTotal, lessThanOrEqualTo(est.high.toDouble()));
    });

    test('handles an EXTREMELY heterogeneous batch (heavy RAW + tiny)', () {
      // Half are huge + detailed; half are tiny + flat (and a different family).
      final items = <EstimateItem>[
        for (var i = 0; i < 20; i++) _mk(SourceFamily.jpeg, 1.0, 12000000),
        for (var i = 0; i < 20; i++) _mk(SourceFamily.png, 0.3, 600000),
      ];
      const target = DefaultFormat.heic;
      const q = 75;
      double truth(EstimateItem it) =>
          _trueBytes(it, q, kTrue: 0.5, contentExp: 0.9, noise: 1.0);
      final trueTotal = items.fold<double>(0, (s, it) => s + truth(it));
      final samples = _stratifiedSamples(items, target, q, 16, truth);
      final est = CompressEstimator.calibrate(items, target, q, samples);
      final err = (est.expected - trueTotal).abs() / trueTotal;
      expect(err, lessThan(0.10),
          reason: 'heterogeneous total off by ${(err * 100).toStringAsFixed(1)}%');
    });

    test('is robust to a wildly broken sample (outlier trimmed)', () {
      final items = _batch(120, seed: 11);
      const target = DefaultFormat.avif;
      const q = 70;
      double truth(EstimateItem it) =>
          _trueBytes(it, q, kTrue: 0.3, contentExp: 0.9, noise: 1.0);
      final trueTotal = items.fold<double>(0, (s, it) => s + truth(it));
      final samples = _stratifiedSamples(items, target, q, 12, truth);
      samples.add(BppSample(
          item: items.first, predicted: 1000, actual: 100000000)); // garbage
      final est = CompressEstimator.calibrate(items, target, q, samples);
      final err = (est.expected - trueTotal).abs() / trueTotal;
      expect(err, lessThan(0.15),
          reason: 'outlier skewed it: ${(err * 100).toStringAsFixed(1)}%');
    });

    test('tightens the band + raises confidence with more samples', () {
      final items = _batch(300, seed: 5);
      const target = DefaultFormat.heic;
      const q = 80;
      final rnd = math.Random(2);
      double truth(EstimateItem it) => _trueBytes(it, q,
          kTrue: 0.5, contentExp: 0.8, noise: 0.7 + rnd.nextDouble() * 0.6);
      final few = CompressEstimator.calibrate(
          items, target, q, _stratifiedSamples(items, target, q, 4, truth));
      final many = CompressEstimator.calibrate(
          items, target, q, _stratifiedSamples(items, target, q, 40, truth));
      expect(many.confidence, greaterThan(few.confidence));
      expect((many.high - many.low) / many.expected,
          lessThan((few.high - few.low) / few.expected));
    });

    test('encoding ALL items (small-N path) is essentially exact', () {
      final items = _batch(20, seed: 9);
      const target = DefaultFormat.heic;
      const q = 85;
      double truth(EstimateItem it) =>
          _trueBytes(it, q, kTrue: 0.6, contentExp: 0.75, noise: 1.0);
      final trueTotal = items.fold<double>(0, (s, it) => s + truth(it));
      final samples = [
        for (final it in items)
          BppSample(
              item: it,
              predicted: CompressEstimator.predictItemBytes(it, target, q),
              actual: truth(it).round()),
      ];
      final est = CompressEstimator.calibrate(items, target, q, samples);
      final err = (est.expected - trueTotal).abs() / trueTotal;
      expect(err, lessThan(0.03));
    });
  });

  group('CompressEstimator.calibrateWithAnchor (single preview anchor)', () {
    BppSample anchorOf(
        EstimateItem it, DefaultFormat target, int q, double ratio) {
      final p = CompressEstimator.predictItemBytes(it, target, q);
      return BppSample(item: it, predicted: p, actual: (p * ratio).round());
    }

    test('a homogeneous batch trusts the anchor (≈ applies its ratio)', () {
      // Every item shares the anchor's family + bpp tier, so the lone sample
      // generalises — the correction is applied at ~full weight (0.9).
      final items = [
        for (var i = 0; i < 40; i++) _mk(SourceFamily.jpeg, 0.9, 8000000)
      ];
      const target = DefaultFormat.heic;
      const q = 80;
      final prior = CompressEstimator.prior(items, target, q).expected;
      // Real encode came out at half the prediction → alpha = 1+(0.5−1)*0.9.
      final est = CompressEstimator.calibrateWithAnchor(
          items, target, q, anchorOf(items.first, target, q, 0.5));
      expect(est.expected / prior, closeTo(0.55, 0.04));
    });

    test('a lone far-stratum anchor does NOT rescale the whole batch', () {
      // 60 low-detail JPEGs (the mass) + one high-detail PNG anchor (far in
      // both family and bpp tier). A blind single-factor calibration would
      // scale everything by the PNG's ratio; the de-biased one must not.
      final items = <EstimateItem>[
        for (var i = 0; i < 60; i++) _mk(SourceFamily.jpeg, 0.25, 6000000),
        _mk(SourceFamily.png, 1.0, 6000000),
      ];
      const target = DefaultFormat.avif;
      const q = 80;
      final prior = CompressEstimator.prior(items, target, q).expected;
      final anchor = anchorOf(items.last, target, q, 3.0); // under-predicted ×3
      final deBiased =
          CompressEstimator.calibrateWithAnchor(items, target, q, anchor)
              .expected;
      final blind =
          CompressEstimator.calibrate(items, target, q, [anchor]).expected;
      expect(deBiased / prior, lessThan(1.6),
          reason: 'far anchor over-moved the batch');
      expect(blind / prior, greaterThan(2.5),
          reason: 'sanity: the blind path really does globally rescale');
    });

    test('switching the previewed anchor swings the total far less than blind',
        () {
      // Two small, distinct strata + a large neutral mass far from both. As the
      // user flips the preview between an A and a B image, the de-biased total
      // should barely move (the neutral mass stays near its prior), whereas a
      // blind single-factor calibration would swing by the full ratio gap.
      final items = <EstimateItem>[
        for (var i = 0; i < 10; i++) _mk(SourceFamily.jpeg, 0.3, 5000000), // A
        for (var i = 0; i < 10; i++) _mk(SourceFamily.heif, 0.95, 9000000), // B
        for (var i = 0; i < 80; i++)
          _mk(SourceFamily.other, 1.4, 4000000), // neutral mass (far from both)
      ];
      const target = DefaultFormat.heic;
      const q = 80;
      final aA = anchorOf(items.first, target, q, 0.5);
      final aB = anchorOf(items[15], target, q, 2.0);
      final swingDeBiased = (CompressEstimator.calibrateWithAnchor(
                  items, target, q, aA)
              .expected -
          CompressEstimator.calibrateWithAnchor(items, target, q, aB).expected)
          .abs();
      final swingBlind =
          (CompressEstimator.calibrate(items, target, q, [aA]).expected -
                  CompressEstimator.calibrate(items, target, q, [aB]).expected)
              .abs();
      expect(swingDeBiased, lessThan(swingBlind * 0.5),
          reason: 'preview bias not dampened enough');
    });

    test('a degenerate anchor falls back to the prior', () {
      final items = _batch(30);
      const target = DefaultFormat.heic;
      const q = 80;
      final prior = CompressEstimator.prior(items, target, q);
      final bad = BppSample(item: items.first, predicted: 0, actual: 0);
      final est = CompressEstimator.calibrateWithAnchor(items, target, q, bad);
      expect(est.expected, prior.expected);
    });
  });

  group('CompressEstimator.selectSampleIndices (dynamic + stratified)', () {
    test('small batch → sample everything (exact path)', () {
      final items = _batch(15);
      expect(CompressEstimator.selectSampleIndices(items, 24).length, 15);
    });

    test('large batch → capped, and covers every content stratum', () {
      // Two very different strata: 100 heavy JPEG + 100 tiny PNG.
      final items = <EstimateItem>[
        for (var i = 0; i < 100; i++) _mk(SourceFamily.jpeg, 0.95, 9000000),
        for (var i = 0; i < 100; i++) _mk(SourceFamily.png, 0.3, 500000),
      ];
      final picked = CompressEstimator.selectSampleIndices(items, 16);
      expect(picked.length, 16);
      // Both strata must be represented (not all from one).
      final heavy = picked.where((i) => i < 100).length;
      final tiny = picked.where((i) => i >= 100).length;
      expect(heavy, greaterThan(0));
      expect(tiny, greaterThan(0));
    });

    test('cap of 0 yields nothing', () {
      expect(CompressEstimator.selectSampleIndices(_batch(10), 0), isEmpty);
    });
  });

  group('SourceFamily classification', () {
    test('maps mime types + extensions', () {
      expect(SourceFamilyFromMime.of('image/jpeg'), SourceFamily.jpeg);
      expect(SourceFamilyFromMime.of('image/png'), SourceFamily.png);
      expect(SourceFamilyFromMime.of('image/heic'), SourceFamily.heif);
      expect(SourceFamilyFromMime.of('image/avif'), SourceFamily.avif);
      expect(SourceFamilyFromMime.of(null, ext: 'webp'), SourceFamily.webp);
      expect(SourceFamilyFromMime.of('application/octet-stream'),
          SourceFamily.other);
    });
  });
}
