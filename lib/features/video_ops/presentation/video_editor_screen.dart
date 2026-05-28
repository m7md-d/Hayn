import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/motion.dart';
import '../../../shared/widgets/widgets.dart';
import '../../library/presentation/providers/library_provider.dart';
import 'widgets/video_timeline.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VideoEditorScreen — single editor with a segmented mode switcher:
// Trim / Crop / Compress / Audio. Top half shows a placeholder player
// (real video playback ships when video_player is wired in).
//
// The Trim mode is the most polished — it owns the timeline. Crop, Compress
// and Audio panels show their respective controls and share an Export action.
// ─────────────────────────────────────────────────────────────────────────────

enum _Mode { trim, crop, compress, audio }

class VideoEditorScreen extends ConsumerStatefulWidget {
  const VideoEditorScreen({required this.assetId, super.key});
  final String assetId;

  @override
  ConsumerState<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends ConsumerState<VideoEditorScreen> {
  AssetEntity? _asset;
  Uint8List? _thumb;

  _Mode _mode = _Mode.trim;

  // Trim state
  double _start = 0;
  double _end = 0;

  // Crop state
  String _aspect = 'free';

  // Compress state
  String _format = 'H.265';
  double _quality = 70;
  String _resolution = 'original';

  // Audio state
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    final all = ref.read(libraryProvider).assets;
    _asset = all.firstWhere(
      (a) => a.id == widget.assetId,
      orElse: () => all.first,
    );
    _end = _asset!.videoDuration.inSeconds.toDouble();
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    final data = await _asset!.thumbnailDataWithSize(
      const ThumbnailSize.square(720),
    );
    if (mounted) setState(() => _thumb = data);
  }

