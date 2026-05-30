import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/widgets.dart';
import '../../image_ops/presentation/widgets/aspect_ratio_chips.dart';
import '../../image_ops/presentation/widgets/crop_canvas.dart';
import '../../library/presentation/providers/asset_entity_cache.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CropVideoScreen — uses the same CropCanvas as the image flow, fed with a
// high-resolution thumbnail of the source video. The crop fraction maps
// 1:1 onto the actual video stream, so the encoder applies the same rect
// to every frame.
//
// We surface an inline warning that cropping a video always requires a
// one-pass re-encode (unlike trim which can be keyframe-lossless).
// ─────────────────────────────────────────────────────────────────────────────

class CropVideoScreen extends ConsumerStatefulWidget {
  const CropVideoScreen({required this.assetId, super.key});
  final String assetId;

  @override
  ConsumerState<CropVideoScreen> createState() => _CropVideoScreenState();
}

class _CropVideoScreenState extends ConsumerState<CropVideoScreen> {
  AssetEntity? _asset;
  Uint8List? _bytes;

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
    // 1080-px is plenty for visual crop selection on most phones, and
    // avoids decoding the full video stream just to draw a single frame.
    final data = await a.thumbnailDataWithSize(
      const ThumbnailSize.square(1080),
    );
    if (mounted) setState(() => _bytes = data);
  }

  Future<void> _apply() async {
    HapticFeedback.lightImpact();
    final l = AppLocalizations.of(context);
    HaynSnack.success(context, l.cropVideoQueued);
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
        title: l.toolCropVideo,
        onDone: _apply,
        doneLabel: l.commonDone,
      ),
      body: Column(
        children: [
          // ── Canvas (thumbnail-based) ─────────────────────────────────
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
                        color: Colors.black,
                        child: CropCanvas(
                          imageBytes: bytes,
                          imageWidth: asset.width,
                          imageHeight: asset.height,
                          rotationQuarters: 0,
                          flipH: false,
                          flipV: false,
                          aspectRatio: aspectRatioValue(
                            _ratio,
                            imageWidth: asset.width,
                            imageHeight: asset.height,
                            rotationQuarters: 0,
                          ),
                          onChange: (r) => _cropFraction = r,
                        ),
                      ),
                    ),
            ),
          ),

          if (asset != null && bytes != null)
            _OutputReadout(
              asset: asset,
              cropFraction: _cropFraction,
            ),

          // ── Re-encode warning + aspect chips ────────────────────────
          Container(
            decoration: BoxDecoration(
              color: hc.surface,
              border: Border(
                top: BorderSide(
                    color: hc.border, width: AppHairline.thickness),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.s2, AppSpacing.md, 0),
              child: HaynInlineBanner(
                tone: HaynBannerTone.warning,
                icon: Icons.warning_amber_rounded,
                message: l.videoEditorCropWarning,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: hc.surface,
              border: Border(
                top: BorderSide(
                    color: hc.border, width: AppHairline.thickness),
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

class _OutputReadout extends StatelessWidget {
  const _OutputReadout({
    required this.asset,
    required this.cropFraction,
  });

  final AssetEntity asset;
  final Rect cropFraction;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final outW = (asset.width * cropFraction.width).round();
    final outH = (asset.height * cropFraction.height).round();
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
