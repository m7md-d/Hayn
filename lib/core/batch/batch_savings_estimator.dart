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

/// Minimal per-asset facts the estimate needs (from the index). [family] is the
/// source codec (jpeg/heif/…), which the per-item model needs to read source
/// bytes correctly — build it with [BatchSavingsEstimator.factsFrom] from the
/// index's mime/title so the chip classifies content the SAME way the compress
/// screen does (otherwise the two show different savings).
typedef AssetSizeFacts = ({
  int sizeBytes,
  int width,
  int height,
  SourceFamily family,
});

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
  /// Build facts from an index row, classifying the source family from its
  /// mime/title — so the chip's per-item model matches the compress screen's.
  static AssetSizeFacts factsFrom({
    required int sizeBytes,
    required int width,
    required int height,
    String? mimeType,
    String? title,
  }) {
    final t = title ?? '';
    final dot = t.lastIndexOf('.');
    final ext = (dot >= 0 && dot < t.length - 1) ? t.substring(dot + 1) : '';
    return (
      sizeBytes: sizeBytes,
      width: width,
      height: height,
      family: SourceFamilyFromMime.of(mimeType, ext: ext),
    );
  }

  /// [format] must be a CONCRETE codec — resolve `auto` (via
  /// `DefaultFormat.resolveAuto`) before calling, so the modelled bytes match
  /// the codec that will actually run (auto≈heic over-predicts AVIF by ~40%).
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
      // Per-item prediction from the shared model (sub-linear in source bpp),
      // classified by the real source family so a PNG isn't read like a JPEG.
      final item = EstimateItem(
        pixels: f.width * f.height,
        sourceBytes: f.sizeBytes,
        family: f.family,
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
