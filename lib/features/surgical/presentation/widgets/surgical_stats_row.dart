import 'package:flutter/material.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SurgicalStatsRow — two side-by-side cards. Left: savings %. Right:
// original size → new size.
// ─────────────────────────────────────────────────────────────────────────────

class SurgicalStatsRow extends StatelessWidget {
  const SurgicalStatsRow({
    required this.savedPercent,
    required this.originalBytes,
    required this.newBytes,
    super.key,
  });

  final int savedPercent;
  final int originalBytes;
  final int newBytes;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: l.surgicalSaved,
            valueText: '−$savedPercent%',
            valueColor: hc.successColor,
            theme: theme,
          ),
        ),
        const SizedBox(width: AppSpacing.s3),
        Expanded(
          child: _StatCard(
            label: _formatSize(originalBytes),
            valueText: '→ ${_formatSize(newBytes)}',
            theme: theme,
          ),
        ),
      ],
    );
  }

  static String _formatSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.valueText,
    required this.theme,
    this.valueColor,
  });
  final String label;
  final String valueText;
  final Color? valueColor;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: hc.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: hc.text2,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valueText,
            style: theme.textTheme.headlineLarge?.copyWith(
              color: valueColor ?? theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
