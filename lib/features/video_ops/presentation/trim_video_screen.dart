import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/widgets.dart';
import '../../library/presentation/providers/library_provider.dart';
import '../../library/presentation/widgets/asset_video_player.dart';
import 'widgets/video_timeline.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TrimVideoScreen — dedicated trim editor.
//
//   ┌── AppBar ─────────────────────────────────────┐
//   │ [Cancel]   Trim                       [Done] │
//   ├───────────────────────────────────────────────┤
//   │                                               │
//   │           [Video preview + controls]          │
//   │                                               │
//   ├───────────────────────────────────────────────┤
//   │  [Banner: Lossless / Smart Cut]              │
//   │                                               │
//   │  [Timeline scrubber with start/end handles]  │
//   │  Start: 0:00.0     Trimmed: 0:12.4    End:.. │
//   │                                               │
//   │  [Save trimmed clip]                          │
//   │  Trim keyframe-aligned = no re-encode         │
//   └───────────────────────────────────────────────┘
// ─────────────────────────────────────────────────────────────────────────────

class TrimVideoScreen extends ConsumerStatefulWidget {
  const TrimVideoScreen({required this.assetId, super.key});
  final String assetId;

  @override
  ConsumerState<TrimVideoScreen> createState() => _TrimVideoScreenState();
}

class _TrimVideoScreenState extends ConsumerState<TrimVideoScreen> {
  AssetEntity? _asset;
  double _start = 0;
  double _end = 0;

  @override
  void initState() {
    super.initState();
    final all = ref.read(libraryProvider).assets;
    _asset = all.firstWhere(
      (a) => a.id == widget.assetId,
      orElse: () => all.first,
    );
    _end = _asset!.videoDuration.inSeconds.toDouble();
  }

  /// Stub heuristic: trim is "lossless" when both edges sit at the existing
  /// keyframes (here: every 2s). Real implementation will probe the file.
  bool get _isLossless {
    final duration = _asset?.videoDuration.inSeconds.toDouble() ?? 0;
    return _start < 0.2 && (duration - _end) < 0.2;
  }

  Future<void> _apply() async {
    HapticFeedback.lightImpact();
    final l = AppLocalizations.of(context);
    HaynSnack.success(context, l.trimQueued);
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
    final duration = asset.videoDuration.inSeconds.toDouble();
    final trimmed = _end - _start;
    final keyframes =
        List.generate((duration / 2).floor(), (i) => i * 2.0);

    return HaynScaffold(
      appBar: HaynModalAppBar(
        title: l.toolTrim,
        onDone: _apply,
        doneLabel: l.commonDone,
      ),
      body: Column(
        children: [
          // ── Preview ─────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: asset.width / asset.height,
                      child: AssetVideoPlayer(asset: asset),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Controls ────────────────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, 0, AppSpacing.md, AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HaynInlineBanner(
                    tone: _isLossless
                        ? HaynBannerTone.success
                        : HaynBannerTone.warning,
                    icon: _isLossless
                        ? Icons.flash_on_rounded
                        : Icons.science_outlined,
                    message: _isLossless
                        ? l.videoEditorTrimLossless
                        : l.videoEditorTrimSmart,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  VideoTimeline(
                    duration: duration,
                    start: _start,
                    end: _end,
                    keyframeSecs: keyframes,
                    onChanged: (s, e) => setState(() {
                      _start = s;
                      _end = e;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.s2),

                  // Time readouts
                  Row(
                    children: [
                      _TimeReadout(
                          label: l.videoEditorStart,
                          value: _formatTime(_start),
                          color: hc.text2),
                      const Spacer(),
                      Text(
                        _formatTime(trimmed),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: hc.accent,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      _TimeReadout(
                          label: l.videoEditorEnd,
                          value: _formatTime(_end),
                          color: hc.text2),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  HaynPrimaryButton(
                    label: l.trimActionLabel,
                    icon: Icons.content_cut_rounded,
                    onPressed: _apply,
                    size: HaynButtonSize.large,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 12, color: hc.text3),
                      const SizedBox(width: 4),
                      Text(
                        l.settingsPrivacy,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: hc.text3),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(double s) {
    final m = s ~/ 60;
    final sec = (s % 60).floor();
    final ds = ((s - s.floor()) * 10).floor();
    return '$m:${sec.toString().padLeft(2, '0')}.$ds';
  }
}

class _TimeReadout extends StatelessWidget {
  const _TimeReadout({
    required this.label,
    required this.value,
    required this.color,
  });
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
