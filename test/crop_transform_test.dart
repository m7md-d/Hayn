import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/features/image_ops/data/image_crop_task.dart';
import 'package:image/image.dart' as img;

// transformRgba is the isolate pixel-work for crop: build an image from raw
// RGBA (engine-decoded, orientation already baked) → rotate/flip/crop → PNG.
void main() {
  // 4×4: left half red, right half blue.
  Uint8List checker(int w, int h) {
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final right = x >= w / 2;
        rgba[i] = right ? 0 : 255; // R
        rgba[i + 1] = 0; // G
        rgba[i + 2] = right ? 255 : 0; // B
        rgba[i + 3] = 255; // A
      }
    }
    return rgba;
  }

  test('crops the requested fraction at full resolution', () {
    final out = transformRgba(checker(4, 4), 4, 4, 0, false, false,
        0.5, 0.0, 0.5, 1.0); // right half
    expect(out, isNotNull);
    final im = img.decodePng(out!)!;
    expect(im.width, 2);
    expect(im.height, 4);
    final p = im.getPixel(0, 0);
    expect(p.b, greaterThan(200), reason: 'right half is blue');
    expect(p.r, lessThan(60));
  });

  test('full-frame crop keeps original dimensions', () {
    final out =
        transformRgba(checker(4, 4), 4, 4, 0, false, false, 0, 0, 1, 1);
    final im = img.decodePng(out!)!;
    expect(im.width, 4);
    expect(im.height, 4);
  });

  test('90° rotation swaps width/height', () {
    final out =
        transformRgba(checker(4, 2), 4, 2, 1, false, false, 0, 0, 1, 1);
    final im = img.decodePng(out!)!;
    expect(im.width, 2);
    expect(im.height, 4);
  });

  test('returns null on a truncated buffer', () {
    expect(transformRgba(Uint8List(3), 4, 4, 0, false, false, 0, 0, 1, 1),
        isNull);
  });
}
