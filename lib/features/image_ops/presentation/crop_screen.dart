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
import '../data/image_crop_task.dart';
import 'widgets/aspect_ratio_chips.dart';
import 'widgets/crop_canvas.dart';
import 'widgets/rotate_flip_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CropScreen — single-image crop + rotate + flip editor.
//
//   ┌────────────────────────────────────────────────────────┐
//   │ [Cancel]    Crop                              [Done]   │
//   ├────────────────────────────────────────────────────────┤
//   │                                                        │
//   │                                                        │
//   │              [Image + crop rect overlay]               │
//   │                                                        │
//   │                                                        │
//   ├────────────────────────────────────────────────────────┤
//   │  ⟲   ⟳   ⇋   ⇕   ↺                                    │
//   ├────────────────────────────────────────────────────────┤
//   │  [Free] [Original] [1:1] [4:3] [3:4] [16:9] [9:16]    │
//   └────────────────────────────────────────────────────────┘
// ─────────────────────────────────────────────────────────────────────────────

class CropScreen extends ConsumerStatefulWidget {
  const CropScreen({required this.assetId, super.key});
  final String assetId;

  @override
  ConsumerState<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends ConsumerState<CropScreen> {
  AssetEntity? _asset;
  Uint8List? _bytes;

  int _rotation = 0;
  bool _flipH = false;
  bool _flipV = false;
  CropAspectRatio _ratio = CropAspectRatio.free;
  Rect _cropFraction = const Rect.fromLTRB(0, 0, 1, 1);

  @override
  void initState() {
    super.initState();
    final cached = AssetEntityCache.get(widget.assetId);
    _asset = cached;
    if (cached == null) {
      AssetEntityCache.load(widget.assetId).then((a) {
        if (!mounted || a == null) return;
        setState(() => _asset = a);
        _load();
      });
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final a = _asset;
    if (a == null) return;
    // 2048-px preview is plenty for an editor without ballooning memory.
    final data = await a.thumbnailDataWithSize(
      const ThumbnailSize.square(2048),
    );
    if (mounted) setState(() => _bytes = data);
  }

  void _rotateCw() {
    HapticFeedback.selectionClick();
    setState(() => _rotation = (_rotation + 1) % 4);
  }

  void _rotateCcw() {
    HapticFeedback.selectionClick();
    setState(() => _rotation = (_rotation + 3) % 4);
  }

  void _toggleFlipH() {
    HapticFeedback.selectionClick();
    setState(() => _flipH = !_flipH);
  }

  void _toggleFlipV() {
    HapticFeedback.selectionClick();
    setState(() => _flipV = !_flipV);
  }

  void _reset() {
    HapticFeedback.lightImpact();
    setState(() {
      _rotation = 0;
      _flipH = false;
      _flipV = false;
      _ratio = CropAspectRatio.free;
      _cropFraction = const Rect.fromLTRB(0, 0, 1, 1);
    });
  }

  void _apply() {
    HapticFeedback.lightImpact();
    final l = AppLocalizations.of(context);
    final id = _asset?.id ?? widget.assetId;
    unawaited(
      ref.read(taskRunnerProvider.notifier).enqueue(
            ImageCropTask(
              assetId: id,
              rotationQuarters: _rotation,
              flipH: _flipH,
              flipV: _flipV,
              cropFraction: _cropFraction,
            ),
          ),
    );
    HaynSnack.success(context, l.cropApplied);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final asset = _asset;
    final bytes = _bytes;

    return HaynScaffold(
      appBar: HaynModalAppBar(
        title: l.toolCrop,
        onDone: _apply,
        doneLabel: l.commonDone,
      ),
      body: Column(
        children: [
          // ── Canvas ───────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: (asset == null || bytes == null)
                  ? Container(
                      decoration: BoxDecoration(
                        color: hc.surfaceSunken,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: Container(
                        color: hc.surfaceSunken,
                        child: CropCanvas(
                          imageBytes: bytes,
                          imageWidth: asset.width,
                          imageHeight: asset.height,
                          rotationQuarters: _rotation,
                          flipH: _flipH,
                          flipV: _flipV,
                          aspectRatio: aspectRatioValue(
                            _ratio,
                            imageWidth: asset.width,
                            imageHeight: asset.height,
                            rotationQuarters: _rotation,
                          ),
                          onChange: (r) => _cropFraction = r,
                        ),
                      ),
                    ),
            ),
          ),

          // ── Crop output dimensions readout ───────────────────────────
          if (asset != null && bytes != null)
            _DimensionsReadout(
              asset: asset,
              cropFraction: _cropFraction,
              rotation: _rotation,
            ),

          // ── Rotate/Flip bar ─────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: hc.surface,
              border: Border(
                top: BorderSide(color: hc.border, width: AppHairline.thickness),
              ),
            ),
            child: RotateFlipBar(
              onRotateCcw: _rotateCcw,
              onRotateCw: _rotateCw,
              onFlipH: _toggleFlipH,
              onFlipV: _toggleFlipV,
              onReset: _reset,
            ),
          ),

          // ── Aspect ratio strip ──────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: hc.surface,
              border: Border(
                top: BorderSide(color: hc.border, width: AppHairline.thickness),
              ),
            ),
            child: SafeArea(
              top: false,
              child: AspectRatioChips(
                value: _ratio,
                onChanged: (v) => setState(() => _ratio = v),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DimensionsReadout — small chip above the toolbar that surfaces the output
// dimensions in pixels. Helps the user understand whether their crop will
// still produce a usable resolution.
// ─────────────────────────────────────────────────────────────────────────────

class _DimensionsReadout extends StatelessWidget {
  const _DimensionsReadout({
    required this.asset,
    required this.cropFraction,
    required this.rotation,
  });

  final AssetEntity asset;
  final Rect cropFraction;
  final int rotation;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final rotated = rotation.isOdd;
    final iw = (rotated ? asset.height : asset.width).toDouble();
    final ih = (rotated ? asset.width : asset.height).toDouble();
    final outW = (iw * cropFraction.width).round();
    final outH = (ih * cropFraction.height).round();
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.s2),
      child: Align(
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s3, vertical: 4),
          decoration: BoxDecoration(
            color: hc.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            '$outW × $outH',
            style: theme.textTheme.labelSmall?.copyWith(
              color: hc.text2,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
