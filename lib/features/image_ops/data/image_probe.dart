import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────────────────────────
// ImageProbe — answers the one question the format policy needs: does this
// image carry transparency? Getting it right is a safety matter (an alpha
// image must never be flattened to JPEG — CLAUDE.md §2).
//
// Strategy:
//   • Sniff the container by magic bytes first. JPEG can never hold alpha, so
//     we answer instantly without decoding.
//   • For alpha-capable raster containers (PNG/WebP/GIF/BMP/TIFF) decode in a
//     background isolate and report whether an alpha channel is present
//     (channel-presence, not a full pixel scan — cheaper and conservatively
//     safe: an opaque PNG simply takes the alpha-safe path, losing nothing).
//   • HEIC/AVIF aren't decodable by package:image; camera shots in those
//     containers are opaque, so we report false (treating every iPhone HEIC as
//     "maybe alpha" would wrongly block JPEG for the whole library). True alpha
//     HEIC/AVIF is rare and still encodes fine via the alpha-safe auto tree.
// ─────────────────────────────────────────────────────────────────────────────

enum SniffedFormat { jpeg, png, webp, gif, bmp, tiff, heic, avif, unknown }

abstract final class ImageProbe {
  /// True if the image has (or, for undecodable alpha-capable containers, may
  /// have) transparency. Decodes off the main isolate.
  static Future<bool> hasAlpha(Uint8List bytes) async {
    switch (sniff(bytes)) {
      case SniffedFormat.jpeg:
      case SniffedFormat.heic:
      case SniffedFormat.avif:
        return false;
      case SniffedFormat.unknown:
        return false;
      case SniffedFormat.png:
      case SniffedFormat.webp:
      case SniffedFormat.gif:
      case SniffedFormat.bmp:
      case SniffedFormat.tiff:
        return Isolate.run(() {
          final decoded = img.decodeImage(bytes);
          // Undecodable but alpha-capable container → assume alpha (safe).
          return decoded?.hasAlpha ?? true;
        });
    }
  }

  /// Identify the container from its leading magic bytes. Pure + synchronous.
  static SniffedFormat sniff(Uint8List b) {
    if (b.length < 12) return SniffedFormat.unknown;

    // JPEG: FF D8 FF
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return SniffedFormat.jpeg;
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return SniffedFormat.png;
    }
    // GIF: "GIF8"
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) {
      return SniffedFormat.gif;
    }
    // BMP: "BM"
    if (b[0] == 0x42 && b[1] == 0x4D) return SniffedFormat.bmp;
    // TIFF: "II*\0" or "MM\0*"
    if ((b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A && b[3] == 0x00) ||
        (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0x00 && b[3] == 0x2A)) {
      return SniffedFormat.tiff;
    }
    // RIFF....WEBP
    if (b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return SniffedFormat.webp;
    }
    // ISO-BMFF "ftyp" box at offset 4; brand at 8..11 distinguishes HEIC/AVIF.
    if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
      final brand = String.fromCharCodes(b.sublist(8, 12));
      if (brand.startsWith('avif') || brand.startsWith('avis')) {
        return SniffedFormat.avif;
      }
      if (brand.startsWith('heic') ||
          brand.startsWith('heix') ||
          brand.startsWith('mif1') ||
          brand.startsWith('hevc') ||
          brand.startsWith('msf1')) {
        return SniffedFormat.heic;
      }
    }
    return SniffedFormat.unknown;
  }
}
