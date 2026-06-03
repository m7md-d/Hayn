import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/widgets.dart';
import '../../tasks/presentation/widgets/tasks_app_bar_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ToolsScreen — clean visual hierarchy: three full-width hero tools (Compress,
// Extract frames, Surgical replace) anchor the screen, with everyday tools
// living in a 2-column grid between them. No section headers — the layout
// itself groups by emphasis.
// ─────────────────────────────────────────────────────────────────────────────

class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final theme = Theme.of(context);

    final compress = _Tool(
      icon: Icons.compress_rounded,
      title: l.toolCompressMedia,
      desc: l.toolCompressMediaDesc,
    );
    final extract = _Tool(
      icon: Icons.image_aspect_ratio_rounded,
      title: l.toolExtractFrames,
      desc: l.toolExtractFramesDesc,
    );

    // Two-up rows between the heroes.
    final pairsTop = <List<_Tool>>[
      [
        _Tool(icon: Icons.crop_rounded, title: l.toolCrop, desc: l.toolCropDesc),
        _Tool(icon: Icons.content_cut_rounded, title: l.toolTrim, desc: l.toolTrimDesc),
      ],
      [
        _Tool(icon: Icons.crop_free_rounded, title: l.toolCropVideo, desc: l.toolCropVideoDesc),
        _Tool(icon: Icons.volume_off_rounded, title: l.toolRemoveAudio, desc: l.toolRemoveAudioDesc),
      ],
      [
        _Tool(icon: Icons.auto_fix_high_rounded, title: l.toolStripMetadata, desc: l.toolStripDesc),
        _Tool(icon: Icons.graphic_eq_rounded, title: l.toolSeparateMusic, desc: l.toolSeparateDesc),
      ],
    ];

    final pairsBottom = <List<_Tool>>[
      [
        _Tool(icon: Icons.movie_filter_rounded, title: l.toolAnimateFromVideo, desc: l.toolAnimateFromVideoDesc),
        _Tool(icon: Icons.collections_rounded, title: l.toolAnimateFromPhotos, desc: l.toolAnimateFromPhotosDesc),
      ],
    ];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        // Not primary: the Library grid owns the single PrimaryScrollController
        // so iOS status-bar-tap-to-top has one unambiguous target across tabs.
        primary: false,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverAppBar.large(
            pinned: true,
            stretch: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            shadowColor: hc.border,
            scrolledUnderElevation: 0.5,
            automaticallyImplyLeading: false,
            title: Text(l.toolsTitle),
            actions: const [TasksAppBarButton()],
            expandedHeight: 112,
            systemOverlayStyle: theme.brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.s2, AppSpacing.md, 96,
            ),
            sliver: SliverList.list(children: [
              // Hero #1 — Compress (the everyday operation)
              _HeroCard(
                tool: compress,
                tone: _HeroTone.primary,
                onTap: () => _showComingSoon(context),
              ),
              const SizedBox(height: AppSpacing.s3),

              for (final pair in pairsTop) ...[
                _GridRow(pair: pair, onTap: () => _showComingSoon(context)),
                const SizedBox(height: AppSpacing.s3),
              ],

              // Hero #2 — Extract frames (unique operation)
              _HeroCard(
                tool: extract,
                tone: _HeroTone.neutral,
                onTap: () => _showComingSoon(context),
              ),
              const SizedBox(height: AppSpacing.s3),

              for (final pair in pairsBottom) ...[
                _GridRow(pair: pair, onTap: () => _showComingSoon(context)),
                const SizedBox(height: AppSpacing.s3),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    HapticFeedback.lightImpact();
    HaynSnack.info(context, AppLocalizations.of(context).toolsComingSoon);
  }
}

class _Tool {
  const _Tool({required this.icon, required this.title, required this.desc});
  final IconData icon;
  final String title;
  final String desc;
}

enum _HeroTone { primary, neutral, danger }

// ─────────────────────────────────────────────────────────────────────────────
// _HeroCard — full-width tool card. Three tones map to visual weight:
//   primary  → accent fill icon (Compress)
//   neutral  → accent-soft icon, no border (Extract frames)
//   danger   → accent-soft border, danger icon hint (Surgical replace)
// ─────────────────────────────────────────────────────────────────────────────
class _HeroCard extends StatefulWidget {
  const _HeroCard({
    required this.tool,
    required this.tone,
    required this.onTap,
  });
  final _Tool tool;
  final _HeroTone tone;
  final VoidCallback onTap;

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final tool = widget.tool;

    final iconBg = switch (widget.tone) {
      _HeroTone.primary => hc.accent,
      _HeroTone.neutral => hc.accentSoft,
      _HeroTone.danger => hc.accentSoft,
    };
    final iconFg = switch (widget.tone) {
      _HeroTone.primary => hc.onAccent,
      _HeroTone.neutral => hc.accent,
      _HeroTone.danger => hc.accent,
    };
    final border = switch (widget.tone) {
      _HeroTone.primary => null,
      _HeroTone.neutral => null,
      _HeroTone.danger => Border.all(color: hc.accentSoft, width: 1.5),
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: AppDuration.micro,
        curve: AppCurves.standard,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: border,
          ),
          child: Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: Icon(tool.icon, color: iconFg, size: 26),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tool.desc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: hc.text2,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: hc.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GridRow — exactly two cards side by side. Keeps the grid rhythm consistent.
// ─────────────────────────────────────────────────────────────────────────────
class _GridRow extends StatelessWidget {
  const _GridRow({required this.pair, required this.onTap});
  final List<_Tool> pair;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Height accommodates: 16 padding + 36 icon + spacer + 22 title + 2 gap +
    // 32 (2-line desc) + 16 padding = 124. Bump to 132 to absorb font-metric
    // variance across locales.
    return SizedBox(
      height: 132,
      child: Row(
        children: [
          Expanded(child: _GridCard(tool: pair[0], onTap: onTap)),
          const SizedBox(width: AppSpacing.s3),
          Expanded(child: _GridCard(tool: pair[1], onTap: onTap)),
        ],
      ),
    );
  }
}

class _GridCard extends StatefulWidget {
  const _GridCard({required this.tool, required this.onTap});
  final _Tool tool;
  final VoidCallback onTap;

  @override
  State<_GridCard> createState() => _GridCardState();
}

class _GridCardState extends State<_GridCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final tool = widget.tool;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: AppDuration.micro,
        curve: AppCurves.standard,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: hc.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(tool.icon, color: hc.accent, size: 20),
              ),
              const Spacer(),
              Text(
                tool.title,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                tool.desc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: hc.text2,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
