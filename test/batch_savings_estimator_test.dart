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
    test('Empty selection returns a zeroed estimate, not a crash', () async {
      final r = await BatchSavingsEstimator.estimate(
        assets: const [],
        format: DefaultFormat.avif,
        quality: 80,
      );
      expect(r.assetCount, 0);
      expect(r.totalOriginalBytes, 0);
      expect(r.estimatedNewBytes, 0);
      expect(r.savedPercent, 0);
      expect(r.isApproximation, false);
    });
  });
}
