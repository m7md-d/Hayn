import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RotateFlipBar — five-button row for crop transforms: rotate CCW, rotate
// CW, flip horizontal, flip vertical, reset. Each button is icon-only with a
// label tooltip so the row stays compact at narrow widths.
// ─────────────────────────────────────────────────────────────────────────────

class RotateFlipBar extends StatelessWidget {
  const RotateFlipBar({
    required this.onRotateCcw,
    required this.onRotateCw,
    required this.onFlipH,
    required this.onFlipV,
    required this.onReset,
    super.key,
  });

  final VoidCallback onRotateCcw;
  final VoidCallback onRotateCw;
  final VoidCallback onFlipH;
  final VoidCallback onFlipV;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
      child: Row(
        children: [
          Expanded(
              child: _BarButton(
                  icon: Icons.rotate_left_rounded,
                  label: l.cropRotateCcw,
                  onTap: onRotateCcw)),
          Expanded(
              child: _BarButton(
                  icon: Icons.rotate_right_rounded,
                  label: l.cropRotateCw,
                  onTap: onRotateCw)),
          Expanded(
              child: _BarButton(
                  icon: Icons.flip_rounded,
                  label: l.cropFlipH,
                  onTap: onFlipH)),
          Expanded(
              child: _BarButton(
                  icon: Icons.flip_rounded,
                  label: l.cropFlipV,
                  onTap: onFlipV,
                  rotateIconQuarter: 1)),
          Expanded(
              child: _BarButton(
                  icon: Icons.refresh_rounded,
                  label: l.cropReset,
                  onTap: onReset)),
        ],
      ),
    );
  }
}

class _BarButton extends StatefulWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.rotateIconQuarter = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// 1 = rotate the icon 90° (used to show V-flip as a 90°-turned H-flip).
  final int rotateIconQuarter;

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        duration: AppDuration.micro,
        scale: _pressed ? 0.92 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: widget.rotateIconQuarter * 1.5707963267948966, // π/2
              child: Icon(widget.icon, size: 22, color: hc.text2),
            ),
            const SizedBox(height: 4),
            Text(
              widget.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: hc.text3,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
