import 'package:flutter/material.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Badges — small pill-shaped indicators.
//
//   HaynStatusBadge        Pending / Running / Done / Cancelled / Failed
//   HaynSavingsBadge       Green: "−42%  4.2MB" with tabular numerals
//   HaynTagChip            Neutral: format tag (AVIF, HEIC, JPEG…)
//   HaynVideoDurationBadge Black: "0:14" overlay for video thumbnails
// ─────────────────────────────────────────────────────────────────────────────

enum HaynStatusKind { pending, running, completed, cancelled, failed }

class HaynStatusBadge extends StatelessWidget {
  const HaynStatusBadge({
    required this.kind,
    required this.label,
    super.key,
  });

  final HaynStatusKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final (color, bg) = switch (kind) {
      HaynStatusKind.pending => (hc.text3, hc.surfaceSunken),
      HaynStatusKind.running => (hc.accent, hc.accentSoft),
      HaynStatusKind.completed => (hc.successColor, hc.successSoft),
      HaynStatusKind.cancelled => (hc.warningColor, hc.warningSoft),
      HaynStatusKind.failed => (hc.dangerColor, hc.dangerSoft),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kind == HaynStatusKind.running)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.s1),
              child: SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: color,
                ),
              ),
            ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class HaynSavingsBadge extends StatelessWidget {
  const HaynSavingsBadge({
    required this.percent,
    this.bytes,
    this.compact = false,
    super.key,
  });

  /// Signed size change: negative = saved (e.g. -42 for 42 % smaller), positive
  /// = GREW (e.g. +12 for 12 % bigger). Compression isn't always positive — a
  /// PNG of a photo, or a small JPEG re-encoded, can grow — so the badge flips
  /// to a warning colour + up arrow when it does.
  final int percent;
  final String? bytes;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final grew = percent > 0;
    final color = grew ? hc.warningColor : hc.successColor;
    final bg = grew ? hc.warningSoft : hc.successSoft;
    final sign = grew ? '+' : '−';
    final label = bytes == null
        ? '$sign${percent.abs()}%'
        : '$sign${percent.abs()}%  •  $bytes';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.s2 : AppSpacing.s3,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(grew ? Icons.north_rounded : Icons.south_rounded,
              size: compact ? 12 : 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: (compact
                    ? theme.textTheme.labelSmall
                    : theme.textTheme.labelLarge)
                ?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class HaynTagChip extends StatelessWidget {
  const HaynTagChip({
    required this.label,
    this.icon,
    this.tone = HaynChipTone.neutral,
    super.key,
  });

  final String label;
  final IconData? icon;
  final HaynChipTone tone;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final (bg, fg) = switch (tone) {
      HaynChipTone.neutral => (hc.surfaceSunken, hc.text2),
      HaynChipTone.accent => (hc.accentSoft, hc.accent),
      HaynChipTone.success => (hc.successSoft, hc.successColor),
      HaynChipTone.warning => (hc.warningSoft, hc.warningColor),
      HaynChipTone.danger => (hc.dangerSoft, hc.dangerColor),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

enum HaynChipTone { neutral, accent, success, warning, danger }

class HaynVideoDurationBadge extends StatelessWidget {
  const HaynVideoDurationBadge({required this.duration, super.key});

  /// Seconds.
  final int duration;

  @override
  Widget build(BuildContext context) {
    final m = duration ~/ 60;
    final s = (duration % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.xs + 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 10),
          const SizedBox(width: 2),
          Text(
            '$m:$s',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
