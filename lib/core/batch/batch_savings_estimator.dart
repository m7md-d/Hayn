import 'package:photo_manager/photo_manager.dart';
import '../../features/library/presentation/providers/asset_size_cache.dart';
import '../../features/settings/providers/preferences_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BatchSavingsEstimator — predicts how many bytes the user will save when
// running compress / surgical-replace on a selection.
//
// Strategy:
//   • ≤ [exactThreshold] assets → read every file size (exact totals).
//   • > [exactThreshold] assets → sample [sampleSize] assets, average their
//     real sizes, multiply by the selection count (heuristic totals).
//
// The format-specific compression ratio matches the one used inside
// CompressEstimateCard so the same numbers appear across screens.
// ─────────────────────────────────────────────────────────────────────────────

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

  /// True when the estimator extrapolated from a small sample rather than
  /// summing every file in the selection.
  final bool isApproximation;
  final int assetCount;
}

abstract final class BatchSavingsEstimator {
  static const int exactThreshold = 5;
  static const int sampleSize = 5;

  static Future<BatchSavingsEstimate> estimate({
    required List<AssetEntity> assets,
    required DefaultFormat format,
    required int quality,
  }) async {
    if (assets.isEmpty) {
      return const BatchSavingsEstimate(
        totalOriginalBytes: 0,
        estimatedNewBytes: 0,
        savedPercent: 0,
        isApproximation: false,
        assetCount: 0,
      );
    }

    final int totalOriginal;
    final bool isApprox;
    if (assets.length <= exactThreshold) {
      totalOriginal = _sumSizes(assets);
      isApprox = false;
    } else {
      final sample = _pickSample(assets, sampleSize);
      final sampleSum = _sumSizes(sample);
      final avg = sampleSum / sample.length;
      totalOriginal = (avg * assets.length).round();
      isApprox = true;
    }

    final ratio = _ratio(format, quality);
    final estimatedNew = (totalOriginal * ratio).round();
    final savedPercent = totalOriginal == 0
        ? 0
        : (((totalOriginal - estimatedNew) / totalOriginal) * 100).round();

    return BatchSavingsEstimate(
      totalOriginalBytes: totalOriginal,
      estimatedNewBytes: estimatedNew,
      savedPercent: savedPercent,
      isApproximation: isApprox,
      assetCount: assets.length,
    );
  }

  /// Picks an evenly-spread sample across the selection so we don't bias
  /// toward only the first few assets (e.g. when a selection spans a wide
  /// timeline).
  static List<AssetEntity> _pickSample(List<AssetEntity> assets, int n) {
    if (assets.length <= n) return assets;
    final step = assets.length / n;
    return [
      for (var i = 0; i < n; i++) assets[(i * step).floor()],
    ];
  }

  // Reads sizes from the index-seeded cache (sync, never asset.file). Assets
  // not yet in the cache count as 0; the estimate is approximate by design.
  static int _sumSizes(List<AssetEntity> assets) {
    var sum = 0;
    for (final a in assets) {
      sum += AssetSizeCache.get(a.id) ?? 0;
    }
    return sum;
  }

  /// Mirrors CompressEstimateCard._ratio so screens stay consistent.
  /// Exposed for tests + reuse by the surgical heuristic.
  static double compressionRatio(DefaultFormat format, int quality) {
    final formatMul = switch (format) {
      DefaultFormat.avif => 0.32,
      DefaultFormat.heic => 0.50,
      DefaultFormat.webp => 0.60,
      DefaultFormat.jpeg => 0.90,
      DefaultFormat.auto => 0.40,
    };
    final qFactor = 0.7 + ((quality - 30) / 70) * 0.7;
    return (formatMul * qFactor).clamp(0.05, 0.95);
  }

  static double _ratio(DefaultFormat format, int quality) =>
      compressionRatio(format, quality);
}
