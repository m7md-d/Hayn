import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/widgets.dart';
import '../../library/presentation/providers/asset_entity_cache.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ExtractFramesScreen — pick a method (every N seconds / fps / single frame),
// preview the resulting grid, then save them as still images.
// ─────────────────────────────────────────────────────────────────────────────

enum _Method { everyNSeconds, atFps, single }

class ExtractFramesScreen extends ConsumerStatefulWidget {
  const ExtractFramesScreen({required this.assetId, super.key});
  final String assetId;

  @override
  ConsumerState<ExtractFramesScreen> createState() =>
      _ExtractFramesScreenState();
}

class _ExtractFramesScreenState extends ConsumerState<ExtractFramesScreen> {
  AssetEntity? _asset;
  Uint8List? _thumb;

  _Method _method = _Method.everyNSeconds;
  double _interval = 5; // seconds for everyNSeconds
  double _fps = 1; // for atFps
  double _cursor = 0; // for single

  @override
  void initState() {
    super.initState();
    final cached = AssetEntityCache.get(widget.assetId);
    _asset = cached;
    if (cached == null) {
      AssetEntityCache.load(widget.assetId).then((a) {
        if (!mounted || a == null) return;
        setState(() => _asset = a);
        _loadThumb();
      });
    } else {
      _loadThumb();
    }
  }

  Future<void> _loadThumb() async {
    final data = await _asset!.thumbnailDataWithSize(
      const ThumbnailSize.square(360),
    );
    if (mounted) setState(() => _thumb = data);
  }

  int get _previewCount {
    final dur = _asset!.videoDuration.inSeconds;
    switch (_method) {
      case _Method.everyNSeconds:
        return (dur / _interval).floor().clamp(1, 64);
      case _Method.atFps:
        return (dur * _fps).floor().clamp(1, 64);
      case _Method.single:
        return 1;
    }
  }

  void _save() {
    HapticFeedback.lightImpact();
    final l = AppLocalizations.of(context);
    HaynSnack.success(context, l.framesSavingCount(_previewCount));
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

    return HaynScaffold(
      appBar: HaynModalAppBar(
        title: l.toolExtractFrames,
        onDone: _save,
        doneLabel: l.commonSave,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.s2, AppSpacing.md, 120,
        ),
        children: [
          // ── Method selector ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HaynSegmentedPill<_Method>(
                  value: _method,
                  onChanged: (m) => setState(() => _method = m),
                  items: [
                    HaynSegmentItem(
                        value: _Method.everyNSeconds, label: l.framesInterval),
                    HaynSegmentItem(value: _Method.atFps, label: l.framesFps),
                    HaynSegmentItem(value: _Method.single, label: l.framesSingle),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (_method == _Method.everyNSeconds)
                  HaynValueSlider(
                    label: l.framesEvery,
                    valueLabel: '${_interval.round()} ${l.framesSecondsUnit}',
                    value: _interval,
                    min: 1,
                    max: 30,
                    divisions: 29,
                    onChanged: (v) => setState(() => _interval = v),
                    helper: l.framesEstimatedCount(_previewCount),
                  )
                else if (_method == _Method.atFps)
                  HaynValueSlider(
                    label: l.framesFps,
                    valueLabel: '${_fps.toStringAsFixed(1)} ${l.animatedFpsUnit}',
                    value: _fps,
                    min: 0.1,
                    max: 4,
                    divisions: 39,
                    onChanged: (v) => setState(() => _fps = v),
                    helper: l.framesEstimatedCount(_previewCount),
                  )
                else
                  HaynValueSlider(
                    label: l.framesPosition,
                    valueLabel: '${_cursor.toStringAsFixed(1)} ${l.framesSecondsUnit}',
                    value: _cursor,
                    min: 0,
                    max: asset.videoDuration.inSeconds.toDouble(),
                    onChanged: (v) => setState(() => _cursor = v),
                    helper: l.framesSingleAtTimestamp,
                  ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Preview grid ───────────────────────────────────────────────
          Text(
            l.framesPreview,
            style: theme.textTheme.labelMedium?.copyWith(
              color: hc.text2,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          if (_thumb == null)
            HaynSkeleton.rect(width: double.infinity, height: 200)
          else
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: AppSpacing.s1,
                mainAxisSpacing: AppSpacing.s1,
              ),
              itemCount: _previewCount.clamp(1, 16),
              itemBuilder: (ctx, i) => Container(
                decoration: BoxDecoration(
                  color: hc.surfaceSunken,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Image.memory(_thumb!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        gaplessPlayback: true),
                    PositionedDirectional(
                      bottom: 2, start: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_previewCount > 16)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s2),
              child: Text(
                l.framesMore(_previewCount - 16),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(color: hc.text2),
              ),
            ),

          const SizedBox(height: AppSpacing.lg),

          HaynPrimaryButton(
            label: l.framesSaveCount(_previewCount),
            icon: Icons.download_rounded,
            onPressed: _save,
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
}
