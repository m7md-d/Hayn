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

  group('MetadataStripper.stripWebp (lossless)', () {
    List<int> u32le(int v) =>
        [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
    List<int> chunk(String cc, List<int> data) {
      final out = [...cc.codeUnits, ...u32le(data.length), ...data];
      if (data.length.isOdd) out.add(0); // RIFF pads odd-length payloads
      return out;
    }

    test('drops EXIF + XMP chunks, clears VP8X flag bits, keeps VP8 + shrinks',
        () {
      final body = [
        // VP8X with EXIF(0x08)+XMP(0x04) flag bits set.
        ...chunk('VP8X', [0x0C, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ...chunk('VP8 ', [1, 2, 3, 4]), // coded image — must survive
        ...chunk('EXIF', [0x45, 0x78, 0x66]),
        ...chunk('XMP ', [9, 9]),
      ];
      final webp = Uint8List.fromList([
        ...'RIFF'.codeUnits,
        ...u32le(4 + body.length),
        ...'WEBP'.codeUnits,
        ...body,
      ]);

      final out = MetadataStripper.stripWebp(webp);

      expect(_contains(out, 'EXIF'.codeUnits), isFalse, reason: 'EXIF dropped');
      expect(_contains(out, 'XMP '.codeUnits), isFalse, reason: 'XMP dropped');
      expect(_contains(out, 'VP8X'.codeUnits), isTrue, reason: 'header kept');
      expect(_contains(out, 'VP8 '.codeUnits), isTrue, reason: 'pixels kept');
      // VP8X flags byte sits right after the 12-byte RIFF/WEBP header + the
      // 8-byte chunk header → index 20. Both metadata bits cleared.
      expect(out[20] & 0x0C, 0, reason: 'EXIF/XMP flag bits cleared');
      // RIFF size field == bytes after the first 8.
      final declared =
          out[4] | (out[5] << 8) | (out[6] << 16) | (out[7] << 24);
      expect(declared, out.length - 8);
      expect(out.length, lessThan(webp.length));
      expect(out.sublist(0, 4), 'RIFF'.codeUnits);
      expect(out.sublist(8, 12), 'WEBP'.codeUnits);
    });

    test('returns input untouched when not a WebP', () {
      final notWebp = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      expect(MetadataStripper.stripWebp(notWebp), notWebp);
    });
  });

  group('MetadataStripper.strip routing (lossless-only, never re-encode)', () {
    Uint8List pad(List<int> head) =>
        Uint8List.fromList([...head, ...List.filled(16, 0)]);

    test('JPEG/PNG/WebP are strippable; HEIC/unknown are skipped (null)', () {
      final jpeg = pad([0xFF, 0xD8, 0xFF]);
      final png = pad([0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10]);
      final webp = Uint8List.fromList(
          [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);
      final heic = Uint8List.fromList([
        0, 0, 0, 0, //
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x68, 0x65, 0x69, 0x63, // 'heic'
      ]);

      expect(MetadataStripper.canStrip(jpeg), isTrue);
      expect(MetadataStripper.canStrip(png), isTrue);
      expect(MetadataStripper.canStrip(webp), isTrue);
      expect(MetadataStripper.canStrip(heic), isFalse);

      // HEIC must NOT re-encode — it returns null so the caller skips it.
      expect(MetadataStripper.strip(heic), isNull);
      expect(MetadataStripper.strip(pad([0x7A, 0x7A, 0x7A])), isNull);
    });
  });
}
