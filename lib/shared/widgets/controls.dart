import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Controls — segmented pill, value slider, toggle row, list cell.
// ─────────────────────────────────────────────────────────────────────────────

// ── HaynSegmentedPill ───────────────────────────────────────────────────────
//
// iOS-style segmented control. Sunken track with a raised pill behind the
// selected item that animates between positions.
//
// Usage:
//   HaynSegmentedPill<MediaFilter>(
//     value: state.filter,
//     onChanged: (f) => notifier.setFilter(f),
//     items: const [
//       HaynSegmentItem(value: MediaFilter.all,    label: 'All'),
//       HaynSegmentItem(value: MediaFilter.photos, label: 'Photos'),
//       HaynSegmentItem(value: MediaFilter.videos, label: 'Videos'),
//     ],
//   )

class HaynSegmentItem<T> {
  const HaynSegmentItem({required this.value, required this.label, this.icon});
  final T value;
  final String label;
  final IconData? icon;
}

class HaynSegmentedPill<T> extends StatelessWidget {
  const HaynSegmentedPill({
    required this.value,
    required this.onChanged,
    required this.items,
    this.height = 36,
    super.key,
  });

  final T value;
  final ValueChanged<T> onChanged;
  final List<HaynSegmentItem<T>> items;
  final double height;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final selectedIndex = items.indexWhere((it) => it.value == value);

    return LayoutBuilder(
      builder: (ctx, c) {
        final segWidth = (c.maxWidth - 6) / items.length;
        return Container(
          height: height,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: hc.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadius.sm + 1),
          ),
          child: Stack(
            children: [
              AnimatedPositionedDirectional(
                duration: AppDuration.fast,
                curve: AppCurves.standard,
                start: selectedIndex * segWidth,
                top: 0,
                bottom: 0,
                width: segWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: hc.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm - 1),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: items.map((item) {
                  final selected = item.value == value;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (!selected) {
                          HapticFeedback.selectionClick();
                          onChanged(item.value);
                        }
                      },
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.icon != null) ...[
                              Icon(item.icon, size: 14,
                                  color: selected ? theme.colorScheme.onSurface : hc.text2),
                              const SizedBox(width: AppSpacing.s1),
                            ],
                            AnimatedDefaultTextStyle(
                              duration: AppDuration.fast,
                              curve: AppCurves.standard,
                              style: theme.textTheme.labelLarge!.copyWith(
                                fontWeight:
                                    selected ? FontWeight.w600 : FontWeight.w500,
                                color: selected
                                    ? theme.colorScheme.onSurface
                                    : hc.text2,
                              ),
                              child: Text(item.label),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── HaynValueSlider ─────────────────────────────────────────────────────────
//
// Slider with a live label header (e.g., "Quality — 78%") and an optional
// helper line (e.g., "Estimated size: 1.2 MB").

class HaynValueSlider extends StatelessWidget {
  const HaynValueSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.label,
    this.valueLabel,
    this.helper,
    this.divisions,
    this.trailing,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String label;
  final String? valueLabel;
  final String? helper;
  final int? divisions;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            if (valueLabel != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s2, vertical: 2),
                decoration: BoxDecoration(
                  color: hc.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  valueLabel!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: hc.accent,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.s2),
              trailing!,
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.s1),
        // Wrap the Slider in a vertical-drag claimer so a parent ListView
        // can't steal an accidental sub-horizontal motion as a scroll. The
        // empty callbacks just register the recognizer in the gesture arena
        // — Material's Slider keeps the horizontal axis for itself.
        _SliderDragGuard(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s1),
            child: Text(
              helper!,
              style: theme.textTheme.labelSmall?.copyWith(color: hc.text2),
            ),
          ),
      ],
    );
  }
}

// ── _SliderDragGuard ────────────────────────────────────────────────────────
//
// Registers a no-op vertical drag recognizer over the slider's hit area so
// the gesture arena can't hand a sub-horizontal motion off to an outer
// ListView/PageView as a scroll. The Slider's own HorizontalDragGesture
// recognizer still wins horizontal motion.

class _SliderDragGuard extends StatelessWidget {
  const _SliderDragGuard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        VerticalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
          () => VerticalDragGestureRecognizer(),
          (instance) {
            // Empty callbacks — we only register the recognizer to claim
            // vertical drags in the arena and stop a parent scroll from
            // hijacking the slider thumb. No actual reaction.
            instance.onStart = (_) {};
            instance.onUpdate = (_) {};
            instance.onEnd = (_) {};
          },
        ),
      },
      child: child,
    );
  }
}

// ── HaynToggleRow ───────────────────────────────────────────────────────────
//
// Settings row with switch on the trailing edge.

class HaynToggleRow extends StatelessWidget {
  const HaynToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.leading,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? description;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.s3,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.s3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyLarge),
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: hc.text2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            Switch.adaptive(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

// ── HaynListCell ────────────────────────────────────────────────────────────
//
// Settings/menu row with leading icon, label, trailing (value + chevron, or
// any widget). Use inside a card or a sectioned list.

class HaynListCell extends StatelessWidget {
  const HaynListCell({
    required this.label,
    this.leading,
    this.leadingIcon,
    this.value,
    this.description,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.danger = false,
    super.key,
  });

  final String label;
  final Widget? leading;
  final IconData? leadingIcon;
  final String? value;
  final String? description;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final color = danger ? hc.dangerColor : theme.colorScheme.onSurface;

    final iconLeading = leadingIcon != null
        ? Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: danger ? hc.dangerSoft : hc.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(leadingIcon, size: 18,
                color: danger ? hc.dangerColor : hc.accent),
          )
        : null;

    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.s3,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.s3),
            ] else if (iconLeading != null) ...[
              iconLeading,
              const SizedBox(width: AppSpacing.s3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: theme.textTheme.bodyLarge?.copyWith(color: color)),
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: hc.text2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpacing.s2),
                child: Text(
                  value!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: hc.text2),
                ),
              ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.s2),
              trailing!,
            ] else if (showChevron && onTap != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpacing.s2),
                child: Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  size: 20,
                  color: hc.text3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── HaynListSection ─────────────────────────────────────────────────────────
//
// Groups list cells inside a rounded card with hairline dividers.

class HaynListSection extends StatelessWidget {
  const HaynListSection({
    required this.children,
    this.title,
    this.footer,
    super.key,
  });

  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.md, bottom: AppSpacing.s2,
            ),
            child: Text(
              title!.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: hc.text2,
                letterSpacing: 0.4,
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 60),
                    child: Divider(
                      color: hc.border,
                      thickness: AppHairline.thickness,
                      height: AppHairline.thickness,
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.md, top: AppSpacing.s2, end: AppSpacing.md,
            ),
            child: Text(
              footer!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: hc.text2,
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }
}
