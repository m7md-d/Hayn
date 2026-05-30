import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/features/image_ops/data/image_probe.dart';
import 'package:hayn/features/image_ops/data/metadata.dart';

bool _contains(Uint8List h, List<int> n) {
  for (var i = 0; i + n.length <= h.length; i++) {
    var ok = true;
    for (var j = 0; j < n.length; j++) {
      if (h[i + j] != n[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  group('ImageProbe.sniff', () {
    test('detects formats by magic bytes', () {
      Uint8List pad(List<int> head) =>
          Uint8List.fromList([...head, ...List.filled(16, 0)]);
      expect(ImageProbe.sniff(pad([0xFF, 0xD8, 0xFF])), SniffedFormat.jpeg);
      expect(ImageProbe.sniff(pad([0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10])),
          SniffedFormat.png);
      expect(ImageProbe.sniff(pad([0x47, 0x49, 0x46, 0x38])), SniffedFormat.gif);
      expect(
        ImageProbe.sniff(Uint8List.fromList(
            [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])),
        SniffedFormat.webp,
      );
      // ISO-BMFF: ....ftyp + brand
      expect(
        ImageProbe.sniff(Uint8List.fromList([
          0, 0, 0, 0, //
          0x66, 0x74, 0x79, 0x70, // 'ftyp'
          0x68, 0x65, 0x69, 0x63, // 'heic'
        ])),
        SniffedFormat.heic,
      );
      expect(ImageProbe.sniff(Uint8List.fromList(List.filled(20, 0x7A))),
          SniffedFormat.unknown);
    });
  });

  group('MetadataStripper.stripJpeg (lossless)', () {
    test('removes APP1/EXIF, keeps APP0 + scan + EOI, shrinks', () {
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xE1, 0x00, 0x08, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // APP1 Exif
        0xFF, 0xE0, 0x00, 0x06, 0x4A, 0x46, 0x49, 0x46, // APP0 JFIF
        0xFF, 0xDA, 0x00, 0x04, 0xAA, 0xBB, // SOS
        0x11, 0x22, 0x33, // entropy data
        0xFF, 0xD9, // EOI
      ]);
      final out = MetadataStripper.stripJpeg(jpeg);

      expect(_contains(out, [0xFF, 0xE1]), isFalse, reason: 'APP1 dropped');
      expect(_contains(out, [0x45, 0x78, 0x69, 0x66]), isFalse,
          reason: '"Exif" gone');
      expect(_contains(out, [0xFF, 0xE0]), isTrue, reason: 'APP0 kept');
      expect(_contains(out, [0x4A, 0x46, 0x49, 0x46]), isTrue, reason: 'JFIF kept');
      expect(_contains(out, [0x11, 0x22, 0x33]), isTrue, reason: 'pixels kept');
      expect(out.sublist(out.length - 2), [0xFF, 0xD9]);
      expect(out.length, lessThan(jpeg.length));
      expect(out.sublist(0, 2), [0xFF, 0xD8]);
    });

    test('returns input untouched when not a JPEG', () {
      final notJpeg = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(MetadataStripper.stripJpeg(notJpeg), notJpeg);
    });
  });

  group('MetadataStripper.stripPng (lossless)', () {
    test('removes tEXt, keeps IHDR/IDAT/IEND, shrinks', () {
      int b0(int v) => (v >> 24) & 0xFF;
      int b1(int v) => (v >> 16) & 0xFF;
      int b2(int v) => (v >> 8) & 0xFF;
      int b3(int v) => v & 0xFF;
      List<int> chunk(String type, List<int> data) => [
            b0(data.length), b1(data.length), b2(data.length), b3(data.length),
            ...type.codeUnits,
            ...data,
            0, 0, 0, 0, // crc (unchecked by the stripper)
          ];
      final png = Uint8List.fromList([
        137, 80, 78, 71, 13, 10, 26, 10, // sig
        ...chunk('IHDR', [0, 0]),
        ...chunk('tEXt', [65, 66, 67]),
        ...chunk('IDAT', [9]),
        ...chunk('IEND', const []),
      ]);
      final out = MetadataStripper.stripPng(png);

      expect(_contains(out, 'tEXt'.codeUnits), isFalse);
      expect(_contains(out, 'IHDR'.codeUnits), isTrue);
      expect(_contains(out, 'IDAT'.codeUnits), isTrue);
      expect(_contains(out, 'IEND'.codeUnits), isTrue);
      expect(out.length, lessThan(png.length));
      expect(out.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    });
  });
}
