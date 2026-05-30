import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';

void main() {
  group('ImageEncoder.fallbackChain', () {
    test('opaque AVIF target walks efficiency → opaque floor', () {
      expect(
        ImageEncoder.fallbackChain(DefaultFormat.avif, false),
        [
          DefaultFormat.avif,
          DefaultFormat.webp,
          DefaultFormat.jpeg,
          DefaultFormat.png,
        ],
      );
    });

    test('alpha AVIF target never lists JPEG, ends at PNG floor', () {
      expect(
        ImageEncoder.fallbackChain(DefaultFormat.avif, true),
        [DefaultFormat.avif, DefaultFormat.webp, DefaultFormat.png],
      );
    });

    test('alpha chains NEVER contain JPEG for any target (golden rule)', () {
      for (final t in DefaultFormat.values) {
        final chain = ImageEncoder.fallbackChain(t, true);
        expect(chain.contains(DefaultFormat.jpeg), isFalse,
            reason: 'target $t (alpha) leaked JPEG: $chain');
        expect(chain.contains(DefaultFormat.png), isTrue,
            reason: 'target $t (alpha) has no PNG floor');
      }
    });

    test('opaque chains always have a JPEG floor', () {
      for (final t in DefaultFormat.values) {
        expect(ImageEncoder.fallbackChain(t, false).contains(DefaultFormat.jpeg),
            isTrue,
            reason: 'target $t (opaque) has no JPEG floor');
      }
    });

    test('no format is attempted twice', () {
      for (final t in DefaultFormat.values) {
        for (final alpha in [true, false]) {
          final chain = ImageEncoder.fallbackChain(t, alpha);
          expect(chain.toSet().length, chain.length,
              reason: 'duplicate in $t/$alpha: $chain');
        }
      }
    });

    test('auto is never attempted (policy resolves it first)', () {
      for (final alpha in [true, false]) {
        for (final t in DefaultFormat.values) {
          expect(ImageEncoder.fallbackChain(t, alpha),
              isNot(contains(DefaultFormat.auto)));
        }
      }
    });
  });
}
