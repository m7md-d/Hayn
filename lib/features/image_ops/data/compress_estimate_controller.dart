import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/index/index_providers.dart';
import '../../settings/providers/preferences_providers.dart';
import '../domain/compress_estimator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CompressEstimateController — a FAST, memory-safe size/time estimate for a
// multi-image selection.
//
// It does NO encoding of its own. (A sampling loop that encoded many full-res
// images — PNG outputs are huge — is what OOM-killed a select-all run.) Instead:
//   • the instant metadata PRIOR is computed from the index (pixels + source
//     bytes + format) for the whole selection — zero IO, fine for 10k;
//   • it's calibrated by ONE real data point: the active image the screen ALdy
//     compresses for the preview. That single anchor pins the model to this
//     batch + codec + device, and its encode time gives a per-format ETA.
//
// One real encode (the preview the user is looking at anyway) → close-to-real
// number, instantly, with no extra memory.
// ─────────────────────────────────────────────────────────────────────────────

class EstimateResult {
  const EstimateResult({
    required this.size,
    required this.refining,
    this.etaSeconds,
  });
  final SizeEstimate size;
  final bool refining;
  final double? etaSeconds;
}

class CompressEstimateController {
  CompressEstimateController(this.ref);
  final WidgetRef ref;

  /// Compute the estimate. [anchorId]/[anchorRealBytes]/[anchorMs] are the real
  /// result of compressing the active preview image (when available) — used to
  /// calibrate the whole-batch prior + derive the ETA. With no anchor it returns
  /// the instant prior. Never encodes; never throws.
  Future<EstimateResult> estimate({
    required List<String> ids,
    required DefaultFormat target,
    required int quality,
    String? anchorId,
    int? anchorRealBytes,
    double? anchorMs,
  }) async {
    final facts = await ref.read(mediaIndexDatabaseProvider).estimateFactsFor(ids);
    if (facts.isEmpty) {
      return const EstimateResult(
        size: SizeEstimate(low: 0, expected: 0, high: 0, confidence: 0),
        refining: false,
      );
    }

    final items = [
      for (final f in facts)
        EstimateItem(
          pixels: f.width * f.height,
          sourceBytes: f.sizeBytes,
          family: SourceFamilyFromMime.of(f.mimeType, ext: _ext(f.title)),
        ),
    ];

    EstimateItem? anchorItem;
    BppSample? anchor;
    if (anchorId != null && anchorRealBytes != null && anchorRealBytes > 0) {
      final idx = facts.indexWhere((f) => f.id == anchorId);
      if (idx >= 0) {
        anchorItem = items[idx];
        anchor = BppSample(
          item: anchorItem,
          predicted:
              CompressEstimator.predictItemBytes(anchorItem, target, quality),
          actual: anchorRealBytes,
        );
      }
    }

    final size = anchor != null
        ? CompressEstimator.calibrate(items, target, quality, [anchor])
        : CompressEstimator.prior(items, target, quality);

    double? eta;
    if (anchorMs != null && anchorMs > 0 && anchorItem != null) {
      final anchorMp = anchorItem.pixels / 1e6;
      if (anchorMp > 0) {
        final batchMp = items.fold<double>(0, (s, it) => s + it.pixels / 1e6);
        eta = (batchMp * (anchorMs / anchorMp)) / 1000.0;
      }
    }

    return EstimateResult(size: size, refining: false, etaSeconds: eta);
  }

  static String _ext(String? title) {
    final t = title ?? '';
    final dot = t.lastIndexOf('.');
    return (dot >= 0 && dot < t.length - 1) ? t.substring(dot + 1) : '';
  }
}