  void _export() {
    HapticFeedback.lightImpact();
    final l = AppLocalizations.of(context);
    HaynSnack.success(context, l.videoEditorExporting);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final asset = _asset;
    if (asset == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return HaynScaffold(
      appBar: HaynModalAppBar(
        title: l.videoEditorTitle,
        onDone: _export,
        doneLabel: l.videoEditorExport,
      ),
      body: Column(
        children: [
          // ── Player area ───────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Container(
              color: Colors.black,
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_thumb != null)
                      AspectRatio(
                        aspectRatio: asset.width / asset.height,
                        child: Image.memory(
                          _thumb!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    const _PlayButtonOverlay(),
                  ],
                ),
              ),
            ),
          ),

          // ── Mode tabs ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.s3,
            ),
            child: HaynSegmentedPill<_Mode>(
              value: _mode,
              onChanged: (m) => setState(() => _mode = m),
              items: [
                HaynSegmentItem(value: _Mode.trim, label: l.toolTrim),
                HaynSegmentItem(value: _Mode.crop, label: l.toolCropVideo),
                HaynSegmentItem(value: _Mode.compress, label: l.toolCompressVideo),
                HaynSegmentItem(value: _Mode.audio, label: l.toolRemoveAudio),
              ],
              height: 40,
            ),
          ),

          // ── Mode panel ────────────────────────────────────────────────
          Expanded(
            flex: 4,
            child: AnimatedSwitcher(
              duration: AppDuration.normal,
              switchInCurve: AppCurves.decelerate,
              transitionBuilder: fadeScaleTransition,
              child: KeyedSubtree(
                key: ValueKey(_mode),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, 0, AppSpacing.md, AppSpacing.md,
                  ),
                  child: _buildPanel(hc),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(HaynColors hc) {
    switch (_mode) {
      case _Mode.trim:
        return _TrimPanel(
          duration: _asset!.videoDuration.inSeconds.toDouble(),
          start: _start,
          end: _end,
          onChanged: (s, e) => setState(() {
            _start = s;
            _end = e;
          }),
        );
      case _Mode.crop:
        return _CropPanel(
          aspect: _aspect,
          onAspect: (a) => setState(() => _aspect = a),
        );
      case _Mode.compress:
        return _CompressVideoPanel(
          format: _format,
          quality: _quality,
          resolution: _resolution,
          onFormat: (f) => setState(() => _format = f),
          onQuality: (v) => setState(() => _quality = v),
          onResolution: (r) => setState(() => _resolution = r),
        );
      case _Mode.audio:
        return _AudioPanel(
          assetId: widget.assetId,
          muted: _muted,
          onMuted: (v) => setState(() => _muted = v),
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Player overlay
// ─────────────────────────────────────────────────────────────────────────────
class _PlayButtonOverlay extends StatelessWidget {
  const _PlayButtonOverlay();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72, height: 72,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trim panel
// ─────────────────────────────────────────────────────────────────────────────
class _TrimPanel extends StatelessWidget {
  const _TrimPanel({
    required this.duration,
    required this.start,
    required this.end,
    required this.onChanged,
  });
  final double duration;
  final double start;
  final double end;
  final void Function(double, double) onChanged;

  bool get _isLossless {
    // Stub heuristic: if start ≈ 0 and end ≈ duration, treat as lossless.
    return start < 0.2 && (duration - end) < 0.2;
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final trimmed = end - start;

    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mode indicator: lossless / smart cut
        HaynInlineBanner(
          tone: _isLossless ? HaynBannerTone.success : HaynBannerTone.warning,
          icon: _isLossless
              ? Icons.flash_on_rounded
              : Icons.science_outlined,
          message: _isLossless
              ? l.videoEditorTrimLossless
              : l.videoEditorTrimSmart,
        ),
        const SizedBox(height: AppSpacing.md),

        // Timeline scrubber
        VideoTimeline(
          duration: duration,
          start: start,
          end: end,
          onChanged: onChanged,
          keyframeSecs: List.generate(
            (duration / 2).floor(),
            (i) => i * 2.0,
          ),
        ),

        const SizedBox(height: AppSpacing.s2),

        // Time labels
        Row(
          children: [
            _TimeChip(label: l.videoEditorStart, value: _format(start), color: hc.text2),
            const Spacer(),
            Text(
              _format(trimmed),
              style: theme.textTheme.titleLarge?.copyWith(
                color: hc.accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            _TimeChip(label: l.videoEditorEnd, value: _format(end), color: hc.text2),
          ],
        ),
      ],
    );
  }

  static String _format(double s) {
    final m = s ~/ 60;
    final sec = (s % 60).floor();
    final cs = ((s - s.floor()) * 10).floor();
    return '$m:${sec.toString().padLeft(2, '0')}.$cs';
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Crop panel
// ─────────────────────────────────────────────────────────────────────────────
class _CropPanel extends StatelessWidget {
  const _CropPanel({required this.aspect, required this.onAspect});
  final String aspect;
  final ValueChanged<String> onAspect;

  static const _aspects = ['free', '16:9', '1:1', '9:16', '4:3'];

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HaynInlineBanner(
          tone: HaynBannerTone.warning,
          icon: Icons.warning_amber_rounded,
          message: l.videoEditorCropWarning,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(l.videoEditorAspectRatio,
            style: theme.textTheme.bodyMedium?.copyWith(color: hc.text2)),
        const SizedBox(height: AppSpacing.s2),
        Wrap(
          spacing: AppSpacing.s2,
          runSpacing: AppSpacing.s2,
          children: [
            for (final a in _aspects)
              _AspectChip(
                label: a == 'free' ? l.videoEditorAspectFree : a,
                selected: aspect == a,
                onTap: () => onAspect(a),
              ),
          ],
        ),
        const Spacer(),
        Row(
          children: [
            const Spacer(),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.rotate_90_degrees_ccw_rounded),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.flip_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _AspectChip extends StatelessWidget {
  const _AspectChip({
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
            horizontal: AppSpacing.s3, vertical: AppSpacing.s2),
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

// ─────────────────────────────────────────────────────────────────────────────
// Video compress panel
// ─────────────────────────────────────────────────────────────────────────────
class _CompressVideoPanel extends StatelessWidget {
  const _CompressVideoPanel({
    required this.format,
    required this.quality,
    required this.resolution,
    required this.onFormat,
    required this.onQuality,
    required this.onResolution,
  });
  final String format;
  final double quality;
  final String resolution;
  final ValueChanged<String> onFormat;
  final ValueChanged<double> onQuality;
  final ValueChanged<String> onResolution;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                  Expanded(child: Text(l.videoEditorCodec, style: theme.textTheme.bodyMedium)),
                  for (final c in const ['H.264', 'H.265', 'AV1'])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 4),
                      child: _AspectChip(
                        label: c,
                        selected: format == c,
                        onTap: () => onFormat(c),
                      ),
                    ),
                ],
              ),
              const Divider(height: AppSpacing.lg),
              HaynValueSlider(
                label: l.compressQuality,
                valueLabel: '${quality.round()}',
                value: quality,
                min: 30, max: 100,
                divisions: 14,
                onChanged: onQuality,
              ),
              const Divider(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                      child: Text(l.videoEditorResolution, style: theme.textTheme.bodyMedium)),
                  for (final r in const ['original', '1080p', '720p'])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 4),
                      child: _AspectChip(
                        label: r == 'original' ? l.videoEditorResolutionOriginal : r,
                        selected: resolution == r,
                        onTap: () => onResolution(r),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Audio panel
// ─────────────────────────────────────────────────────────────────────────────
class _AudioPanel extends StatelessWidget {
  const _AudioPanel({
    required this.assetId,
    required this.muted,
    required this.onMuted,
  });
  final String assetId;
  final bool muted;
  final ValueChanged<bool> onMuted;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            children: [
              HaynToggleRow(
                leading: Icon(Icons.volume_off_rounded, color: hc.accent),
                label: l.toolRemoveAudio,
                description: l.toolRemoveAudioDesc,
                value: muted,
                onChanged: onMuted,
              ),
              Divider(color: hc.border, height: 0.5, thickness: 0.5),
              HaynListCell(
                leadingIcon: Icons.graphic_eq_rounded,
                label: l.toolSeparateMusic,
                description: l.toolSeparateDesc,
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.push('/audio-separate/$assetId');
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l.videoEditorRemoveLossless,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: hc.text2,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
