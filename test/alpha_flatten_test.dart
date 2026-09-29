import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/features/image_ops/data/alpha_flatten.dart';
import 'package:image/image.dart' as img;

void main() {
  test('partial alpha is composited over white', () {
    final src = img.Image(width: 1, height: 1, numChannels: 4)
      ..setPixelRgba(0, 0, 80, 120, 160, 64);
    final out = img.decodePng(flattenOnWhite(img.encodePng(src))!)!;
    expect(out.hasAlpha, isFalse);
    final p = out.getPixel(0, 0);
    // c·a + 255·(1 − a) with a = 64/255.
    expect(p.r, closeTo(80 * 64 / 255 + 255 * 191 / 255, 1));
    expect(p.g, closeTo(120 * 64 / 255 + 255 * 191 / 255, 1));
    expect(p.b, closeTo(160 * 64 / 255 + 255 * 191 / 255, 1));
  });

  test('16-bit and palette sources come out as 8-bit opaque', () {
    final deep = img.Image(
      width: 1,
      height: 1,
      numChannels: 4,
      format: img.Format.uint16,
    )..setPixelRgba(0, 0, 0, 0, 0, 0);
    final a = img.decodePng(flattenOnWhite(img.encodePng(deep))!)!;
    expect((a.hasAlpha, a.getPixel(0, 0).r), (false, 255));

    final palette = img.Image(
      width: 2,
      height: 1,
      numChannels: 4,
      withPalette: true,
    );
    palette.palette!
      ..setRgba(0, 0, 0, 0, 0)
      ..setRgba(1, 10, 20, 30, 255);
    palette.getPixel(1, 0).index = 1;
    final b = img.decodePng(flattenOnWhite(img.encodePng(palette))!)!;
    expect(b.getPixel(0, 0).r, 255);
    expect(b.getPixel(1, 0).b, 30);
  });

  test('undecodable bytes return null', () {
    expect(flattenOnWhite(Uint8List(8)), isNull);
  });
}
