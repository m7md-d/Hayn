import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/isolates/task_runner.dart';
import '../../../shared/widgets/widgets.dart';
import '../../library/presentation/providers/asset_entity_cache.dart';
import '../../video_ops/data/animate_gif_task.dart';
import '../../video_ops/presentation/widgets/video_timeline.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnimateFromVideoScreen — pick a sub-range of a video and export it as a
// looping animated asset (WebP / AVIF / GIF). Layout:
//   • Preview thumbnail with play overlay
//   • Range timeline (start/end handles)
//   • Format chips, FPS slider, output size chips
//   • Estimated size card + Export
// ─────────────────────────────────────────────────────────────────────────────

enum _AnimFormat { webp, avif, gif }

class AnimateFromVideoScreen extends ConsumerStatefulWidget {
  const AnimateFromVideoScreen({required this.assetId, super.key});
  final String assetId;

  @override
  ConsumerState<AnimateFromVideoScreen> createState() =>
      _AnimateFromVideoScreenState();
}

class _AnimateFromVideoScreenState
    extends ConsumerState<AnimateFromVideoScreen> {
  AssetEntity? _asset;
  Uint8List? _thumb;

  double _start = 0;
  double _end = 0;
  _AnimFormat _format = _AnimFormat.webp;
  double _fps = 12;
  String _resolution = '720p';

  @override
  void initState() {
    super.initState();
    final cached = AssetEntityCache.get(widget.assetId);
    if (cached != null) {
      _asset = cached;
      _end = cached.videoDuration.inSeconds.toDouble().clamp(0.0, 10.0);
      _loadThumb();
    } else {
      AssetEntityCache.load(widget.assetId).then((a) {
        if (!mounted || a == null) return;
        setState(() {
          _asset = a;
          _end = a.videoDuration.inSeconds.toDouble().clamp(0.0, 10.0);
        });
        _loadThumb();
      });
    }
  }

  Future<void> _loadThumb() async {
    final data = await _asset!.thumbnailDataWithSize(
      const ThumbnailSize.square(720),
    );
    if (mounted) setState(() => _thumb = data);
  }

  String _estimatedSize() {
    final dur = (_end - _start).clamp(0.1, 60.0);
    final pixels = switch (_resolution) {
      '720p' => 1280 * 720,
      '480p' => 854 * 480,
      _ => 1920 * 1080,
    };
    final formatFactor = switch (_format) {
      _AnimFormat.avif => 0.35,
      _AnimFormat.webp => 0.55,
      _AnimFormat.gif => 1.4,
    };
    final bytes = (pixels * _fps * dur * 0.0005 * formatFactor).round();
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _export() {
    HapticFeedback.lightImpact();
    final l = AppLocalizations.of(context);
    // GIF is encodable now (ffmpeg, lightweight); animated WebP/AVIF land via
    // DarkLib — until then, say so honestly rather than fake a queued success.
    if (_format != _AnimFormat.gif) {
      HaynSnack.info(context, l.toolsComingSoon);
      return;
    }
    final h = switch (_resolution) {
      '480p' => 480,
      '1080p' => 1080,
      _ => 720,
    };
    unawaited(
      ref.read(taskRunnerProvider.notifier).enqueue(
            AnimateGifFromVideoTask(
              assetId: widget.assetId,
              startSeconds: _start,
              endSeconds: _end,
              fps: _fps.round(),
              height: h,
            ),
          ),
    );
    HaynSnack.success(context, l.animatedExportQueued);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final theme = Theme.of(context);
    final asset = _asset;
    if (asset == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final durationSec = asset.videoDuration.inSeconds.toDouble();

    return HaynScaffold(
      appBar: HaynModalAppBar(
        title: l.toolAnimateFromVideo,
        onDone: _export,
        doneLabel: l.animatedExport,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.s2, AppSpacing.md, 120,
        ),
        children: [
          // ── Preview ────────────────────────────────────────────────────
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_thumb != null)
                    Image.memory(
                      _thumb!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 30),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Range timeline ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.s3,
            ),
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              children: [
                Text(
                  l.animatedRange,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: hc.text2,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: AppSpacing.s1),
                VideoTimeline(
                  duration: durationSec,
                  start: _start,
                  end: _end,
                  onChanged: (s, e) => setState(() {
                    _start = s;
                    _end = e;
                  }),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatTime(_start),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: hc.text2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      '${l.animatedLength} ${_formatTime(_end - _start)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: hc.accent,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      _formatTime(_end),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: hc.text2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Format + FPS + Resolution settings ─────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(l.animatedFormat, style: theme.textTheme.bodyMedium)),
                    _PickChip(
                      label: 'WebP',
                      selected: _format == _AnimFormat.webp,
                      onTap: () => setState(() => _format = _AnimFormat.webp),
                    ),
                    const SizedBox(width: 4),
                    _PickChip(
                      label: 'AVIF',
                      selected: _format == _AnimFormat.avif,
                      onTap: () => setState(() => _format = _AnimFormat.avif),
                    ),
                    const SizedBox(width: 4),
                    _PickChip(
                      label: 'GIF',
                      selected: _format == _AnimFormat.gif,
                      onTap: () => setState(() => _format = _AnimFormat.gif),
                    ),
                  ],
                ),
                const Divider(height: AppSpacing.lg),
                HaynValueSlider(
                  label: l.animatedFrameRate,
                  valueLabel: '${_fps.round()} ${l.animatedFpsUnit}',
                  value: _fps,
                  min: 6,
                  max: 30,
                  divisions: 12,
                  onChanged: (v) => setState(() => _fps = v),
                ),
                const Divider(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(child: Text(l.animatedSize, style: theme.textTheme.bodyMedium)),
                    for (final r in const ['480p', '720p', '1080p'])
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 4),
                        child: _PickChip(
                          label: r,
                          selected: _resolution == r,
                          onTap: () => setState(() => _resolution = r),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Estimate ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: hc.surface2,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: hc.border),
            ),
            child: Row(
              children: [
                Icon(Icons.sd_storage_outlined, size: 18, color: hc.text2),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Text(
                    l.animatedEstimatedSize,
                    style: theme.textTheme.bodyMedium?.copyWith(color: hc.text2),
                  ),
                ),
                Text(
                  _estimatedSize(),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: hc.successColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          HaynPrimaryButton(
            label: l.animatedExport,
            icon: Icons.movie_creation_outlined,
            onPressed: _export,
            size: HaynButtonSize.large,
          ),

          const SizedBox(height: AppSpacing.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 12, color: hc.text3),
              const SizedBox(width: 4),
              Text(
                l.settingsPrivacy,
                style: theme.textTheme.labelSmall?.copyWith(color: hc.text3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(double s) {
    final m = s ~/ 60;
    final sec = (s % 60).toStringAsFixed(1);
    return '${m.toString().padLeft(2, '0')}:${sec.padLeft(4, '0')}';
  }
}

class _PickChip extends StatelessWidget {
  const _PickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: AppDuration.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3, vertical: AppSpacing.s1 + 1),
        decoration: BoxDecoration(
          color: selected ? hc.accent : hc.surface2,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: selected ? hc.accent : hc.border),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: selected ? hc.onAccent : hc.text2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
