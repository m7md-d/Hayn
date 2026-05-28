import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Dialogs — confirm / destructive-confirm with consistent layout.
// Always use these instead of bare AlertDialog so styling stays uniform.
// ─────────────────────────────────────────────────────────────────────────────

Future<bool> showHaynConfirm({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: context.hc.scrim,
    builder: (ctx) => _HaynConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      icon: icon,
      destructive: false,
    ),
  );
  return result ?? false;
}

Future<bool> showHaynDestructiveConfirm({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  String? reassurance,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: context.hc.scrim,
    builder: (ctx) => _HaynConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      icon: icon ?? Icons.delete_outline_rounded,
      destructive: true,
      reassurance: reassurance,
    ),
  );
  return result ?? false;
}

class _HaynConfirmDialog extends StatelessWidget {
  const _HaynConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
    this.icon,
    this.reassurance,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final IconData? icon;
  final String? reassurance;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final confirmColor = destructive ? hc.dangerColor : hc.accent;
    final iconBg = destructive ? hc.dangerSoft : hc.accentSoft;

    return Dialog(
      backgroundColor: hc.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.s3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 28, color: confirmColor),
              ),
              const SizedBox(height: AppSpacing.s3),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineLarge,
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: hc.text2,
                height: 1.5,
              ),
            ),
            if (reassurance != null) ...[
              const SizedBox(height: AppSpacing.s3),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3, vertical: AppSpacing.s2,
                ),
                decoration: BoxDecoration(
                  color: hc.surfaceSunken,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    Icon(Icons.restore_rounded, size: 16, color: hc.text2),
                    const SizedBox(width: AppSpacing.s2),
                    Expanded(
                      child: Text(
                        reassurance!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hc.text2,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: theme.colorScheme.onSurface,
                      backgroundColor: hc.surfaceSunken,
                    ),
                    child: Text(cancelLabel),
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      destructive
                          ? HapticFeedback.mediumImpact()
                          : HapticFeedback.lightImpact();
                      Navigator.of(context).pop(true);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: confirmColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                    ),
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
