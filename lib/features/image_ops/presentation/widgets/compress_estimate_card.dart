import 'package:flutter/material.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../data/compress_estimate_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CompressEstimateCard — predicted total size for a multi-image selection, from
// the live CompressEstimator (metadata prior, refined by tiny-proxy samples).
// Shows original → expected with a low–high band + savings, a refining spinner
// while sampling, and a rough compress-time ETA.
// ─────────────────────────────────────────────────────────────────────────────

class CompressEstimateCard extends StatelessWidget {
  const CompressEstimateCard({
    required this.originalBytes,
    required this.estimate,
    super.key,
  });

  final int originalBytes;
  final EstimateResult? estimate;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    final est = estimate?.size;
    final loading = est == null;
    final expected = est?.expected ?? 0;
    final savedPercent = (est != null && originalBytes > 0)
        ? ((1 - expected / originalBytes) * 100).round()
        : 0;
    final refining = estimate?.refining ?? true;
    final eta = estimate?.etaSeconds;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: hc.surface2,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: hc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          l.compressEstimatedSize,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: hc.text2, letterSpacing: 0.3),
                        ),
                        if (refining) ...[
                          const SizedBox(width: AppSpacing.s2),
                          SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.6, color: hc.text3),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _bytes(originalBytes),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: hc.text3,
                            decoration: TextDecoration.lineThrough,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        Icon(Icons.east_rounded, size: 14, color: hc.text3),
                        const SizedBox(width: AppSpacing.s2),
                        Text(
                          loading ? '…' : _bytes(expected),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: hc.successColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    if (!loading && est.high > est.low) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${_bytes(est.low)} – ${_bytes(est.high)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hc.text3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!loading)
                HaynSavingsBadge(percent: -savedPercent, compact: true),
            ],
          ),
          if (eta != null && eta > 0) ...[
            const SizedBox(height: AppSpacing.s3),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 13, color: hc.text3),
                const SizedBox(width: 6),
                Text(
                  '${l.compressEtaLabel}  ${_clock(eta)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: hc.text3),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _clock(double secs) {
    final t = secs.round();
    if (t < 60) return '≈ ${t}s';
    final m = t ~/ 60;
    final s = t % 60;
    return '≈ $m:${s.toString().padLeft(2, '0')}';
  }
}
