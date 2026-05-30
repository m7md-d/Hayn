import '../../features/settings/providers/preferences_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BatchSavingsEstimator — predicts how many bytes a compress / surgical-replace
// run will save on a selection.
//
// Works off per-asset facts pulled from the on-device index (size + pixel
// dimensions), so it covers EVERY selected item — not just the pages currently
// loaded in the grid. Output size is modelled from dimensions × a format/
// quality bytes-per-pixel factor and capped at the original (a compression
// pass never grows a file), which tracks reality far better than a flat ratio
// of the original byte size.
// ─────────────────────────────────────────────────────────────────────────────

/// Minimal per-asset facts the estimate needs (from the index).
typedef AssetSizeFacts = ({int sizeBytes, int width, int height});

class BatchSavingsEstimate {
  const BatchSavingsEstimate({
    required this.totalOriginalBytes,
    required this.estimatedNewBytes,
    required this.savedPercent,
    required this.isApproximation,
    required this.assetCount,
  });

  final int totalOriginalBytes;
  final int estimatedNewBytes;
  final int savedPercent;

  /// Always true here: the bytes-per-pixel model is a heuristic, not a real
  /// encode.
  final bool isApproximation;
  final int assetCount;

  static const empty = BatchSavingsEstimate(
    totalOriginalBytes: 0,
    estimatedNewBytes: 0,
    savedPercent: 0,
    isApproximation: false,
    assetCount: 0,
  );
}

abstract final class BatchSavingsEstimator {
  static BatchSavingsEstimate estimate({
    required List<AssetSizeFacts> facts,
    required DefaultFormat format,
    required int quality,
  }) {
    if (facts.isEmpty) return BatchSavingsEstimate.empty;

    final bpp = bytesPerPixel(format, quality);
    var totalOriginal = 0;
    var totalOutput = 0;
    for (final f in facts) {
      totalOriginal += f.sizeBytes;
      var out = (f.width * f.height * bpp).round();
      // Compression never grows a file: cap the estimate at the original.
      if (f.sizeBytes > 0 && out > f.sizeBytes) out = f.sizeBytes;
      totalOutput += out;
    }

    final saved = (totalOriginal - totalOutput).clamp(0, totalOriginal);
    final savedPercent =
        totalOriginal == 0 ? 0 : ((saved / totalOriginal) * 100).round();

    return BatchSavingsEstimate(
      totalOriginalBytes: totalOriginal,
      estimatedNewBytes: totalOutput,
      savedPercent: savedPercent,
      isApproximation: true,
      assetCount: facts.length,
    );
  }

  /// Rough output bytes per output pixel for a format at a quality. AVIF is the
  /// most efficient, JPEG the least; higher quality → more bytes.
  static double bytesPerPixel(DefaultFormat format, int quality) {
    final base = switch (format) {
      DefaultFormat.avif => 0.14,
      DefaultFormat.heic => 0.20,
      DefaultFormat.webp => 0.28,
      DefaultFormat.jpeg => 0.42,
      // PNG is lossless: huge for photos (usually capped at the original →
      // ~0% saved), only wins on flat/transparent graphics.
      DefaultFormat.png => 1.20,
      DefaultFormat.auto => 0.16,
    };
    final q = quality.clamp(30, 100);
    final qFactor = 0.5 + ((q - 30) / 70) * 1.0; // q30→0.5×, q100→1.5×
    return base * qFactor;
  }

  /// Legacy flat-ratio heuristic, kept for the single-image compress preview.
  static double compressionRatio(DefaultFormat format, int quality) {
    final formatMul = switch (format) {
      DefaultFormat.avif => 0.32,
      DefaultFormat.heic => 0.50,
      DefaultFormat.webp => 0.60,
      DefaultFormat.jpeg => 0.90,
      DefaultFormat.png => 0.95, // rarely shrinks a photo
      DefaultFormat.auto => 0.40,
    };
    final qFactor = 0.7 + ((quality - 30) / 70) * 0.7;
    return (formatMul * qFactor).clamp(0.05, 0.95);
  }
}
