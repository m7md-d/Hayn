import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/features/image_ops/presentation/widgets/aspect_ratio_chips.dart';
import 'package:hayn/features/image_ops/presentation/widgets/crop_canvas.dart';

void main() {
  group('aspectRatioValue', () {
    test('Free returns null (no constraint)', () {
      final r = aspectRatioValue(
        CropAspectRatio.free,
        imageWidth: 4000,
        imageHeight: 3000,
        rotationQuarters: 0,
      );
      expect(r, isNull);
    });

    test('Square returns 1.0', () {
      final r = aspectRatioValue(
        CropAspectRatio.square,
        imageWidth: 4000,
        imageHeight: 3000,
        rotationQuarters: 0,
      );
      expect(r, 1.0);
    });

    test('4:3 returns the float ratio', () {
      final r = aspectRatioValue(
        CropAspectRatio.fourThree,
        imageWidth: 4000,
        imageHeight: 3000,
        rotationQuarters: 0,
      );
      expect(r, closeTo(4 / 3, 0.0001));
    });

    test('Original uses the image aspect (rotation 0)', () {
      final r = aspectRatioValue(
        CropAspectRatio.original,
        imageWidth: 1920,
        imageHeight: 1080,
        rotationQuarters: 0,
      );
      expect(r, closeTo(1920 / 1080, 0.0001));
    });

    test('Original inverts the aspect when rotation is odd', () {
      final r = aspectRatioValue(
        CropAspectRatio.original,
        imageWidth: 1920,
        imageHeight: 1080,
        rotationQuarters: 1,
      );
      // After 90° rotation the displayed image is 1080×1920 → 1080/1920.
      expect(r, closeTo(1080 / 1920, 0.0001));
    });

    test('Square is unaffected by rotation', () {
      final r0 = aspectRatioValue(
        CropAspectRatio.square,
        imageWidth: 2000,
        imageHeight: 1500,
        rotationQuarters: 0,
      );
      final r1 = aspectRatioValue(
        CropAspectRatio.square,
        imageWidth: 2000,
        imageHeight: 1500,
        rotationQuarters: 1,
      );
      expect(r0, r1);
    });
  });
}
