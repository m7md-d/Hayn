import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../domain/entities/library_sort_filter.dart';

// (l10n + theme tokens reused in nested widgets below)

// ─────────────────────────────────────────────────────────────────────────────
// SortFilterSheet — bottom sheet that lets the user change sort order, file
// size range, and format. Returns a LibrarySortFilter (or null on cancel).
// ─────────────────────────────────────────────────────────────────────────────

Future<LibrarySortFilter?> showSortFilterSheet({
  required BuildContext context,
  required LibrarySortFilter current,
}) {
  return showHaynSheet<LibrarySortFilter>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SortFilterSheetBody(current: current),
  );
}

class _SortFilterSheetBody extends StatefulWidget {
  const _SortFilterSheetBody({required this.current});
  final LibrarySortFilter current;

  @override
  State<_SortFilterSheetBody> createState() => _SortFilterSheetBodyState();
}

class _SortFilterSheetBodyState extends State<_SortFilterSheetBody> {
  late LibrarySortFilter _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.current;
  }

  void _patch(LibrarySortFilter Function(LibrarySortFilter) f) {
    HapticFeedback.selectionClick();
    setState(() => _draft = f(_draft));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HaynSheetHeader(
              title: l.librarySortAndFilter,
              trailing: TextButton(
                onPressed: _draft.hasAnyActive
                    ? () {
                        HapticFeedback.selectionClick();
                        setState(() => _draft = LibrarySortFilter.cleared);
                      }
                    : null,
                child: Text(l.libraryClearFilters),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sort
                  _SectionLabel(label: l.librarySortBy),
                  _OptionChips<LibrarySort>(
                    value: _draft.sort,
                    onSelect: (v) => _patch((d) => d.copyWith(sort: v)),
                    options: [
                      _ChipOption(LibrarySort.newestFirst, l.librarySortNewest),
                      _ChipOption(LibrarySort.oldestFirst, l.librarySortOldest),
                      _ChipOption(LibrarySort.largestFirst, l.librarySortLargest),
                      _ChipOption(LibrarySort.smallestFirst, l.librarySortSmallest),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // Size filter
                  _SectionLabel(label: l.libraryFilterBySize),
                  _OptionChips<LibrarySizeFilter>(
                    value: _draft.sizeFilter,
                    onSelect: (v) =>
                        _patch((d) => d.copyWith(sizeFilter: v)),
                    options: [
                      _ChipOption(LibrarySizeFilter.any, l.libraryFilterAnySize),
                      _ChipOption(LibrarySizeFilter.small, l.libraryFilterSmall),
                      _ChipOption(LibrarySizeFilter.medium, l.libraryFilterMedium),
                      _ChipOption(LibrarySizeFilter.large, l.libraryFilterLarge),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // Format filter
                  _SectionLabel(label: l.libraryFilterByFormat),
                  _OptionChips<String?>(
                    value: _draft.formatFilter,
                    onSelect: (v) =>
                        _patch((d) => d.copyWith(formatFilter: v)),
                    options: [
                      _ChipOption<String?>(null, l.libraryFilterAnyFormat),
                      _ChipOption<String?>('jpeg', 'JPEG'),
                      _ChipOption<String?>('png', 'PNG'),
                      _ChipOption<String?>('heic', 'HEIC'),
                      _ChipOption<String?>('webp', 'WebP'),
                      _ChipOption<String?>('avif', 'AVIF'),
                      _ChipOption<String?>('gif', 'GIF'),
                      _ChipOption<String?>('mp4', 'MP4'),
                      _ChipOption<String?>('mov', 'MOV'),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  HaynPrimaryButton(
                    label: l.libraryApplyFilters,
                    onPressed: () => Navigator.of(context).pop(_draft),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s2),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: hc.text2,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ChipOption<T> {
  const _ChipOption(this.value, this.label);
  final T value;
  final String label;
}

class _OptionChips<T> extends StatelessWidget {
  const _OptionChips({
    required this.value,
    required this.onSelect,
    required this.options,
  });

  final T value;
  final ValueChanged<T> onSelect;
  final List<_ChipOption<T>> options;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      children: [
        for (final opt in options)
          GestureDetector(
            onTap: () => onSelect(opt.value),
            child: AnimatedContainer(
              duration: AppDuration.fast,
              curve: AppCurves.standard,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s3,
                vertical: AppSpacing.s2,
              ),
              decoration: BoxDecoration(
                color: opt.value == value ? hc.accent : hc.surface2,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: opt.value == value ? hc.accent : hc.border,
                ),
              ),
              child: Text(
                opt.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: opt.value == value ? hc.onAccent : hc.text2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
