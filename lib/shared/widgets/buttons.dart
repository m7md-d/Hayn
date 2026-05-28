import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Buttons — five semantic variants. All share haptics, loading state, and
// touch-target rules. Use these instead of raw Material buttons in screens.
//
//   HaynPrimaryButton      → THE action (one per screen, ideally)
//   HaynSecondaryButton    → outlined, sits next to a primary
//   HaynTonalButton        → soft-accent fill, for noticeable-but-not-primary
//   HaynPlainButton        → text-only, for cancel / dismiss / inline links
//   HaynDestructiveButton  → filled with --danger, for delete / replace only
//
// Sizes: compact (36) / normal (48) / large (56)
// ─────────────────────────────────────────────────────────────────────────────

enum HaynButtonSize {
  compact(36),
  normal(48),
  large(56);

  const HaynButtonSize(this.height);
  final double height;
}

class HaynPrimaryButton extends StatelessWidget {
  const HaynPrimaryButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    this.size = HaynButtonSize.normal,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expanded;
  final HaynButtonSize size;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    final hc = context.hc;
    return _BaseButton(
      expanded: expanded,
      size: size,
      child: FilledButton(
        onPressed: disabled ? null : () => _press(onPressed!),
        style: FilledButton.styleFrom(
          minimumSize: Size(0, size.height),
          backgroundColor: hc.accent,
          foregroundColor: hc.onAccent,
          disabledBackgroundColor: hc.accent.withValues(alpha: 0.4),
          disabledForegroundColor: hc.onAccent.withValues(alpha: 0.7),
        ),
        child: _ButtonContent(
          label: label,
          icon: icon,
          isLoading: isLoading,
          color: hc.onAccent,
        ),
      ),
    );
  }
}

class HaynSecondaryButton extends StatelessWidget {
  const HaynSecondaryButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    this.size = HaynButtonSize.normal,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expanded;
  final HaynButtonSize size;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    final cs = Theme.of(context).colorScheme;
    final hc = context.hc;
    return _BaseButton(
      expanded: expanded,
      size: size,
      child: OutlinedButton(
        onPressed: disabled ? null : () => _press(onPressed!),
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, size.height),
          side: BorderSide(color: hc.border),
          foregroundColor: cs.onSurface,
        ),
        child: _ButtonContent(
          label: label,
          icon: icon,
          isLoading: isLoading,
          color: cs.onSurface,
        ),
      ),
    );
  }
}

class HaynTonalButton extends StatelessWidget {
  const HaynTonalButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    this.size = HaynButtonSize.normal,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expanded;
  final HaynButtonSize size;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    final hc = context.hc;
    return _BaseButton(
      expanded: expanded,
      size: size,
      child: FilledButton.tonal(
        onPressed: disabled ? null : () => _press(onPressed!),
        style: FilledButton.styleFrom(
          minimumSize: Size(0, size.height),
          backgroundColor: hc.accentSoft,
          foregroundColor: hc.accent,
          disabledBackgroundColor: hc.accentSoft.withValues(alpha: 0.4),
          disabledForegroundColor: hc.accent.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: _ButtonContent(
          label: label,
          icon: icon,
          isLoading: isLoading,
          color: hc.accent,
        ),
      ),
    );
  }
}

class HaynPlainButton extends StatelessWidget {
  const HaynPlainButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.color,
    this.size = HaynButtonSize.normal,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final HaynButtonSize size;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final effective = color ?? hc.accent;
    return TextButton(
      onPressed: onPressed == null ? null : () => _press(onPressed!),
      style: TextButton.styleFrom(
        foregroundColor: effective,
        minimumSize: Size(0, size.height),
      ),
      child: _ButtonContent(
        label: label,
        icon: icon,
        isLoading: false,
        color: effective,
      ),
    );
  }
}

class HaynDestructiveButton extends StatelessWidget {
  const HaynDestructiveButton({
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
    this.size = HaynButtonSize.normal,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expanded;
  final HaynButtonSize size;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    final hc = context.hc;
    return _BaseButton(
      expanded: expanded,
      size: size,
      child: FilledButton(
        onPressed: disabled ? null : () => _pressMedium(onPressed!),
        style: FilledButton.styleFrom(
          minimumSize: Size(0, size.height),
          backgroundColor: hc.dangerColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: hc.dangerColor.withValues(alpha: 0.4),
        ),
        child: _ButtonContent(
          label: label,
          icon: icon,
          isLoading: isLoading,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ── Internal helpers ────────────────────────────────────────────────────────

class _BaseButton extends StatelessWidget {
  const _BaseButton({
    required this.child,
    required this.expanded,
    required this.size,
  });
  final Widget child;
  final bool expanded;
  final HaynButtonSize size;

  @override
  Widget build(BuildContext context) {
    return expanded
        ? SizedBox(width: double.infinity, height: size.height, child: child)
        : SizedBox(height: size.height, child: child);
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.color,
  });

  final String label;
  final IconData? icon;
  final bool isLoading;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.s2),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

void _press(VoidCallback cb) {
  HapticFeedback.lightImpact();
  cb();
}

void _pressMedium(VoidCallback cb) {
  HapticFeedback.mediumImpact();
  cb();
}
