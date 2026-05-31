import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NativeImageProbe — reads an image's REAL bit depth, alpha-channel presence and
// HDR status straight from ImageIO (iOS). This is accurate for HEIC (which
// package:image can't decode) and reflects what the file ACTUALLY contains — we
// never infer alpha/depth from the container type alone. Returns null off-iOS or
// on any failure. Never throws.
// ─────────────────────────────────────────────────────────────────────────────

class NativeImageInfo {
  const NativeImageInfo({
    required this.bitDepth,
    required this.hasAlpha,
    required this.isHdr,
    required this.colorModel,
  });

  /// Bits per colour component (8 = SDR, 10/16 = deep / HDR-capable).
  final int bitDepth;

  /// A real alpha channel is present (from ImageIO, not the container type).
  final bool hasAlpha;

  /// The photo carries HDR — an Apple gain map is attached, or the pixels are
  /// deeper than 8-bit.
  final bool isHdr;

  /// "RGB", "Gray", … (informational).
  final String colorModel;
}

abstract final class NativeImageProbe {
  static const MethodChannel channel = MethodChannel('hayn/metadata');

  static Future<NativeImageInfo?> probe(Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    try {
      final res = await channel.invokeMapMethod<String, dynamic>(
        'probeImage',
        <String, dynamic>{'bytes': bytes},
      );
      if (res == null) return null;
      return NativeImageInfo(
        bitDepth: (res['bitDepth'] as num?)?.toInt() ?? 8,
        hasAlpha: (res['hasAlpha'] as bool?) ?? false,
        isHdr: (res['isHdr'] as bool?) ?? false,
        colorModel: (res['colorModel'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
