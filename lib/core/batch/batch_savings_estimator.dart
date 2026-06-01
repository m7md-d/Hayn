import '../../features/image_ops/domain/compress_estimator.dart';
import '../../features/settings/providers/preferences_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BatchSavingsEstimator — predicts how many bytes a compress / surgical-replace
// run will save on a selection (the library "savings chip" + surgical batch).
//
// Delegates to the shared CompressEstimator's metadata PRIOR — the same model
// the compress screen uses — so the chip reflects the real engine: a sub-linear
// content curve driven by each item's source bits-per-pixel, not a flat factor.
// Instant (index facts only, no encoding), spanning the WHOLE selection. Output
// is still capped at the original here (a "savings" indicator shows 0 %, not a
// negative, when a format would grow a file).
// ─────────────────────────────────────────────────────────────────────────────

/// Minimal per-asset facts the estimate needs (from the index). Optional
/// [mimeType] sharpens the per-format model; null falls back to a generic curve.
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

    var totalOriginal = 0;
    var totalOutput = 0;
    for (final f in facts) {
      totalOriginal += f.sizeBytes;
      // Per-item prediction from the shared model (sub-linear in source bpp).
      final item = EstimateItem(
        pixels: f.width * f.height,
        sourceBytes: f.sizeBytes,
        family: SourceFamily.other, // index facts here carry no mime
      );
      var out = CompressEstimator.predictItemBytes(item, format, quality);
      // Savings indicator: a compression pass shows 0 %, not a negative, if a
      // format would grow a file — cap at the original.
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
