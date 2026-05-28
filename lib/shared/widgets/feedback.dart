import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Feedback — snackbars + inline banners.
//
// HaynSnack uses an Overlay-backed widget (not Material's ScaffoldMessenger)
// so we can control the entry/exit curves and durations precisely. The slide
// + fade + scale combo feels soft instead of mechanical.
//
//   HaynSnack.info / .success / .warning / .error
//   HaynInlineBanner  → inline informational box.
// ─────────────────────────────────────────────────────────────────────────────

enum _FeedbackTone { info, success, warning, danger }

abstract final class HaynSnack {
  static OverlayEntry? _entry;
  static Timer? _timer;
  static _SnackHandle? _handle;

  static void info(BuildContext context, String message,
          {String? actionLabel, VoidCallback? onAction}) =>
      _show(context, _FeedbackTone.info, message, actionLabel, onAction);

  static void success(BuildContext context, String message,
          {String? actionLabel, VoidCallback? onAction}) =>
      _show(context, _FeedbackTone.success, message, actionLabel, onAction);

  static void warning(BuildContext context, String message,
          {String? actionLabel, VoidCallback? onAction}) =>
      _show(context, _FeedbackTone.warning, message, actionLabel, onAction);

  static void error(BuildContext context, String message,
          {String? actionLabel, VoidCallback? onAction}) =>
      _show(context, _FeedbackTone.danger, message, actionLabel, onAction);

  static void _show(
    BuildContext context,
    _FeedbackTone tone,
    String message,
    String? actionLabel,
    VoidCallback? onAction,
  ) {
    HapticFeedback.selectionClick();

    // Dismiss anything in flight.
    _timer?.cancel();
    _handle?.dismissAndRemove();
    _entry = null;
    _handle = null;

    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    final handle = _SnackHandle();

    entry = OverlayEntry(
      builder: (_) => _SnackHost(
        message: message,
        tone: tone,
        actionLabel: actionLabel,
        onAction: onAction,
        handle: handle,
        onDone: () {
          if (_entry == entry) _entry = null;
          if (_handle == handle) _handle = null;
          entry.remove();
        },
      ),
    );

    _entry = entry;
    _handle = handle;
    overlay.insert(entry);

    _timer = Timer(const Duration(milliseconds: 2800), () {
      handle.dismiss();
    });
  }
}

class _SnackHandle {
  VoidCallback? _dismiss;
  VoidCallback? _dismissAndRemove;

  void _wire(VoidCallback dismiss, VoidCallback dismissAndRemove) {
    _dismiss = dismiss;
    _dismissAndRemove = dismissAndRemove;
  }

  void dismiss() => _dismiss?.call();
  void dismissAndRemove() => _dismissAndRemove?.call();
}

class _SnackHost extends StatefulWidget {
  const _SnackHost({
    required this.message,
    required this.tone,
    required this.actionLabel,
    required this.onAction,
    required this.handle,
    required this.onDone,
  });

  final String message;
  final _FeedbackTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final _SnackHandle handle;
  final VoidCallback onDone;

  @override
  State<_SnackHost> createState() => _SnackHostState();
}

class _SnackHostState extends State<_SnackHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _enter;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AppDuration.slow,
      reverseDuration: AppDuration.normal,
    );
    _enter = CurvedAnimation(parent: _ctrl, curve: AppCurves.emphasized);
    _opacity = CurvedAnimation(parent: _ctrl, curve: AppCurves.decelerate);

    widget.handle._wire(_dismiss, _dismissImmediate);

    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.forward());
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    if (mounted) widget.onDone();
  }

  void _dismissImmediate() {
    _ctrl.stop();
    widget.onDone();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final (icon, fg) = switch (widget.tone) {
      _FeedbackTone.info => (Icons.info_outline_rounded, hc.accent),
      _FeedbackTone.success =>
        (Icons.check_circle_outline_rounded, hc.successColor),
      _FeedbackTone.warning =>
        (Icons.warning_amber_rounded, hc.warningColor),
      _FeedbackTone.danger =>
        (Icons.error_outline_rounded, hc.dangerColor),
    };

    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.surface2Dark : AppColors.textLight;
    final fgText = isDark ? AppColors.textDark : Colors.white;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: GestureDetector(
          onTap: _dismiss,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (ctx, child) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Transform.translate(
                  offset: Offset(0, (1 - _enter.value) * 60),
                  child: Opacity(
                    opacity: _opacity.value,
                    child: Transform.scale(
                      scale: 0.96 + _enter.value * 0.04,
                      alignment: Alignment.bottomCenter,
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        boxShadow: AppElevation.shadowFloat(isDark: isDark),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.s3,
                      ),
                      child: Row(
                        children: [
                          Icon(icon, color: fg, size: 20),
                          const SizedBox(width: AppSpacing.s3),
                          Expanded(
                            child: Text(
                              widget.message,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: fgText),
                            ),
                          ),
                          if (widget.actionLabel != null &&
                              widget.onAction != null) ...[
                            const SizedBox(width: AppSpacing.s2),
                            TextButton(
                              onPressed: () {
                                widget.onAction!.call();
                                _dismiss();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: hc.accent,
                                minimumSize: const Size(0, 32),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.s2),
                              ),
                              child: Text(widget.actionLabel!),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HaynInlineBanner — pill-shaped info box that lives inside content.
// ─────────────────────────────────────────────────────────────────────────────

enum HaynBannerTone { info, success, warning, danger }

class HaynInlineBanner extends StatelessWidget {
  const HaynInlineBanner({
    required this.message,
    this.icon,
    this.tone = HaynBannerTone.info,
    this.action,
    this.onDismiss,
    super.key,
  });

  final String message;
  final IconData? icon;
  final HaynBannerTone tone;
  final Widget? action;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);

    final (bg, fg, defaultIcon) = switch (tone) {
      HaynBannerTone.info =>
        (hc.accentSoft, hc.accent, Icons.auto_awesome_rounded),
      HaynBannerTone.success =>
        (hc.successSoft, hc.successColor, Icons.check_circle_outline_rounded),
      HaynBannerTone.warning =>
        (hc.warningSoft, hc.warningColor, Icons.warning_amber_rounded),
      HaynBannerTone.danger =>
        (hc.dangerSoft, hc.dangerColor, Icons.error_outline_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, size: 18, color: fg),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: fg,
                height: 1.45,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.s2),
            action!,
          ],
          if (onDismiss != null) ...[
            const SizedBox(width: AppSpacing.s2),
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onDismiss!();
              },
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s1),
                child: Icon(Icons.close_rounded, size: 16, color: fg),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
