import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PreservedMetadataCard — green-tinted list with checkmarks for every piece
// of metadata that will be carried over after the surgical replace.
// ─────────────────────────────────────────────────────────────────────────────

class PreservedMetadataCard extends StatelessWidget {
  const PreservedMetadataCard({required this.asset, super.key});
  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    final items = <String>[
      l.surgicalPreservedFilename,
      l.surgicalPreservedCaptureDate,
      if (asset.latitude != null &&
          asset.longitude != null &&
          asset.latitude != 0 &&
          asset.longitude != 0)
        l.surgicalPreservedGps,
      l.surgicalPreservedAllMeta,
      l.surgicalPreservedOrder,
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: hc.successSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 16, color: hc.successColor),
              const SizedBox(width: AppSpacing.s1),
              Text(
                l.surgicalPreserved,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: hc.successColor,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: hc.successColor),
                  const SizedBox(width: AppSpacing.s2),
                  Text(item, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
