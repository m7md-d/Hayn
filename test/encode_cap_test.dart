import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';

// The huge-image guard: only sources whose long edge exceeds kMaxEncodeLongEdge
// are downscaled (a ~200 MP decode is ~800 MB of RGBA → OOM). Normal/large
// photos pass through untouched.
void main() {
  group('encodeCapFor (huge-image guard)', () {
    test('normal photo (12 MP) is untouched', () {
      final c = encodeCapFor(4032, 3024);
      expect(c.maxWidth, isNull);
      expect(c.maxHeight, isNull);
    });

    test('48 MP (8064 px long edge) is still untouched (≤ cap)', () {
      final c = encodeCapFor(8064, 6048);
      expect(c.maxWidth, isNull);
      expect(c.maxHeight, isNull);
    });

    test('~200 MP is capped to the max long edge', () {
      final c = encodeCapFor(16320, 12240);
      expect(c.maxWidth, kMaxEncodeLongEdge);
      expect(c.maxHeight, kMaxEncodeLongEdge);
    });

    test('portrait orientation uses the long (height) edge', () {
      final c = encodeCapFor(12240, 16320);
      expect(c.maxWidth, kMaxEncodeLongEdge);
      expect(c.maxHeight, kMaxEncodeLongEdge);
    });

    test('unknown dimensions (0) are untouched', () {
      final c = encodeCapFor(0, 0);
      expect(c.maxWidth, isNull);
    });

    test('exactly at the cap is untouched (boundary)', () {
      final c = encodeCapFor(kMaxEncodeLongEdge, 4000);
      expect(c.maxWidth, isNull);
    });
  });
}
