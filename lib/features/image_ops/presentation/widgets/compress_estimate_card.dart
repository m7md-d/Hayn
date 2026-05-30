import 'package:flutter/material.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../settings/providers/preferences_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CompressEstimateCard — shows the (estimated) original size, predicted new
// size, and a savings badge. Estimation is a coarse heuristic for now; the
// real number will come from the encoder once the engine lands.
// ─────────────────────────────────────────────────────────────────────────────

class CompressEstimateCard extends StatelessWidget {
  const CompressEstimateCard({
    required this.originalBytes,
    required this.quality,
    required this.format,
    super.key,
  });

  final int originalBytes;
  final int quality;
  final DefaultFormat format;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    final ratio = _ratio(quality, format);
    final estimated = (originalBytes * ratio).round();
    final savedPercent = ((1 - ratio) * 100).round();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: hc.surface2,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: hc.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.compressEstimatedSize,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: hc.text2,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _format(originalBytes),
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
                      _format(estimated),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: hc.successColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          HaynSavingsBadge(
            percent: -savedPercent,
            compact: true,
          ),
        ],
      ),
    );
  }

  /// Returns 0..1 — fraction of original that the new file will take.
  /// Heuristic only; real ratio comes from the encoder.
  double _ratio(int quality, DefaultFormat format) {
    // Format efficiency multipliers vs JPEG@85
    final formatMul = switch (format) {
      DefaultFormat.avif => 0.32,
      DefaultFormat.heic => 0.50,
      DefaultFormat.webp => 0.60,
      DefaultFormat.jpeg => 0.90,
      DefaultFormat.png => 0.95, // lossless — rarely shrinks a photo
      DefaultFormat.auto => 0.40,
    };
    // Quality factor: 30→0.7x, 100→1.4x of the base multiplier
    final qFactor = 0.7 + ((quality - 30) / 70) * 0.7;
    return (formatMul * qFactor).clamp(0.05, 0.95);
  }

  static String _format(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
