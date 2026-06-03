import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../core/batch/batch_savings_estimator.dart';
import '../../../../core/capabilities/format_capabilities.dart';
import '../../../../data/index/index_providers.dart';
import '../../../settings/providers/preferences_providers.dart';
import '../providers/library_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SelectionToolbar — replaces the bottom nav while the user is selecting
// items. Two-layer structure:
//
//   ┌─ Savings chip ──────────────────────────────────────┐
//   │  ≈ 1.2 GB → 320 MB · −73%   ⓘ approximate           │
//   └─────────────────────────────────────────────────────┘
//   ┌─ Action row ────────────────────────────────────────┐
//   │  [Compress] [Clean] [Surgical] [More]               │
//   └─────────────────────────────────────────────────────┘
//
// The savings chip is asynchronous (file-size lookups happen in parallel)
// and uses the user's default format + quality as the projection target.
// ─────────────────────────────────────────────────────────────────────────────

class SelectionToolbar extends ConsumerWidget {
  const SelectionToolbar({
    required this.hasSelection,
    required this.isVideo,
    required this.onCompress,
    required this.onStripMetadata,
    required this.onVideoEdit,
    required this.onTrim,
    required this.onRemoveAudio,
    required this.onMore,
    super.key,
  });

  /// Whether anything is selected. The actual ids/assets are pulled by id where
  /// needed (estimate, downstream screens), never materialised here — so a
  /// 10k "select all" never builds a 10k AssetEntity list.
  final bool hasSelection;

  /// The selection is videos (single-type lock guarantees it's all-or-nothing).
  /// Drives which action set shows — image tools would be wrong for a video.
  final bool isVideo;

