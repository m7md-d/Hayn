import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/features/surgical/data/surgical_verify.dart';

void main() {
  // A typical safe replacement: same dimensions, genuinely smaller.
  SurgicalVerifyResult run({
    int originalBytes = 5000000,
    int candidateBytes = 1500000,
    int originalWidth = 4000,
    int originalHeight = 3000,
    int decodedWidth = 4000,
    int decodedHeight = 3000,
    bool allowResize = false,
  }) =>
      SurgicalVerify.check(
        originalBytes: originalBytes,
        candidateBytes: candidateBytes,
        originalWidth: originalWidth,
        originalHeight: originalHeight,
        decodedWidth: decodedWidth,
        decodedHeight: decodedHeight,
        allowResize: allowResize,
      );

  group('SurgicalVerify (never overwrite unless proven safe)', () {
    test('ok: same dims, smaller', () {
      expect(run(), SurgicalVerifyResult.ok);
      expect(SurgicalVerify.passed(run()), isTrue);
    });

    test('empty candidate is rejected', () {
      expect(run(candidateBytes: 0), SurgicalVerifyResult.empty);
    });

    test('failed decode (0 dimensions) → corrupt', () {
      expect(run(decodedWidth: 0, decodedHeight: 0),
          SurgicalVerifyResult.corrupt);
    });

    test('dimensions differ → dimsMismatch', () {
      expect(run(decodedWidth: 2000, decodedHeight: 1500),
          SurgicalVerifyResult.dimsMismatch);
    });

    test('an orientation swap (W↔H) is accepted as matching', () {
      // Baked-upright encode of a rotated source: 3000×4000 vs stored 4000×3000.
      expect(run(decodedWidth: 3000, decodedHeight: 4000),
          SurgicalVerifyResult.ok);
    });

    test('not actually smaller → notSmaller (refuse, no point)', () {
      expect(run(candidateBytes: 5000000), SurgicalVerifyResult.notSmaller);
      expect(run(candidateBytes: 6000000), SurgicalVerifyResult.notSmaller);
    });

    test('verify order: corrupt beats notSmaller/dims', () {
      // A zero-dimension (corrupt) candidate that is also "not smaller" must
      // report corrupt — we never trust an undecodable file.
      expect(
        run(candidateBytes: 9000000, decodedWidth: 0, decodedHeight: 0),
        SurgicalVerifyResult.corrupt,
      );
    });

    test('allowResize: smaller dimensions are fine when resizing was requested',
        () {
      expect(
        run(decodedWidth: 2000, decodedHeight: 1500, allowResize: true),
        SurgicalVerifyResult.ok,
      );
    });

    test('unknown original dims (0) → dims check skipped, size still enforced',
        () {
      expect(run(originalWidth: 0, originalHeight: 0), SurgicalVerifyResult.ok);
      expect(
        run(originalWidth: 0, originalHeight: 0, candidateBytes: 9000000),
        SurgicalVerifyResult.notSmaller,
      );
    });
  });
}
