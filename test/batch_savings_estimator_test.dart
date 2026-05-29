import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/batch/batch_savings_estimator.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';

void main() {
  group('BatchSavingsEstimator.compressionRatio', () {
    test('AVIF at balanced quality is roughly a third of the original', () {
      final r = BatchSavingsEstimator.compressionRatio(DefaultFormat.avif, 80);
      expect(r, greaterThan(0.20));
      expect(r, lessThan(0.45));
    });

    test('JPEG keeps most of the original size', () {
      final r = BatchSavingsEstimator.compressionRatio(DefaultFormat.jpeg, 80);
      expect(r, greaterThan(0.60));
      expect(r, lessThan(1.00));
    });

    test('Higher quality always produces a larger ratio than lower', () {
      final low =
          BatchSavingsEstimator.compressionRatio(DefaultFormat.avif, 40);
      final high =
          BatchSavingsEstimator.compressionRatio(DefaultFormat.avif, 95);
      expect(high, greaterThan(low));
    });

    test('Ratio stays inside [0.05, 0.95] for any format/quality combo', () {
      for (final f in DefaultFormat.values) {
        for (final q in [30, 50, 80, 100]) {
          final r = BatchSavingsEstimator.compressionRatio(f, q);
          expect(r, greaterThanOrEqualTo(0.05));
          expect(r, lessThanOrEqualTo(0.95));
        }
      }
    });

    test('AVIF < HEIC < WebP < JPEG at the same quality (efficiency order)',
        () {
      const q = 80;
      final avif = BatchSavingsEstimator.compressionRatio(
          DefaultFormat.avif, q);
      final heic = BatchSavingsEstimator.compressionRatio(
          DefaultFormat.heic, q);
      final webp = BatchSavingsEstimator.compressionRatio(
          DefaultFormat.webp, q);
      final jpeg = BatchSavingsEstimator.compressionRatio(
          DefaultFormat.jpeg, q);
      expect(avif, lessThan(heic));
      expect(heic, lessThan(webp));
      expect(webp, lessThan(jpeg));
    });
  });

  group('BatchSavingsEstimator.estimate', () {
    test('Empty selection returns a zeroed estimate, not a crash', () {
      final r = BatchSavingsEstimator.estimate(
        facts: const [],
        format: DefaultFormat.avif,
        quality: 80,
      );
      expect(r.assetCount, 0);
      expect(r.totalOriginalBytes, 0);
      expect(r.estimatedNewBytes, 0);
      expect(r.savedPercent, 0);
    });

    test('models output from dimensions and reports real savings', () {
      // A 12 MP photo at 5 MB → AVIF is far denser, so it clearly shrinks.
      final r = BatchSavingsEstimator.estimate(
        facts: const [(sizeBytes: 5000000, width: 4000, height: 3000)],
        format: DefaultFormat.avif,
        quality: 80,
      );
      expect(r.assetCount, 1);
      expect(r.totalOriginalBytes, 5000000);
      expect(r.estimatedNewBytes, greaterThan(0));
      expect(r.estimatedNewBytes, lessThan(5000000));
      expect(r.savedPercent, greaterThan(0));
    });

    test('never grows a file: output is capped at the original size', () {
      final r = BatchSavingsEstimator.estimate(
        facts: const [(sizeBytes: 1000, width: 4000, height: 3000)],
        format: DefaultFormat.jpeg,
        quality: 100,
      );
      expect(r.estimatedNewBytes, lessThanOrEqualTo(1000));
      expect(r.savedPercent, greaterThanOrEqualTo(0));
    });

    test('AVIF estimates fewer output bytes than JPEG for the same image', () {
      const facts = [(sizeBytes: 8000000, width: 4000, height: 3000)];
      final avif = BatchSavingsEstimator.estimate(
          facts: facts, format: DefaultFormat.avif, quality: 80);
      final jpeg = BatchSavingsEstimator.estimate(
          facts: facts, format: DefaultFormat.jpeg, quality: 80);
      expect(avif.estimatedNewBytes, lessThan(jpeg.estimatedNewBytes));
    });
  });
}
