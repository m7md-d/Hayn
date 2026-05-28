import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/motion.dart';
import '../../../core/capabilities/format_capabilities.dart';
import '../../../shared/widgets/widgets.dart';
import '../../library/presentation/providers/library_provider.dart';
import '../../settings/providers/preferences_providers.dart';
import 'widgets/compress_estimate_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CompressScreen — same philosophy as Surgical Arena: comparison preview on
// top, Auto/Advanced toggle below, estimate card, then the primary action.
//
//   [Cancel]   Compress image   [Done]
//   ┌────────────────────────────────────┐
//   │ Comparison viewer (zoomable)       │
//   └────────────────────────────────────┘
//   [Auto | Advanced]
//   auto banner OR advanced settings
//   ┌────────────────────────────────────┐
//   │ Estimated 4.8 MB → 1.2 MB · -75%   │
//   └────────────────────────────────────┘
//   [Compress now]
// ─────────────────────────────────────────────────────────────────────────────

enum _Mode { auto, advanced }

class CompressScreen extends ConsumerStatefulWidget {
  const CompressScreen({required this.assetIds, super.key});
  final List<String> assetIds;

  @override
  ConsumerState<CompressScreen> createState() => _CompressScreenState();
}

class _CompressScreenState extends ConsumerState<CompressScreen> {
  _Mode _mode = _Mode.auto;
  DefaultFormat _format = DefaultFormat.auto;
  double _quality = 80;
  bool _keepMetadata = true;

  late final List<AssetEntity> _assets;
  Uint8List? _previewBytes;
  int _activeAssetIndex = 0;

  /// Set while the comparison viewer has 2+ fingers or is zoomed in — the
  /// ListView freezes so the pinch isn't stolen as a scroll.
  bool _viewerZoomLocked = false;

  @override
  void initState() {
    super.initState();
    final all = ref.read(libraryProvider).assets;
    _assets =
        all.where((a) => widget.assetIds.contains(a.id)).toList(growable: false);
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    if (_assets.isEmpty) return;
    final data = await _assets[_activeAssetIndex]
        .thumbnailDataWithSize(const ThumbnailSize.square(1080));
    if (mounted) setState(() => _previewBytes = data);
  }

  void _switchActive(int newIndex) {
    if (newIndex == _activeAssetIndex) return;
    setState(() {
      _activeAssetIndex = newIndex;
      _previewBytes = null;
    });
    HapticFeedback.selectionClick();
    _loadPreview();
  }

