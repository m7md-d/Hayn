import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/features/image_ops/data/image_probe.dart';
import 'package:hayn/features/image_ops/data/metadata.dart';

void main() {
  group('ImageProbe.sniff', () {
    test('detects formats by magic bytes', () {
      Uint8List pad(List<int> head) =>
          Uint8List.fromList([...head, ...List.filled(16, 0)]);
      expect(ImageProbe.sniff(pad([0xFF, 0xD8, 0xFF])), SniffedFormat.jpeg);
      expect(
        ImageProbe.sniff(pad([0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10])),
        SniffedFormat.png,
      );
      expect(
        ImageProbe.sniff(pad([0x47, 0x49, 0x46, 0x38])),
        SniffedFormat.gif,
      );
      expect(
        ImageProbe.sniff(
          Uint8List.fromList([
            0x52,
            0x49,
            0x46,
            0x46,
            0,
            0,
            0,
            0,
            0x57,
            0x45,
            0x42,
            0x50,
          ]),
        ),
        SniffedFormat.webp,
      );
      // ISO-BMFF: ....ftyp + brand
      expect(
        ImageProbe.sniff(
          Uint8List.fromList([
            0, 0, 0, 0, //
            0x66, 0x74, 0x79, 0x70, // 'ftyp'
            0x68, 0x65, 0x69, 0x63, // 'heic'
            0, 0, 0, 0, // minor version
          ]),
        ),
        SniffedFormat.heic,
      );
      expect(
        ImageProbe.sniff(Uint8List.fromList(List.filled(20, 0x7A))),
        SniffedFormat.unknown,
      );
    });
  });

  group('MetadataStripper gates (lossless-only, never re-encode)', () {
    Uint8List pad(List<int> head) =>
        Uint8List.fromList([...head, ...List.filled(16, 0)]);

    final jpeg = pad([0xFF, 0xD8, 0xFF]);
    final png = pad([0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10]);
    final webp = Uint8List.fromList([
      0x52,
      0x49,
      0x46,
      0x46,
      0,
      0,
      0,
      0,
      0x57,
      0x45,
      0x42,
      0x50,
    ]);
    final heic = Uint8List.fromList([
      0, 0, 0, 0, //
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      0x68, 0x65, 0x69, 0x63, // 'heic'
      0, 0, 0, 0, // minor version
    ]);
    final avif = Uint8List.fromList([
      0, 0, 0, 0, //
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      0x61, 0x76, 0x69, 0x66, // 'avif'
      0, 0, 0, 0, // minor version
    ]);
    final unknown = pad([0x7A, 0x7A, 0x7A]);

    test('canStrip admits every pipeline format incl. HEIC/AVIF (DarkLib)', () {
      expect(MetadataStripper.canStrip(jpeg), isTrue);
      expect(MetadataStripper.canStrip(png), isTrue);
      expect(MetadataStripper.canStrip(webp), isTrue);
      // HEIC/AVIF are stripped losslessly by DarkLib (ISOBMFF item surgery) —
      // the entry-point gate must let them reach the task, not pre-reject them.
      expect(MetadataStripper.canStrip(heic), isTrue);
      expect(MetadataStripper.canStrip(avif), isTrue);
      // No lossless editor anywhere → gated out, never re-encoded.
      expect(MetadataStripper.canStrip(unknown), isFalse);
    });
  });
}
