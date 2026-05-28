import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../app/theme/design_tokens.dart';
import 'buttons.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheets — single helper that respects the theme's drag handle, radius
// and surface color. Use this instead of showModalBottomSheet directly.
//
//   showHaynSheet           generic sheet — pass any widget as body
//   showHaynPickerSheet<T>  list of choices with checkmarks (theme, language…)
//   HaynSheetHeader         consistent title + close pattern inside a sheet
// ─────────────────────────────────────────────────────────────────────────────

Future<T?> showHaynSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  // Background is provided dynamically inside the builder so that live theme
  // changes (e.g. switching dark mode from inside the sheet) repaint the
  // sheet too — bottom_sheet.dart captures the `backgroundColor` argument
  // at push time and would otherwise hold the stale colour.
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DecoratedBox(
      decoration: BoxDecoration(
        color: ctx.hc.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      child: builder(ctx),
    ),
  );
}

class HaynSheetHeader extends StatelessWidget {
  const HaynSheetHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.s2, AppSpacing.s2, AppSpacing.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: hc.text2,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HaynPickerOption — value + label + optional description.
// ─────────────────────────────────────────────────────────────────────────────
class HaynPickerOption<T> {
  const HaynPickerOption({
    required this.value,
    required this.label,
    this.description,
    this.icon,
    this.warning,
  });
  final T value;
  final String label;
  final String? description;
  final IconData? icon;

  /// Optional warning shown as a yellow pill next to the label
  /// (e.g. "Software encoding — slower" for AVIF without hw accel).
  final String? warning;
}

/// Opens a picker sheet that **stays open** as the user taps options. The
/// selection is committed live via [onChanged]; the sheet only closes when
/// the user dismisses it (swipe-down, tap-outside, back).
///
/// This matches the user's expectation that changing a preference shouldn't
/// kick them out of the picker — they may want to compare options.
Future<void> showHaynPickerSheet<T>({
  required BuildContext context,
  required String title,
  required T currentValue,
  required List<HaynPickerOption<T>> options,
  required ValueChanged<T> onChanged,
  String? subtitle,
}) {
  return showHaynSheet<void>(
    context: context,
    builder: (ctx) => _PickerSheetBody<T>(
      title: title,
      subtitle: subtitle,
      initialValue: currentValue,
      options: options,
      onChanged: onChanged,
    ),
  );
}

class _PickerSheetBody<T> extends StatefulWidget {
  const _PickerSheetBody({
    required this.title,
    required this.initialValue,
    required this.options,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final T initialValue;
  final List<HaynPickerOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  State<_PickerSheetBody<T>> createState() => _PickerSheetBodyState<T>();
}

class _PickerSheetBodyState<T> extends State<_PickerSheetBody<T>> {
  late T _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HaynSheetHeader(title: widget.title, subtitle: widget.subtitle),
            for (var i = 0; i < widget.options.length; i++) ...[
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selected = widget.options[i].value);
                  widget.onChanged(widget.options[i].value);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.s3,
                  ),
                  child: Row(
                    children: [
                      if (widget.options[i].icon != null) ...[
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: hc.accentSoft,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          alignment: Alignment.center,
                          child: Icon(widget.options[i].icon, size: 18, color: hc.accent),
                        ),
                        const SizedBox(width: AppSpacing.s3),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(widget.options[i].label,
                                      style: theme.textTheme.bodyLarge),
                                ),
                                if (widget.options[i].warning != null) ...[
                                  const SizedBox(width: AppSpacing.s2),
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: hc.warningSoft,
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.sm),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.warning_amber_rounded,
                                              size: 11, color: hc.warningColor),
                                          const SizedBox(width: 3),
                                          Flexible(
                                            child: Text(
                                              widget.options[i].warning!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                color: hc.warningColor,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (widget.options[i].description != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.options[i].description!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: hc.text2,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      AnimatedOpacity(
                        duration: AppDuration.fast,
                        opacity:
                            widget.options[i].value == _selected ? 1 : 0,
                        child: Icon(Icons.check_rounded,
                            color: hc.accent, size: 22),
                      ),
                    ],
                  ),
                ),
              ),
              if (i < widget.options.length - 1)
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HaynActionSheet — iOS-flavored sheet with a primary or destructive action,
// optional title + message.
// ─────────────────────────────────────────────────────────────────────────────

class HaynSheetAction {
  const HaynSheetAction({
    required this.label,
    required this.onTap,
    this.icon,
    this.destructive = false,
  });
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool destructive;
}

Future<void> showHaynActionSheet({
  required BuildContext context,
  String? title,
  String? message,
  required List<HaynSheetAction> actions,
  required String cancelLabel,
}) {
  return showHaynSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null || message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  children: [
                    if (title != null)
                      Text(title,
                          style: Theme.of(ctx).textTheme.titleLarge,
                          textAlign: TextAlign.center),
                    if (message != null) ...[
                      const SizedBox(height: AppSpacing.s1),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              color: ctx.hc.text2,
                              height: 1.4,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            for (final action in actions) ...[
              action.destructive
                  ? HaynDestructiveButton(
                      label: action.label,
                      icon: action.icon,
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        action.onTap();
                      },
                    )
                  : HaynPrimaryButton(
                      label: action.label,
                      icon: action.icon,
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        action.onTap();
                      },
                    ),
              const SizedBox(height: AppSpacing.s2),
            ],
            HaynSecondaryButton(
              label: cancelLabel,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}
