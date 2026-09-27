import 'package:flutter/services.dart';

import '../../../core/diagnostics/media_diagnostics.dart';

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

  /// HDR reported by the native gain-map / transfer-function probe. Bit depth
  /// alone does not imply HDR.
  final bool isHdr;

  /// "RGB", "Gray", … (informational).
  final String colorModel;
}

abstract final class NativeImageProbe {
  static const MethodChannel channel = MethodChannel('hayn/metadata');

  /// Read just this fact; a partial response does not imply opaque pixels.
  static Future<bool?> probeAlpha(Uint8List bytes) async {
    final value = (await _read(bytes))?['hasAlpha'];
    return value is bool ? value : null;
  }

  static Future<NativeImageInfo?> probe(Uint8List bytes) async {
    final res = await _read(bytes);
    final depth = res?['bitDepth'];
    final alpha = res?['hasAlpha'];
    final hdr = res?['isHdr'];
    if (depth is! num || depth <= 0 || alpha is! bool || hdr is! bool) {
      return null;
    }
    return NativeImageInfo(
      bitDepth: depth.toInt(),
      hasAlpha: alpha,
      isHdr: hdr,
      colorModel: res?['colorModel'] as String? ?? '',
    );
  }

  static Future<Map<String, dynamic>?> _read(Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    try {
      return await channel.invokeMapMethod<String, dynamic>(
        'probeImage',
        <String, dynamic>{'bytes': bytes},
      );
    } on MissingPluginException {
      return null; // A platform without this probe has unknown facts.
    } catch (_) {
      MediaDiagnostics.record(
        MediaBackend.imageIO,
        MediaOperation.probe,
        MediaDiagnosticCode.exception,
      );
      return null;
    }
  }
}