  final VoidCallback onCompress;
  final VoidCallback onStripMetadata;
  final VoidCallback onVideoEdit;
  final VoidCallback onTrim;
  final VoidCallback onRemoveAudio;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final l = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        border: Border(
          top: BorderSide(color: hc.border, width: AppHairline.thickness),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Savings chip (image selections only — it's a compression
            // estimate; videos go through their own pipeline). ────────────
            if (hasSelection && !isVideo)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.s2, AppSpacing.md, 0,
                ),
                child: const _SavingsChip(),
              ),
            // ── Action row — image vs video. ─────────────────────────────
            SizedBox(
              height: 64,
              child: isVideo
                  ? Row(
                      children: [
                        Expanded(
                          child: _ToolbarAction(
                            icon: Icons.video_settings_rounded,
                            label: l.selectionCompress,
                            tone: _ToolbarTone.primary,
                            enabled: hasSelection,
                            batchSupported: false,
                            onTap: onVideoEdit,
                          ),
                        ),
                        Expanded(
                          child: _ToolbarAction(
                            icon: Icons.content_cut_rounded,
                            label: l.toolTrim,
                            enabled: hasSelection,
                            batchSupported: false,
                            onTap: onTrim,
                          ),
                        ),
                        Expanded(
                          child: _ToolbarAction(
                            icon: Icons.music_off_rounded,
                            label: l.toolRemoveAudio,
                            enabled: hasSelection,
                            batchSupported: false,
                            onTap: onRemoveAudio,
                          ),
                        ),
                        Expanded(
                          child: _ToolbarAction(
                            icon: Icons.more_horiz_rounded,
                            label: l.selectionMore,
                            enabled: hasSelection,
                            batchSupported: true,
                            onTap: onMore,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _ToolbarAction(
                            icon: Icons.compress_rounded,
                            label: l.selectionCompress,
                            tone: _ToolbarTone.primary,
                            enabled: hasSelection,
                            batchSupported: true,
                            onTap: onCompress,
                          ),
                        ),
                        Expanded(
                          child: _ToolbarAction(
                            icon: Icons.auto_fix_high_rounded,
                            label: l.selectionStripMetadata,
                            enabled: hasSelection,
                            batchSupported: true,
                            onTap: onStripMetadata,
                          ),
                        ),
                        Expanded(
                          child: _ToolbarAction(
                            icon: Icons.more_horiz_rounded,
                            label: l.selectionMore,
                            enabled: hasSelection,
                            batchSupported: true,
                            onTap: onMore,
                          ),
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

// ─────────────────────────────────────────────────────────────────────────────
// _SavingsChip — async estimate from the BatchSavingsEstimator, projected
// using the user's default format + quality preferences.
// ─────────────────────────────────────────────────────────────────────────────

class _SavingsChip extends ConsumerStatefulWidget {
  const _SavingsChip();

  @override
  ConsumerState<_SavingsChip> createState() => _SavingsChipState();
}

class _SavingsChipState extends ConsumerState<_SavingsChip> {
  Future<BatchSavingsEstimate>? _future;
  int? _lastKey;

  Future<BatchSavingsEstimate> _estimate(
      List<String> ids, DefaultFormat format, int quality) async {
    // Mime-aware facts from the index, so the chip classifies each source the
    // SAME way the compress screen does — spanning the WHOLE selection (even
    // select-all over thousands), not just the loaded grid pages.
    final rows =
        await ref.read(mediaIndexDatabaseProvider).estimateFactsFor(ids);
    final facts = [
      for (final r in rows)
        BatchSavingsEstimator.factsFrom(
          sizeBytes: r.sizeBytes,
          width: r.width,
          height: r.height,
          mimeType: r.mimeType,
          title: r.title,
        ),
    ];
    return BatchSavingsEstimator.estimate(
        facts: facts, format: format, quality: quality);
  }

  @override
  Widget build(BuildContext context) {
    // Resolve `auto` to the codec that will actually run — the compress screen
    // models the real codec too, so both land on the same number.
    final caps = ref.watch(formatCapabilitiesProvider);
    final raw = ref.watch(defaultFormatProvider);
    final format =
        raw == DefaultFormat.auto ? DefaultFormat.resolveAuto(caps) : raw;
    final quality = qualityIntFor(ref.watch(defaultQualityProvider));
    final ids = ref.watch(libraryProvider.select((s) => s.selectedIds));
    final key = Object.hash(ids.length, format, quality);
    if (key != _lastKey) {
      _lastKey = key;
      _future = _estimate(ids.toList(), format, quality);
    }

    return FutureBuilder<BatchSavingsEstimate>(
      future: _future,
      builder: (ctx, snap) {
        final hc = ctx.hc;
        final theme = Theme.of(ctx);
        if (!snap.hasData) {
          return _ChipShell(
            child: SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: hc.text3,
              ),
            ),
          );
        }
        final est = snap.data!;
        if (est.totalOriginalBytes == 0) {
          return const SizedBox.shrink();
        }
        return _ChipShell(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                est.isApproximation ? '≈ ' : '',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: hc.text2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _formatBytes(est.totalOriginalBytes),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: hc.text3,
                  decoration: TextDecoration.lineThrough,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.east_rounded, size: 12, color: hc.text3),
              const SizedBox(width: 6),
              Text(
                _formatBytes(est.estimatedNewBytes),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: hc.successColor,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: hc.successSoft,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  '−${est.savedPercent}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: hc.successColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _ChipShell extends StatelessWidget {
  const _ChipShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3, vertical: 6),
        decoration: BoxDecoration(
          color: hc.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ToolbarAction — single icon + label cell. Subscript dot marks actions
// that don't support batches (currently none, but the affordance is wired
// for the next round of tools).
// ─────────────────────────────────────────────────────────────────────────────

enum _ToolbarTone { neutral, primary }

class _ToolbarAction extends StatefulWidget {
  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.batchSupported,
    this.tone = _ToolbarTone.neutral,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final _ToolbarTone tone;
  final bool batchSupported;

  @override
  State<_ToolbarAction> createState() => _ToolbarActionState();
}

class _ToolbarActionState extends State<_ToolbarAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final baseColor =
        widget.tone == _ToolbarTone.primary ? hc.accent : hc.text2;
    final color = widget.enabled
        ? baseColor
        : baseColor.withValues(alpha: 0.35);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown:
          widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel:
          widget.enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.enabled
          ? () {
              HapticFeedback.lightImpact();
              widget.onTap();
            }
          : null,
      child: AnimatedContainer(
        duration: AppDuration.micro,
        decoration: BoxDecoration(
          color: _pressed && widget.enabled
              ? hc.surfaceSunken
              : Colors.transparent,
        ),
        child: AnimatedScale(
          duration: AppDuration.micro,
          scale: _pressed && widget.enabled ? 0.94 : 1.0,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(widget.icon, size: 22, color: color),
                    if (!widget.batchSupported)
                      Positioned(
                        right: -4,
                        top: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: hc.warningColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: hc.surface, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: widget.tone == _ToolbarTone.primary
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
