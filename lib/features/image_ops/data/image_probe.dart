import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../../core/darklib/darklib.dart';
import 'native_image_info.dart';

// Alpha inspection is tri-state: true = present, false = confirmed absent,
// null = unknown. Unknown must never authorize an opaque target or fallback.
// Channel presence is conservative; it does not prove per-pixel equivalence.
//
// The container answers first (DarkLib `inspect`, no decode): PNG colour type
// and tRNS, WebP alpha, the AVIF/HEIF alpha auxiliary. Decoding in Dart cost
// seconds per 12 MP image and misreported every lossy WebP as transparent:
// package:image allocates four channels for VP8 (IMG-16, PERF-01).

enum SniffedFormat { jpeg, png, webp, gif, bmp, tiff, heic, avif, unknown }

abstract final class ImageProbe {
  /// Inspect alpha off the UI isolate. Unavailable or failed probes stay null.
  static Future<bool?> hasAlpha(Uint8List bytes) async {
    final format = sniff(bytes);
    if (format != SniffedFormat.jpeg && format != SniffedFormat.unknown) {
      switch ((await DarkLibCore.inspect(bytes))?.alpha) {
        case Presence.present:
          return true;
        case Presence.absent:
          return false;
        case Presence.unknown || null:
          break; // unreadable container or no DarkLib: the fallbacks below
      }
    }
    switch (format) {
      case SniffedFormat.jpeg:
        return false;
      case SniffedFormat.heic:
      case SniffedFormat.avif:
        return NativeImageProbe.probeAlpha(bytes);
      case SniffedFormat.unknown:
        return null;
      case SniffedFormat.png:
      case SniffedFormat.webp:
      case SniffedFormat.gif:
      case SniffedFormat.bmp:
      case SniffedFormat.tiff:
        return Isolate.run(() {
          try {
            return img.decodeImage(bytes)?.hasAlpha;
          } catch (_) {
            // The caller retains unknown rather than inventing source facts.
            return null;
          }
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
    // A generic HEIF major brand can advertise AVIF in compatible brands.
    if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
      if (b.length < 16) return SniffedFormat.unknown;
      final size = ByteData.sublistView(b).getUint32(0);
      final end = size == 0 ? b.length : size;
      if (end < 16 || end > 4096 || end > b.length || (end - 16) % 4 != 0) {
        return SniffedFormat.unknown;
      }
      final brands = <String>{String.fromCharCodes(b.sublist(8, 12))};
      for (var at = 16; at < end; at += 4) {
        brands.add(String.fromCharCodes(b.sublist(at, at + 4)));
      }
      if (brands.contains('avif') || brands.contains('avis')) {
        return SniffedFormat.avif;
      }
      if (brands.any(
        const {'heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'}.contains,
      )) {
        return SniffedFormat.heic;
      }
    }
    return SniffedFormat.unknown;
  }
}
