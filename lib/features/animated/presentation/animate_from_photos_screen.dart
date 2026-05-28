import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/widgets.dart';
import '../../library/presentation/providers/library_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnimateFromPhotosScreen — drag-reorderable list of selected frames + per
// playback fps + format. Tap+hold a thumbnail to reorder; tap × to remove.
// ─────────────────────────────────────────────────────────────────────────────

enum _AnimFormat { webp, avif, gif }

class AnimateFromPhotosScreen extends ConsumerStatefulWidget {
  const AnimateFromPhotosScreen({required this.assetIds, super.key});
  final List<String> assetIds;

  @override
  ConsumerState<AnimateFromPhotosScreen> createState() =>
      _AnimateFromPhotosScreenState();
}

class _AnimateFromPhotosScreenState
    extends ConsumerState<AnimateFromPhotosScreen> {
  late List<AssetEntity> _frames;
  _AnimFormat _format = _AnimFormat.webp;
  double _fps = 6;
  bool _loop = true;

  @override
  void initState() {
    super.initState();
    final all = ref.read(libraryProvider).assets;
    _frames = widget.assetIds
        .map((id) => all.firstWhere(
              (a) => a.id == id,
              orElse: () => all.first,
            ))
        .toList();
  }

  void _export() {
    HapticFeedback.lightImpact();
    final l = AppLocalizations.of(context);
    HaynSnack.success(context, l.animatedPhotosExportQueued);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final theme = Theme.of(context);

    return HaynScaffold(
      appBar: HaynModalAppBar(
        title: l.toolAnimateFromPhotos,
        onDone: _frames.length >= 2 ? _export : null,
        doneLabel: l.animatedExport,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.s2, AppSpacing.md, 120,
        ),
        children: [
          // ── Frame strip (reorderable) ─────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            padding: const EdgeInsets.all(AppSpacing.s3),
            height: 116,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              proxyDecorator: (child, _, __) => Material(
                color: Colors.transparent,
                elevation: 6,
                shadowColor: Colors.black,
                child: child,
              ),
              itemCount: _frames.length,
              onReorderItem: (oldIndex, newIndex) {
                HapticFeedback.lightImpact();
                setState(() {
                  final item = _frames.removeAt(oldIndex);
                  _frames.insert(newIndex, item);
                });
              },
              itemBuilder: (ctx, i) {
                final asset = _frames[i];
                return Padding(
                  key: ValueKey(asset.id),
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.s2),
                  child: _FrameTile(
                    asset: asset,
                    index: i,
                    onRemove: () =>
                        setState(() => _frames.removeAt(i)),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: AppSpacing.s2),
          Text(
            '${l.animatedReorderHint} · ${l.animatedFramesCount(_frames.length)}',
            style: theme.textTheme.labelSmall?.copyWith(color: hc.text2),
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Settings card ─────────────────────────────────────────────
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
                    for (final f in _AnimFormat.values)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 4),
                        child: _MiniChip(
                          label: f.name.toUpperCase(),
                          selected: _format == f,
                          onTap: () => setState(() => _format = f),
                        ),
                      ),
                  ],
                ),
                const Divider(height: AppSpacing.lg),
                HaynValueSlider(
                  label: l.animatedFrameRate,
                  valueLabel: '${_fps.round()} ${l.animatedFpsUnit}',
                  value: _fps,
                  min: 1,
                  max: 24,
                  divisions: 23,
                  onChanged: (v) => setState(() => _fps = v),
                  helper: _fps < 4
                      ? l.animatedSlideshow
                      : _fps > 15
                          ? l.animatedSmooth
                          : l.animatedStandard,
                ),
                const Divider(height: AppSpacing.lg),
                HaynToggleRow(
                  leading: Icon(Icons.loop_rounded, color: hc.accent),
                  label: l.animatedLoop,
                  description: l.animatedLoopDesc,
                  value: _loop,
                  onChanged: (v) => setState(() => _loop = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          HaynPrimaryButton(
            label: l.animatedExport,
            icon: Icons.gif_box_outlined,
            onPressed: _frames.length >= 2 ? _export : null,
            size: HaynButtonSize.large,
          ),

          if (_frames.length < 2) ...[
            const SizedBox(height: AppSpacing.s2),
            Text(
              l.animatedSelectAtLeast2,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: hc.text2),
            ),
          ],

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

class _MiniChip extends StatelessWidget {
  const _MiniChip({
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
            horizontal: AppSpacing.s2, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? hc.accent : hc.surface2,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: selected ? hc.accent : hc.border),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: selected ? hc.onAccent : hc.text2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _FrameTile extends StatefulWidget {
  const _FrameTile({
    required this.asset,
    required this.index,
    required this.onRemove,
  });
  final AssetEntity asset;
  final int index;
  final VoidCallback onRemove;

  @override
  State<_FrameTile> createState() => _FrameTileState();
}

class _FrameTileState extends State<_FrameTile> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize.square(200),
    );
    if (mounted) setState(() => _thumb = data);
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return SizedBox(
      width: 88,
      child: Stack(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: hc.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            clipBehavior: Clip.antiAlias,
            child: _thumb == null
                ? null
                : Image.memory(_thumb!,
                    fit: BoxFit.cover, gaplessPlayback: true),
          ),
          PositionedDirectional(
            top: 4, end: 4,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onRemove();
              },
              child: Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 12),
              ),
            ),
          ),
          PositionedDirectional(
            bottom: 4, start: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                '${widget.index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
