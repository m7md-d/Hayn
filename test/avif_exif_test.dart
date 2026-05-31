import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/features/image_ops/data/avif_exif.dart';

// Build a minimal TIFF block with a single IFD0 Orientation (0x0112) entry of
// the given value, in big- or little-endian byte order.
Uint8List _tiff({required bool big, required int orientation}) {
  final b = BytesBuilder();
  void u16(int v) => big
      ? b.add([(v >> 8) & 0xFF, v & 0xFF])
      : b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(int v) => big
      ? b.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF])
      : b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  b.add(big ? [0x4D, 0x4D] : [0x49, 0x49]); // byte order
  u16(42); // magic
  u32(8); // IFD0 right after the 8-byte header
  u16(1); // one entry
  u16(0x0112); // Orientation tag
  u16(3); // type SHORT
  u32(1); // count 1
  // value field is 4 bytes; a SHORT lives in the first 2.
  u16(orientation);
  u16(0); // padding
  return b.toBytes();
}

int _readOrientation(Uint8List b, bool big) =>
    big ? (b[18] << 8) | b[19] : (b[19] << 8) | b[18];

void main() {
  group('AvifExif.setTiffOrientation', () {
    test('rewrites a big-endian Orientation to 1', () {
      final b = _tiff(big: true, orientation: 6);
      expect(AvifExif.setTiffOrientation(b, 0, 1), isTrue);
      expect(_readOrientation(b, true), 1);
    });

    test('rewrites a little-endian Orientation to 1', () {
      final b = _tiff(big: false, orientation: 8);
      expect(AvifExif.setTiffOrientation(b, 0, 1), isTrue);
      expect(_readOrientation(b, false), 1);
    });

    test('leaves other bytes untouched (only the value field changes)', () {
      final b = _tiff(big: true, orientation: 3);
      final before = Uint8List.fromList(b);
      AvifExif.setTiffOrientation(b, 0, 1);
      for (var i = 0; i < b.length; i++) {
        if (i == 18 || i == 19) continue; // the orientation value
        expect(b[i], before[i], reason: 'byte $i must be unchanged');
      }
    });

    test('refuses a non-TIFF block', () {
      final junk = Uint8List.fromList(List.filled(32, 0xAB));
      expect(AvifExif.setTiffOrientation(junk, 0, 1), isFalse);
    });

    test('refuses when there is no Orientation entry', () {
      final b = _tiff(big: true, orientation: 1);
      // Corrupt the tag id so no Orientation entry exists.
      b[10] = 0x00;
      b[11] = 0x01; // tag 0x0001 instead of 0x0112
      expect(AvifExif.setTiffOrientation(b, 0, 1), isFalse);
    });

    test('normalizeOrientation returns input unchanged for non-AVIF bytes', () {
      final junk = Uint8List.fromList(List.filled(64, 0x11));
      expect(AvifExif.normalizeOrientation(junk), same(junk));
    });
  });
}
