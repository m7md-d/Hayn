import 'dart:typed_data';

import 'package:exif/exif.dart';

import '../../settings/providers/preferences_providers.dart';
import 'image_encoder.dart';
import 'image_probe.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Metadata read + strip.
//
// Reading (for "here's what will be removed"): a header parse via package:exif,
// so it works even for HEIC (where a full pixel decode isn't available).
//
// Stripping honours the golden rule (no needless re-encode):
//   • JPEG / PNG → LOSSLESS segment/chunk surgery: drop the metadata
//     blocks (EXIF/XMP/IPTC/comments, PNG text/eXIf) and keep the pixel data
//     and colour profile byte-for-byte.
//   • HEIC / WebP / AVIF → re-encode once at high quality with metadata off
//     (no lossless container editor available without native code).
//   • anything else → returned untouched.
// ─────────────────────────────────────────────────────────────────────────────

class MetadataSummary {
  const MetadataSummary({
    required this.hasGps,
    required this.hasDate,
    required this.hasCamera,
    required this.tagCount,
  });

  final bool hasGps;
  final bool hasDate;
  final bool hasCamera;
  final int tagCount;

  bool get isEmpty => tagCount == 0;

  static const empty = MetadataSummary(
    hasGps: false,
    hasDate: false,
    hasCamera: false,
    tagCount: 0,
  );
}

abstract final class MetadataReader {
  static Future<MetadataSummary> read(Uint8List bytes) async {
    try {
      final tags = await readExifFromBytes(bytes);
      if (tags.isEmpty) return MetadataSummary.empty;
      bool any(bool Function(String) p) => tags.keys.any(p);
      return MetadataSummary(
        hasGps: any((k) => k.startsWith('GPS')),
        hasDate: any((k) => k.contains('DateTime')),
        hasCamera:
            tags.containsKey('Image Make') || tags.containsKey('Image Model'),
        tagCount: tags.length,
      );
    } catch (_) {
      return MetadataSummary.empty;
    }
  }
}

abstract final class MetadataStripper {
  /// Returns metadata-free bytes (+ the file extension to save under, since the
  /// format is preserved).
  static Future<({Uint8List bytes, String ext})> strip(Uint8List bytes) async {
    switch (ImageProbe.sniff(bytes)) {
      case SniffedFormat.jpeg:
        return (bytes: stripJpeg(bytes), ext: 'jpg');
      case SniffedFormat.png:
        return (bytes: stripPng(bytes), ext: 'png');
      case SniffedFormat.heic:
        return (bytes: await _reencode(bytes, DefaultFormat.heic), ext: 'heic');
      case SniffedFormat.webp:
        return (bytes: await _reencode(bytes, DefaultFormat.webp), ext: 'webp');
      case SniffedFormat.avif:
        return (bytes: await _reencode(bytes, DefaultFormat.avif), ext: 'avif');
      case SniffedFormat.gif:
      case SniffedFormat.bmp:
      case SniffedFormat.tiff:
      case SniffedFormat.unknown:
        return (bytes: bytes, ext: 'jpg');
    }
  }

  static Future<Uint8List> _reencode(Uint8List bytes, DefaultFormat fmt) async {
    final hasAlpha = await ImageProbe.hasAlpha(bytes);
    final out = await ImageEncoder.encode(
      source: bytes,
      target: fmt,
      quality: 95,
      hasAlpha: hasAlpha,
      keepMetadata: false,
    );
    return out.bytes;
  }

  // ── Lossless JPEG strip ────────────────────────────────────────────────
  // Drop APP1 (EXIF/XMP), APP13 (IPTC/Photoshop), APP14 (Adobe) and COM; keep
  // APP0 (JFIF), APP2 (ICC) and all coding segments. On any malformation we
  // return the input untouched (never risk corrupting the image).
  static Uint8List stripJpeg(Uint8List b) {
    if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return b;
    const drop = {0xE1, 0xED, 0xEE, 0xFE};
    final out = BytesBuilder()..add([0xFF, 0xD8]);
    var i = 2;
    while (i + 1 < b.length) {
      if (b[i] != 0xFF) return b;
      var marker = b[i + 1];
      while (marker == 0xFF && i + 2 < b.length) {
        i++;
        marker = b[i + 1];
      }
      if (marker == 0xDA) {
        // Start of scan: entropy-coded data + EOI follow — copy verbatim.
        out.add(b.sublist(i));
        return out.toBytes();
      }
      if (marker == 0xD9) {
        out.add([0xFF, 0xD9]);
        return out.toBytes();
      }
      if (i + 4 > b.length) return b;
      final len = (b[i + 2] << 8) | b[i + 3];
      final segEnd = i + 2 + len;
      if (len < 2 || segEnd > b.length) return b;
      if (!drop.contains(marker)) out.add(b.sublist(i, segEnd));
      i = segEnd;
    }
    return b;
  }

  // ── Lossless PNG strip ─────────────────────────────────────────────────
  // Drop text/timestamp/EXIF ancillary chunks; keep IHDR/PLTE/IDAT/IEND and
  // colour chunks (gAMA/cHRM/iCCP/sRGB) untouched.
  static Uint8List stripPng(Uint8List b) {
    const sig = [137, 80, 78, 71, 13, 10, 26, 10];
    if (b.length < 8) return b;
    for (var k = 0; k < 8; k++) {
      if (b[k] != sig[k]) return b;
    }
    const drop = {'tEXt', 'zTXt', 'iTXt', 'eXIf', 'tIME'};
    final out = BytesBuilder()..add(b.sublist(0, 8));
    var i = 8;
    while (i + 8 <= b.length) {
      final len =
          (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
      if (len < 0) return b;
      final type = String.fromCharCodes(b.sublist(i + 4, i + 8));
      final chunkEnd = i + 12 + len; // length(4)+type(4)+data(len)+crc(4)
      if (chunkEnd > b.length) return b;
      if (!drop.contains(type)) out.add(b.sublist(i, chunkEnd));
      if (type == 'IEND') break;
      i = chunkEnd;
    }
    return out.toBytes();
  }
}
