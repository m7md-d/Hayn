import 'package:flutter/material.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../app/theme/design_tokens.dart';
import '../../app/theme/motion.dart';
import 'buttons.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Empty / error / loading states — neutral, friendly, never blame the user.
//
//   HaynEmptyState   icon + title + message + optional CTA
//   HaynErrorState   danger icon + title + message + retry CTA
//   HaynLoadingState centered spinner + optional message
// ─────────────────────────────────────────────────────────────────────────────

class HaynEmptyState extends StatelessWidget {
  const HaynEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: hc.surfaceSunken,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 36, color: hc.text3),
              ),
              const SizedBox(height: AppSpacing.md),
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
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.lg),
                HaynPrimaryButton(
                  label: actionLabel!,
                  icon: actionIcon,
                  onPressed: onAction,
                  expanded: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HaynErrorState extends StatelessWidget {
  const HaynErrorState({
    required this.title,
    required this.message,
    this.icon = Icons.error_outline_rounded,
    this.retryLabel,
    this.onRetry,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: hc.dangerSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 36, color: hc.dangerColor),
              ),
              const SizedBox(height: AppSpacing.md),
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
              if (retryLabel != null && onRetry != null) ...[
                const SizedBox(height: AppSpacing.lg),
                HaynSecondaryButton(
                  label: retryLabel!,
                  icon: Icons.refresh_rounded,
                  onPressed: onRetry,
                  expanded: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HaynLoadingState extends StatelessWidget {
  const HaynLoadingState({
    this.message,
    this.size = 32,
    super.key,
  });

  final String? message;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: hc.accent,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(color: hc.text2),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AnimatedState — fades between empty/error/loading/content states with a
// gentle scale + fade transition. Use to swap whole-screen states.
// ─────────────────────────────────────────────────────────────────────────────
class HaynAnimatedState extends StatelessWidget {
  const HaynAnimatedState({
    required this.stateKey,
    required this.child,
    this.duration,
    super.key,
  });

  /// A key that identifies the *current* state (so AnimatedSwitcher knows
  /// when to play). Pass a unique String per state.
  final Object stateKey;
  final Widget child;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration ?? AppDuration.normal,
      switchInCurve: AppCurves.decelerate,
      switchOutCurve: AppCurves.accelerate,
      transitionBuilder: fadeScaleTransition,
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }
}
