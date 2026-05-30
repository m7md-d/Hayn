import 'dart:typed_data';

import 'package:exif/exif.dart';

import 'image_probe.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Metadata read + strip.
//
// Reading (for "here's what will be removed"): a header parse via package:exif,
// so it works even for HEIC (where a full pixel decode isn't available).
//
// Stripping is LOSSLESS-ONLY — it NEVER re-encodes (that would change quality
// and, for already-efficient formats like HEIC, INFLATE the file). It edits the
// container in place:
//   • JPEG → drop APP1/APP13/APP14/COM segments, keep JFIF/ICC + scan verbatim.
//   • PNG  → drop text/eXIf/tIME ancillary chunks, keep IHDR/IDAT/IEND + colour.
//   • WebP → drop the EXIF/"XMP " RIFF chunks + clear their VP8X flag bits.
// Formats with no safe pure-Dart container editor (HEIC/HEIF, AVIF, and the
// rest) are reported as UNSUPPORTED via a null result — the caller skips them
// rather than degrading the image. (Lossless HEIC stripping needs the native
// metadata writer that the Surgical phase will bring.)
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown by [StripMetadataTask] when nothing could be stripped because every
/// input was in a format we can't strip losslessly yet (e.g. iPhone HEIC). The
/// UI maps this to a helpful, localised hint instead of a raw error string.
class StripUnsupportedFormat implements Exception {
  const StripUnsupportedFormat();
}

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
  /// Returns metadata-free bytes (+ the extension to save under, since the
  /// format is preserved byte-compatibly), or NULL when the format has no
  /// lossless pure-Dart stripper (HEIC/AVIF/etc) — the caller must skip it,
  /// never re-encode. Pure + synchronous (all work is byte surgery).
  /// Whether [bytes] is a format we can strip LOSSLESSLY (JPEG/PNG/WebP).
  /// Cheap (magic-byte sniff only) — lets callers warn up front before
  /// enqueuing a task that would otherwise skip the file.
  static bool canStrip(Uint8List bytes) => switch (ImageProbe.sniff(bytes)) {
        SniffedFormat.jpeg ||
        SniffedFormat.png ||
        SniffedFormat.webp =>
          true,
        _ => false,
      };

  static ({Uint8List bytes, String ext})? strip(Uint8List bytes) {
    switch (ImageProbe.sniff(bytes)) {
      case SniffedFormat.jpeg:
        return (bytes: stripJpeg(bytes), ext: 'jpg');
      case SniffedFormat.png:
        return (bytes: stripPng(bytes), ext: 'png');
      case SniffedFormat.webp:
        return (bytes: stripWebp(bytes), ext: 'webp');
      case SniffedFormat.heic:
      case SniffedFormat.avif:
      case SniffedFormat.gif:
      case SniffedFormat.bmp:
      case SniffedFormat.tiff:
      case SniffedFormat.unknown:
        return null; // No lossless editor — skip, don't degrade.
    }
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

  // ── Lossless WebP strip ────────────────────────────────────────────────
  // RIFF container: 'RIFF' <u32 size> 'WEBP' then FourCC-tagged chunks (each
  // u32 little-endian size, payload padded to even length). Metadata lives in
  // the 'EXIF' and 'XMP ' chunks — drop them, and clear the matching flag bits
  // in the VP8X extended header (EXIF=0x08, XMP=0x04) so the file stays valid.
  // The coded image chunks (VP8/VP8L/ALPH/ANMF…) are copied byte-for-byte. On
  // any malformation we return the input untouched.
  static Uint8List stripWebp(Uint8List b) {
    if (b.length < 16) return b;
    bool tag(int o, String s) {
      for (var k = 0; k < 4; k++) {
        if (b[o + k] != s.codeUnitAt(k)) return false;
      }
      return true;
    }

    if (!tag(0, 'RIFF') || !tag(8, 'WEBP')) return b;

    final body = BytesBuilder();
    var i = 12;
    var changed = false;
    while (i + 8 <= b.length) {
      final fourcc = String.fromCharCodes(b.sublist(i, i + 4));
      final size = b[i + 4] | (b[i + 5] << 8) | (b[i + 6] << 16) | (b[i + 7] << 24);
      if (size < 0) return b;
      final padded = size + (size.isOdd ? 1 : 0);
      final chunkEnd = i + 8 + padded;
      if (chunkEnd > b.length) return b;

      if (fourcc == 'EXIF' || fourcc == 'XMP ') {
        changed = true; // drop the whole chunk (header + payload + pad)
      } else if (fourcc == 'VP8X' && size >= 1) {
        // Clear EXIF (0x08) and XMP (0x04) flag bits in the first payload byte.
        final chunk = Uint8List.fromList(b.sublist(i, chunkEnd));
        final cleared = chunk[8] & ~0x0C;
        if (cleared != chunk[8]) {
          chunk[8] = cleared;
          changed = true;
        }
        body.add(chunk);
      } else {
        body.add(b.sublist(i, chunkEnd));
      }
      i = chunkEnd;
    }
    if (!changed) return b;

    final bodyBytes = body.toBytes();
    final out = BytesBuilder()
      ..add('RIFF'.codeUnits);
    final riffSize = 4 + bodyBytes.length; // 'WEBP' + chunks
    out.add([
      riffSize & 0xFF,
      (riffSize >> 8) & 0xFF,
      (riffSize >> 16) & 0xFF,
      (riffSize >> 24) & 0xFF,
    ]);
    out
      ..add('WEBP'.codeUnits)
      ..add(bodyBytes);
    return out.toBytes();
  }
}
