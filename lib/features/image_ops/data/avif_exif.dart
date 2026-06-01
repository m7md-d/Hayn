import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, visibleForTesting;

// ─────────────────────────────────────────────────────────────────────────────
// AvifExif — fixes the orientation of a flutter_avif output.
//
// flutter_avif bakes the EXIF orientation into the pixels (it decodes via
// ui.instantiateImageCodec, which applies orientation) AND — when keepExif is
// on — embeds the ORIGINAL Orientation tag too. Viewers then rotate a second
// time, so a portrait photo comes out sideways. Since the pixels are already
// upright, the correct tag is 1. So we keep keepExif (preserving camera /
// exposure / GPS) and just rewrite the embedded TIFF Orientation (tag 0x0112)
// to 1, leaving every other value intact.
//
// Safety: this walks the real ISO-BMFF item table (meta → iinf/iloc) to locate
// the Exif item — no blind scanning of pixel data — and only flips a single
// 2-byte value AFTER validating it's a SHORT Orientation entry holding 1..8. On
// ANYTHING unexpected it returns the input unchanged. The original photo is
// never touched (compress always writes a new asset), so the worst case is "no
// fix applied", never a corrupt file.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class AvifExif {
  /// Set the embedded EXIF Orientation to 1. Returns the input unchanged if the
  /// Exif item / Orientation tag can't be confidently located.
  static Uint8List normalizeOrientation(Uint8List avif) {
    try {
      final tiffStart = _locateExifTiff(avif);
      if (tiffStart == null) {
        if (kDebugMode) debugPrint('hayn/avif: Exif item not found — no fix');
        return avif;
      }
      final copy = Uint8List.fromList(avif);
      final ok = setTiffOrientation(copy, tiffStart, 1);
      if (kDebugMode) {
        debugPrint('hayn/avif: orientation patch ${ok ? "applied" : "skipped"}');
      }
      return ok ? copy : avif;
    } catch (e) {
      if (kDebugMode) debugPrint('hayn/avif: patch error $e');
      return avif;
    }
  }

  // ── ISO-BMFF: locate the Exif item's TIFF header ────────────────────────────
  static int? _locateExifTiff(Uint8List b) {
    final meta = _findBox(b, 0, b.length, 'meta');
    if (meta == null) return null;
    // 'meta' is a FullBox: its child boxes start after the 4-byte version/flags.
    final childrenStart = meta.contentStart + 4;
    final iinf = _findBox(b, childrenStart, meta.end, 'iinf');
    final iloc = _findBox(b, childrenStart, meta.end, 'iloc');
    if (iinf == null || iloc == null) return null;
    // Some muxers store small items (EXIF) inside an 'idat' box rather than
    // 'mdat' (iloc construction_method == 1); offsets are then idat-relative.
    final idat = _findBox(b, childrenStart, meta.end, 'idat');
    final idatStart = idat?.contentStart ?? 0;

    final exifId = _exifItemId(b, iinf);
    if (exifId == null) return null;

    final extent = _itemExtent(b, iloc, exifId, idatStart);
    if (extent == null) return null;
    final (off, len) = extent;
    if (off < 0 || len < 8 || off + len > b.length) return null;

    // ExifDataBlock = uint32 exif_tiff_header_offset, then the TIFF block.
    final headerOffset = _u32(b, off);
    final tiffStart = off + 4 + headerOffset;
    if (tiffStart < 0 || tiffStart + 8 > b.length) return null;
    return tiffStart;
  }

  /// Scan the iinf entries for the item whose type is "Exif"; return its id.
  static int? _exifItemId(Uint8List b, _Box iinf) {
    final version = b[iinf.contentStart];
    var p = iinf.contentStart + 4; // skip version + flags
    if (version == 0) {
      p += 2; // entry_count u16
    } else {
      p += 4; // entry_count u32
    }
    while (p + 8 <= iinf.end) {
      final infe = _boxAt(b, p, iinf.end);
      if (infe == null || infe.type != 'infe') break;
      final v = b[infe.contentStart];
      final base = infe.contentStart + 4; // after version+flags
      int? id;
      int typePos;
      if (v == 2) {
        id = _u16(b, base);
        typePos = base + 4; // id(2) + protection(2)
      } else if (v == 3) {
        id = _u32(b, base);
        typePos = base + 6; // id(4) + protection(2)
      } else {
        p = infe.end;
        continue;
      }
      if (typePos + 4 <= b.length &&
          String.fromCharCodes(b, typePos, typePos + 4) == 'Exif') {
        return id;
      }
      p = infe.end;
    }
    return null;
  }

  /// Resolve the (absolute offset, length) of [itemId]'s first extent.
  /// [idatStart] is the content offset of the 'idat' box (0 if none), used when
  /// the item's construction_method is 1 (idat-relative).
  static (int, int)? _itemExtent(
      Uint8List b, _Box iloc, int itemId, int idatStart) {
    final version = b[iloc.contentStart];
    var p = iloc.contentStart + 4; // after version + flags
    final offsetSize = b[p] >> 4;
    final lengthSize = b[p] & 0x0F;
    final baseOffsetSize = b[p + 1] >> 4;
    final indexSize = b[p + 1] & 0x0F;
    p += 2;
    final int itemCount;
    if (version < 2) {
      itemCount = _u16(b, p);
      p += 2;
    } else {
      itemCount = _u32(b, p);
      p += 4;
    }

    for (var i = 0; i < itemCount; i++) {
      final int id;
      if (version < 2) {
        id = _u16(b, p);
        p += 2;
      } else {
        id = _u32(b, p);
        p += 4;
      }
      var constructionMethod = 0;
      if (version == 1 || version == 2) {
        constructionMethod = _u16(b, p) & 0x0F;
        p += 2;
      }
      p += 2; // data_reference_index
      final baseOffset = _uint(b, p, baseOffsetSize);
      p += baseOffsetSize;
      final extentCount = _u16(b, p);
      p += 2;

      int? foundOffset;
      int? foundLength;
      for (var e = 0; e < extentCount; e++) {
        if ((version == 1 || version == 2) && indexSize > 0) {
          p += indexSize; // extent_index
        }
        final extentOffset = _uint(b, p, offsetSize);
        p += offsetSize;
        final extentLength = _uint(b, p, lengthSize);
        p += lengthSize;
        if (e == 0) {
          foundOffset = extentOffset;
          foundLength = extentLength;
        }
      }

      if (id == itemId && foundOffset != null && foundLength != null) {
        if (constructionMethod == 0) {
          return (baseOffset + foundOffset, foundLength); // file offset
        } else if (constructionMethod == 1) {
          return (idatStart + baseOffset + foundOffset, foundLength); // idat
        }
      }
    }
    return null;
  }

  // ── TIFF: set the Orientation entry to [value] ──────────────────────────────
  /// Patch IFD0's Orientation (tag 0x0112) to [value], in place. Returns true
  /// only if a valid SHORT Orientation entry (current value 1..8) was found.
  @visibleForTesting
  static bool setTiffOrientation(Uint8List b, int tiffStart, int value) {
    if (tiffStart + 8 > b.length) return false;
    final bool big;
    if (b[tiffStart] == 0x4D && b[tiffStart + 1] == 0x4D) {
      big = true;
    } else if (b[tiffStart] == 0x49 && b[tiffStart + 1] == 0x49) {
      big = false;
    } else {
      return false;
    }
    if (_u16e(b, tiffStart + 2, big) != 42) return false;
    final ifd0 = tiffStart + _u32e(b, tiffStart + 4, big);
    if (ifd0 + 2 > b.length) return false;
    final count = _u16e(b, ifd0, big);
    final entriesStart = ifd0 + 2;
    if (entriesStart + count * 12 > b.length) return false;

    for (var i = 0; i < count; i++) {
      final e = entriesStart + i * 12;
      if (_u16e(b, e, big) != 0x0112) continue; // Orientation
      final type = _u16e(b, e + 2, big);
      final cnt = _u32e(b, e + 4, big);
      if (type != 3 || cnt != 1) return false; // expect SHORT × 1
      final cur = _u16e(b, e + 8, big);
      if (cur < 1 || cur > 8) return false;
      _setU16e(b, e + 8, value, big);
      return true;
    }
    return false;
  }

  // ── Box helpers ─────────────────────────────────────────────────────────────
  static _Box? _findBox(Uint8List b, int from, int to, String type) {
    var p = from;
    while (p + 8 <= to) {
      final box = _boxAt(b, p, to);
      if (box == null) break;
      if (box.type == type) return box;
      p = box.end;
    }
    return null;
  }

  static _Box? _boxAt(Uint8List b, int p, int to) {
    if (p + 8 > to) return null;
    var size = _u32(b, p);
    var header = 8;
    int end;
    if (size == 1) {
      if (p + 16 > to) return null;
      size = _u64(b, p + 8);
      header = 16;
      end = p + size;
    } else if (size == 0) {
      end = to;
    } else {
      end = p + size;
    }
    if (end <= p + header || end > to) return null;
    final type = String.fromCharCodes(b, p + 4, p + 8);
    return _Box(type, p + header, end);
  }

  // ── Numeric readers (big-endian for ISO-BMFF; endian-aware for TIFF) ─────────
  static int _uint(Uint8List b, int p, int size) {
    var v = 0;
    for (var i = 0; i < size; i++) {
      v = (v << 8) | b[p + i];
    }
    return v;
  }

  static int _u16(Uint8List b, int p) => (b[p] << 8) | b[p + 1];
  static int _u32(Uint8List b, int p) =>
      (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3];
  static int _u64(Uint8List b, int p) => (_u32(b, p) << 32) | _u32(b, p + 4);

  static int _u16e(Uint8List b, int p, bool big) =>
      big ? (b[p] << 8) | b[p + 1] : (b[p + 1] << 8) | b[p];
  static int _u32e(Uint8List b, int p, bool big) => big
      ? (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3]
      : (b[p + 3] << 24) | (b[p + 2] << 16) | (b[p + 1] << 8) | b[p];
  static void _setU16e(Uint8List b, int p, int v, bool big) {
    if (big) {
      b[p] = (v >> 8) & 0xFF;
      b[p + 1] = v & 0xFF;
    } else {
      b[p] = v & 0xFF;
      b[p + 1] = (v >> 8) & 0xFF;
    }
  }
}

class _Box {
  const _Box(this.type, this.contentStart, this.end);
  final String type;
  final int contentStart; // first byte after the box header
  final int end; // exclusive
}
