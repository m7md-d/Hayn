import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_avif/flutter_avif.dart' show AvifImage;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/motion.dart';
import '../../../core/capabilities/format_capabilities.dart';
import '../../../core/isolates/task_runner.dart';
import '../../../data/index/index_providers.dart';
import '../../../shared/widgets/widgets.dart';
import '../../library/presentation/providers/asset_entity_cache.dart';
import '../../library/presentation/widgets/id_thumbnail.dart';
import '../../settings/providers/preferences_providers.dart';
import '../data/image_compress_task.dart';
import '../data/image_encoder.dart';
import '../data/image_probe.dart';
import '../domain/image_format_policy.dart';
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

  // Work from ids only — `select all` can hand us thousands. The active
  // preview + estimate are resolved lazily by id; we never build an
  // AssetEntity list.
  List<String> get _ids => widget.assetIds;
  bool get _isSingle => _ids.length == 1;
  Uint8List? _previewBytes;
  int _activeAssetIndex = 0;

  /// Summed original byte size of the WHOLE selection, from the index
  /// (multi-select heuristic estimate).
  int _originalBytes = 0;

  // ── Single-image real encode ──────────────────────────────────────────
  // For ONE image we don't guess: load the original, probe alpha, and run the
  // ACTUAL encoder (debounced), so the before/after preview + size are the
  // truth. Skipped for multi-select (that would mean loading every original —
  // which is exactly what the index-based estimate avoids).
  Uint8List? _originBytes;
  int _beforeSize = 0;
  bool _hasAlpha = false;
  EncodedImage? _encoded;
  bool _encoding = false;
  int _encodeSeq = 0;
  Timer? _debounce;

  /// Set while the comparison viewer has 2+ fingers or is zoomed in — the
  /// ListView freezes so the pinch isn't stolen as a scroll.
  bool _viewerZoomLocked = false;

  @override
  void initState() {
    super.initState();
    if (_isSingle) {
      _loadSingle();
    } else {
      _loadPreview();
      _loadOriginalBytes();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    if (_ids.isEmpty) return;
    final entity = await AssetEntityCache.load(_ids[_activeAssetIndex]);
    final data = await entity
        ?.thumbnailDataWithSize(const ThumbnailSize.square(1080));
    if (mounted) setState(() => _previewBytes = data);
  }

  Future<void> _loadOriginalBytes() async {
    // Real sizes from the index span the whole selection (no asset.file).
    final facts = await ref.read(mediaIndexDatabaseProvider).factsFor(_ids);
    final sum = facts.fold<int>(0, (s, f) => s + f.sizeBytes);
    if (mounted) setState(() => _originalBytes = sum);
  }

  Future<void> _loadSingle() async {
    final entity = await AssetEntityCache.load(_ids.first);
    if (entity == null || !mounted) return;
    final thumb =
        await entity.thumbnailDataWithSize(const ThumbnailSize.square(1080));
    final origin = await entity.originBytes;
    if (!mounted) return;
    final alpha = origin == null ? false : await ImageProbe.hasAlpha(origin);
    if (!mounted) return;
    setState(() {
      _previewBytes = thumb;
      _originBytes = origin;
      _beforeSize = origin?.length ?? 0;
      _hasAlpha = alpha;
    });
    _scheduleEncode();
  }

  /// Debounced real encode of the single image — re-runs when the format /
  /// quality / metadata choice changes, without thrashing on every slider tick.
  void _scheduleEncode() {
    if (!_isSingle || _originBytes == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runEncode);
  }

  Future<void> _runEncode() async {
    final src = _originBytes;
    if (src == null) return;
    final caps = ref.read(formatCapabilitiesProvider);
    final target = ImageFormatPolicy.resolve(
      choice: _format,
      hasAlpha: _hasAlpha,
      caps: caps,
    );
    final q = _mode == _Mode.auto ? 80 : _quality.round();
    final seq = ++_encodeSeq;
    setState(() => _encoding = true);
    try {
      final result = await ImageEncoder.encode(
        source: src,
        target: target.format,
        quality: q,
        hasAlpha: _hasAlpha,
        keepMetadata: _keepMetadata,
      );
      if (!mounted || seq != _encodeSeq) return;
      setState(() {
        _encoded = result;
        _encoding = false;
      });
    } catch (_) {
      if (!mounted || seq != _encodeSeq) return;
      setState(() => _encoding = false);
    }
  }

  /// The "after" pane: the REAL decoded encode for a single image (AVIF needs
  /// flutter_avif's provider; the rest decode natively), or — for multi-select
  /// / while encoding — the source with a slight desaturation so the panes
  /// still read as before vs after.
  Widget _afterWidget() {
    final enc = _encoded;
    if (_isSingle && enc != null && !_encoding) {
      if (enc.format == DefaultFormat.avif) {
        return AvifImage.memory(enc.bytes, fit: BoxFit.contain);
      }
      return Image.memory(
        enc.bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            Image.memory(_previewBytes!, fit: BoxFit.contain),
      );
    }
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        0.95, 0.0, 0.0, 0.0, 0, //
        0.0, 0.95, 0.0, 0.0, 0, //
        0.0, 0.0, 0.95, 0.0, 0, //
        0.0, 0.0, 0.0, 1.0, 0, //
      ]),
      child: Image.memory(_previewBytes!, fit: BoxFit.contain,
          gaplessPlayback: true),
    );
  }

  /// True when the user forced an opaque format (JPEG) on a transparent image —
  /// the encode will flatten the alpha, so we warn first.
  bool _flattensAlpha(FormatCapabilities caps) =>
      _isSingle &&
      _hasAlpha &&
      ImageFormatPolicy.resolve(
        choice: _format,
        hasAlpha: _hasAlpha,
        caps: caps,
      ).requiresAlphaFlatten;

  void _switchActive(int newIndex) {
    if (newIndex == _activeAssetIndex) return;
    setState(() {
      _activeAssetIndex = newIndex;
      _previewBytes = null;
    });
    HapticFeedback.selectionClick();
    _loadPreview();
  }

  void _apply() {
    HapticFeedback.lightImpact();
    final l = AppLocalizations.of(context);
    final q = _mode == _Mode.auto ? 80 : _quality.round();
    // Enqueue the real engine — it encodes each id + saves a new gallery asset,
    // surfacing in the floating Tasks badge with progress/cancel.
    unawaited(
      ref.read(taskRunnerProvider.notifier).enqueue(
            ImageCompressTask(
              assetIds: _ids,
              format: _format,
              quality: q,
              keepMetadata: _keepMetadata,
            ),
          ),
    );
    HaynSnack.success(context, l.compressQueued(_ids.length));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final theme = Theme.of(context);
    final isBatch = _ids.length > 1;

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
                    after: _afterWidget(),
                  ),
          ),
          const SizedBox(height: AppSpacing.s2),

          // ── Asset switcher (only when batch) ─────────────────────────
          if (isBatch)
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _ids.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s2),
                itemBuilder: (ctx, i) => _AssetSwitcherTile(
                  id: _ids[i],
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
            onChanged: (m) {
              setState(() => _mode = m);
              _scheduleEncode();
            },
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
                    onFormatChanged: (v) {
                      setState(() => _format = v);
                      _scheduleEncode();
                    },
                    onQualityChanged: (v) {
                      setState(() => _quality = v);
                      _scheduleEncode();
                    },
                    onKeepMetaChanged: (v) {
                      setState(() => _keepMetadata = v);
                      _scheduleEncode();
                    },
                  ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Result (single = real) / estimate (multi = heuristic) ──────
          if (_isSingle)
            _RealResultCard(
              encoding: _encoding,
              beforeBytes: _beforeSize,
              encoded: _encoded,
              flattensAlpha: _flattensAlpha(caps),
            )
          else
            CompressEstimateCard(
              originalBytes: _originalBytes,
              quality: _mode == _Mode.auto ? 80 : _quality.round(),
              format: autoFormat,
            ),
          const SizedBox(height: AppSpacing.lg),

          // ── Compress button ────────────────────────────────────────────
          HaynPrimaryButton(
            label: isBatch
                ? '${l.compressTitle} (${_ids.length})'
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

}

// ─────────────────────────────────────────────────────────────────────────────
// _AssetSwitcherTile — small thumbnail used to switch the comparison preview
// to a specific asset in a batch.
// ─────────────────────────────────────────────────────────────────────────────

class _AssetSwitcherTile extends StatelessWidget {
  const _AssetSwitcherTile({
    required this.id,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: hc.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? hc.accent : Colors.transparent,
            width: 2.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: IdThumbnail(id: id, placeholderColor: hc.surfaceSunken),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RealResultCard — the TRUTH for a single image: actual original → actual
// encoded bytes + percent, plus the format actually produced (which may differ
// from the request if a fallback kicked in). No heuristic. Shows a warning tone
// if the chosen format grew the file (e.g. PNG of a photo).
// ─────────────────────────────────────────────────────────────────────────────

class _RealResultCard extends StatelessWidget {
  const _RealResultCard({
    required this.encoding,
    required this.beforeBytes,
    required this.encoded,
    required this.flattensAlpha,
  });

  final bool encoding;
  final int beforeBytes;
  final EncodedImage? encoded;
  final bool flattensAlpha;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    final loading = encoding || encoded == null || beforeBytes == 0;
    final after = encoded?.bytes.length ?? 0;
    final grew = after > beforeBytes && beforeBytes > 0;
    final pct =
        beforeBytes == 0 ? 0 : (((beforeBytes - after).abs() / beforeBytes) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (flattensAlpha) ...[
          HaynInlineBanner(
            tone: HaynBannerTone.warning,
            icon: Icons.warning_amber_rounded,
            message: l.compressAlphaFlattenWarning,
          ),
          const SizedBox(height: AppSpacing.s2),
        ],
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: grew ? hc.surfaceSunken : hc.successSoft,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: loading
              ? Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: hc.text3),
                    ),
                    const SizedBox(width: AppSpacing.s3),
                    Text(l.compressComputing,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: hc.text2)),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              _fmt(beforeBytes),
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: hc.text3,
                                decoration: TextDecoration.lineThrough,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s2),
                          Icon(Icons.east_rounded, size: 16, color: hc.text3),
                          const SizedBox(width: AppSpacing.s2),
                          Flexible(
                            child: Text(
                              _fmt(after),
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: grew ? hc.warningColor : hc.successColor,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    // Actual format produced (surfaces any fallback).
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s2, vertical: 3),
                      decoration: BoxDecoration(
                        color: hc.surface2,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(encoded!.format.techName,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: hc.text2)),
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s2, vertical: 3),
                      decoration: BoxDecoration(
                        color: grew ? hc.warningColor : hc.successColor,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        grew ? '+$pct%' : '−$pct%',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  static String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
