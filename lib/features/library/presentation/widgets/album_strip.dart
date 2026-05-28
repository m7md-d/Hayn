import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AlbumStrip — horizontal pill list. First chip = synthesized "All"
// (selectedId == null). Subsequent chips = actual albums (skipping the
// photo_manager "All" album at index 0).
// ─────────────────────────────────────────────────────────────────────────────

class AlbumStrip extends StatelessWidget {
  const AlbumStrip({
    required this.albums,
    required this.selectedId,
    required this.onSelected,
    this.onMoreTap,
    super.key,
  });

  /// `albums` is the full list returned by photo_manager (hasAll: true).
  final List<AssetPathEntity> albums;

  /// `null` means the synthesized "All" chip is active.
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  /// If set, a "More" chip appears at the end to open the full picker.
  final VoidCallback? onMoreTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (albums.length <= 1) return const SizedBox.shrink();

    // Inline strip stays compact — limit visible non-"All" chips to 5; the rest
    // live in the picker reached via "More".
    final inlineLimit = onMoreTap != null ? 5 : albums.length - 1;
    final chips = <_AlbumChipData>[
      _AlbumChipData(id: null, label: l.filterAll, isAll: true),
      for (var i = 1; i <= inlineLimit && i < albums.length; i++)
        _AlbumChipData(id: albums[i].id, label: albums[i].name),
    ];

    final extraCount = onMoreTap != null
        ? (albums.length - 1) - inlineLimit
        : 0;

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md, 0, AppSpacing.md, 0,
        ),
        itemCount: chips.length + (onMoreTap != null ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s2),
        itemBuilder: (context, index) {
          if (index < chips.length) {
            final chip = chips[index];
            return _AlbumChip(
              data: chip,
              selected: chip.id == selectedId,
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(chip.id);
              },
            );
          }
          return _MoreChip(
            extraCount: extraCount,
            onTap: () {
              HapticFeedback.selectionClick();
              onMoreTap!();
            },
          );
        },
      ),
    );
  }
}

class _MoreChip extends StatelessWidget {
  const _MoreChip({required this.extraCount, required this.onTap});
  final int extraCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.s3, vertical: AppSpacing.s2,
        ),
        decoration: BoxDecoration(
          color: hc.surface2,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: hc.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.more_horiz_rounded, size: 14, color: hc.text2),
            const SizedBox(width: 4),
            Text(
              extraCount > 0
                  ? '${l.selectionMore} (+$extraCount)'
                  : l.libraryAlbumsTitle,
              style: theme.textTheme.labelMedium?.copyWith(
                color: hc.text2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumChipData {
  const _AlbumChipData({required this.id, required this.label, this.isAll = false});
  final String? id;
  final String label;
  final bool isAll;
}

class _AlbumChip extends StatelessWidget {
  const _AlbumChip({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _AlbumChipData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        curve: AppCurves.standard,
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: data.isAll ? AppSpacing.s3 : AppSpacing.s3,
          vertical: AppSpacing.s2,
        ),
        decoration: BoxDecoration(
          color: selected ? hc.accent : hc.surface2,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: selected ? null : Border.all(color: hc.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (data.isAll)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: Icon(
                  Icons.photo_library_rounded,
                  size: 14,
                  color: selected ? hc.onAccent : hc.text2,
                ),
              ),
            AnimatedDefaultTextStyle(
              duration: AppDuration.fast,
              style: theme.textTheme.labelMedium!.copyWith(
                color: selected ? hc.onAccent : hc.text2,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(data.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