  Future<void> _apply() async {
    HapticFeedback.lightImpact();
    final l = AppLocalizations.of(context);
    HaynSnack.success(context, l.compressQueued(_assets.length));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final theme = Theme.of(context);
    final isBatch = _assets.length > 1;

    final caps = ref.watch(formatCapabilitiesProvider);
    final autoFormat = _format == DefaultFormat.auto
        ? DefaultFormat.resolveAuto(caps)
        : _format;

    return HaynScaffold(
      appBar: HaynModalAppBar(
        title: l.compressTitle,
        onDone: _apply,
        doneLabel: l.commonDone,
      ),
      body: ListView(
        padding: const EdgeInsets.only(
          left: AppSpacing.md, right: AppSpacing.md, top: AppSpacing.s2,
          bottom: 120,
        ),
        physics: _viewerZoomLocked
            ? const NeverScrollableScrollPhysics()
            : null,
        children: [
          // ── Comparison preview ────────────────────────────────────────
          AspectRatio(
            aspectRatio: 4 / 3,
            child: _previewBytes == null
                ? Container(
                    decoration: BoxDecoration(
                      color: hc.surfaceSunken,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  )
                : HaynComparisonViewer(
                    beforeLabel: l.compressOriginalLabel,
                    afterLabel: l.compressPreviewLabel,
                    onZoomStateChanged: (locked) =>
                        setState(() => _viewerZoomLocked = locked),
                    before: Image.memory(
                      _previewBytes!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                    // Until the real encoder runs, the "after" is the same
                    // bytes with a slight saturation drop to read as a
                    // separate state. Once encoding lands, this swaps for
                    // the actual decoded result.
                    after: ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        0.95, 0.0, 0.0, 0.0, 0,
                        0.0, 0.95, 0.0, 0.0, 0,
                        0.0, 0.0, 0.95, 0.0, 0,
                        0.0, 0.0, 0.0, 1.0, 0,
                      ]),
                      child: Image.memory(
                        _previewBytes!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.s2),

          // ── Asset switcher (only when batch) ─────────────────────────
          if (isBatch)
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _assets.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s2),
                itemBuilder: (ctx, i) => _AssetSwitcherTile(
                  asset: _assets[i],
                  selected: i == _activeAssetIndex,
                  onTap: () => _switchActive(i),
                ),
              ),
            ),
          if (isBatch) const SizedBox(height: AppSpacing.md),
          if (!isBatch) const SizedBox(height: AppSpacing.s2),

          // ── Mode segmented ─────────────────────────────────────────────
          HaynSegmentedPill<_Mode>(
            value: _mode,
            onChanged: (m) => setState(() => _mode = m),
            items: [
              HaynSegmentItem(value: _Mode.auto, label: l.compressModeAuto),
              HaynSegmentItem(
                  value: _Mode.advanced, label: l.compressModeAdvanced),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Mode content ───────────────────────────────────────────────
          AnimatedSwitcher(
            duration: AppDuration.normal,
            switchInCurve: AppCurves.decelerate,
            transitionBuilder: fadeScaleTransition,
            child: _mode == _Mode.auto
                ? HaynInlineBanner(
                    key: const ValueKey('auto'),
                    tone: HaynBannerTone.info,
                    icon: Icons.auto_awesome_rounded,
                    message: l.compressAutoChose(
                      DefaultFormat.labelFor(
                        autoFormat,
                        supportsHeic: caps.supportsHeic,
                        supportsHeif: caps.supportsHeif,
                      ),
                    ),
                  )
                : HaynAdvancedSettingsCard(
                    key: const ValueKey('advanced'),
                    format: _format,
                    quality: _quality,
                    keepMetadata: _keepMetadata,
                    onFormatChanged: (v) => setState(() => _format = v),
                    onQualityChanged: (v) => setState(() => _quality = v),
                    onKeepMetaChanged: (v) =>
                        setState(() => _keepMetadata = v),
                  ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Estimate card ──────────────────────────────────────────────
          CompressEstimateCard(
            originalBytes: _estimateOriginalBytes(),
            quality: _mode == _Mode.auto ? 80 : _quality.round(),
            format: autoFormat,
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Compress button ────────────────────────────────────────────
          HaynPrimaryButton(
            label: isBatch
                ? '${l.compressTitle} (${_assets.length})'
                : l.compressTitle,
            icon: Icons.compress_rounded,
            onPressed: _apply,
            size: HaynButtonSize.large,
          ),
          const SizedBox(height: AppSpacing.s3),

          Center(
            child: Row(
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
          ),
        ],
      ),
    );
  }

  int _estimateOriginalBytes() {
    return _assets.fold<int>(
      0,
      (sum, a) => sum + (a.width * a.height * 0.6).round(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AssetSwitcherTile — small thumbnail used to switch the comparison preview
// to a specific asset in a batch.
// ─────────────────────────────────────────────────────────────────────────────

class _AssetSwitcherTile extends StatefulWidget {
  const _AssetSwitcherTile({
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  final AssetEntity asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AssetSwitcherTile> createState() => _AssetSwitcherTileState();
}

class _AssetSwitcherTileState extends State<_AssetSwitcherTile> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await widget.asset
        .thumbnailDataWithSize(const ThumbnailSize.square(160));
    if (mounted) setState(() => _thumb = data);
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: hc.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: widget.selected ? hc.accent : Colors.transparent,
            width: 2.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: _thumb == null
            ? Container(color: hc.surfaceSunken)
            : Image.memory(_thumb!, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}
