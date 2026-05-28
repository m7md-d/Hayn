import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CropAspectRatio + AspectRatioChips — horizontal scrollable strip of
// presets. "Free" releases the constraint; "Original" snaps to the source
// image's aspect.
// ─────────────────────────────────────────────────────────────────────────────

enum CropAspectRatio {
  free,
  original,
  square,
  fourThree,
  threeFour,
  sixteenNine,
  nineSixteen,
}

class AspectRatioChips extends StatelessWidget {
  const AspectRatioChips({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final CropAspectRatio value;
  final ValueChanged<CropAspectRatio> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entries = <(_RatioMeta, CropAspectRatio)>[
      (_RatioMeta(label: l.cropRatioFree, icon: Icons.crop_free_rounded),
          CropAspectRatio.free),
      (_RatioMeta(label: l.cropRatioOriginal, icon: Icons.image_rounded),
          CropAspectRatio.original),
      (const _RatioMeta(label: '1:1', icon: Icons.crop_square_rounded),
          CropAspectRatio.square),
      (const _RatioMeta(label: '4:3', icon: Icons.crop_landscape_rounded),
          CropAspectRatio.fourThree),
      (const _RatioMeta(label: '3:4', icon: Icons.crop_portrait_rounded),
          CropAspectRatio.threeFour),
      (const _RatioMeta(label: '16:9', icon: Icons.crop_16_9_rounded),
          CropAspectRatio.sixteenNine),
      (const _RatioMeta(label: '9:16', icon: Icons.stay_current_portrait_rounded),
          CropAspectRatio.nineSixteen),
    ];

    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.s2),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s2),
        itemBuilder: (ctx, i) {
          final (meta, ratio) = entries[i];
          return _RatioChip(
            meta: meta,
            selected: ratio == value,
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(ratio);
            },
          );
        },
      ),
    );
  }
}

class _RatioMeta {
  const _RatioMeta({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

class _RatioChip extends StatelessWidget {
  const _RatioChip({
    required this.meta,
    required this.selected,
    required this.onTap,
  });

  final _RatioMeta meta;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3, vertical: AppSpacing.s2),
        decoration: BoxDecoration(
          color: selected ? hc.accent : hc.surface2,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              meta.icon,
              size: 16,
              color: selected ? Colors.white : hc.text2,
            ),
            const SizedBox(width: 6),
            Text(
              meta.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? Colors.white : hc.text2,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
