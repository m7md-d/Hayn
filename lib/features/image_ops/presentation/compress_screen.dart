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
import '../data/compress_estimate_controller.dart';
import '../data/image_compress_task.dart';
import '../data/image_encoder.dart';
import '../data/image_probe.dart';
import '../data/native_image_info.dart';
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
  // Off by default: the copy gets the current time so it lands at the top of
  // the timeline. The user opts in to keep the original capture date.
  bool _keepOriginalTime = false;

  // Work from ids only — `select all` can hand us thousands. The active
  // preview + estimate are resolved lazily by id; we never build an
  // AssetEntity list.
  List<String> get _ids => widget.assetIds;
  bool get _isSingle => _ids.length == 1;
  Uint8List? _previewBytes;
  int _activeAssetIndex = 0;

  /// Summed original byte size of the WHOLE selection, from the index.
  int _originalBytes = 0;

  // ── Multi-image live size estimate ─────────────────────────────────────
  EstimateResult? _estimate;
  Timer? _estimateDebounce;

  // ── Single-image real encode ──────────────────────────────────────────
  // For ONE image we don't guess: load the original, probe alpha, and run the
  // ACTUAL encoder (debounced), so the before/after preview + size are the
  // truth. Skipped for multi-select (that would mean loading every original —
  // which is exactly what the index-based estimate avoids).
  Uint8List? _originBytes;
  int _beforeSize = 0;
  int _activeW = 0; // source dimensions (for the huge-image encode cap)
  int _activeH = 0;
  bool _hasAlpha = false;
  NativeImageInfo? _info; // real bit depth / alpha / HDR of the source
  int _bitDepth = 0; // target: 0 = match source (preserves HDR), 8 = SDR
  EncodedImage? _encoded;
  // Settings signature the live `_encoded` was produced with. The save reuses
  // those bytes only when this still matches the current settings, so it can
  // never write a stale encode (e.g. after the user nudged a slider).
  String? _encodedSig;
  double _encodeMs = 0; // active image's real encode time (anchors the ETA)
  bool _encoding = false;
  int _encodeSeq = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Seed from the user's saved defaults so this screen AGREES with the
    // selection chip (which projects savings from the same defaults) AND so Auto
    // mode actually USES those defaults — quality included — instead of a
    // hard-coded format=auto/q80.
    _format = ref.read(defaultFormatProvider);
    _quality = qualityIntFor(ref.read(defaultQualityProvider)).toDouble();
    // Always open in Auto — it simply honours the saved defaults (format +
    // quality). We never force the user into Advanced; that's opt-in for tweaks.
    _mode = _Mode.auto;
    _loadActive();
    if (!_isSingle) _loadOriginalBytes();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _estimateDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadOriginalBytes() async {
    // Real sizes from the index span the whole selection (no asset.file).
    final facts = await ref.read(mediaIndexDatabaseProvider).factsFor(_ids);
    final sum = facts.fold<int>(0, (s, f) => s + f.sizeBytes);
    if (mounted) setState(() => _originalBytes = sum);
    _scheduleEstimate(); // instant metadata prior; refines after the encode
  }

  /// Load the ACTIVE image (single, or the one selected in the batch switcher):
  /// origin + thumbnail + alpha/HDR probe, then kick a real encode for the
  /// preview. The encode of this one image doubles as the calibration anchor for
  /// a batch estimate — so we never encode the whole selection (that OOM'd).
  Future<void> _loadActive() async {
    if (_ids.isEmpty) return;
    final id = _ids[_activeAssetIndex];
    final entity = await AssetEntityCache.load(id);
    if (entity == null || !mounted) return;
    final thumb =
        await entity.thumbnailDataWithSize(const ThumbnailSize.square(1080));
    final origin = await entity.originBytes;
    if (!mounted) return;
    final alpha = origin == null ? false : await ImageProbe.hasAlpha(origin);
    final info = origin == null ? null : await NativeImageProbe.probe(origin);
    if (!mounted) return;
    setState(() {
      _previewBytes = thumb;
      _originBytes = origin;
      _beforeSize = origin?.length ?? 0;
      _activeW = entity.width;
      _activeH = entity.height;
      _hasAlpha = alpha;
      _info = info;
    });
    _scheduleEncode();
  }

  /// Debounced real encode of the ACTIVE image — re-runs when format / quality /
  /// metadata change, without thrashing on every slider tick. Runs for both
  /// single and multi (multi uses it as the preview + the estimate anchor).
  void _scheduleEncode() {
    if (_originBytes == null) return;
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
    final q = _quality.round();
    final seq = ++_encodeSeq;
    setState(() => _encoding = true);
    if (!_isSingle) _scheduleEstimate(); // show prior + spinner while encoding
    try {
      final sw = Stopwatch()..start();
      final cap = encodeCapFor(_activeW, _activeH); // huge-image guard
      final result = await ImageEncoder.encode(
        source: src,
        target: target.format,
        quality: q,
        hasAlpha: _hasAlpha,
        keepMetadata: _keepMetadata,
        keepOriginalTime: _keepOriginalTime,
        bitDepth: _bitDepth,
        maxWidth: cap.maxWidth,
        maxHeight: cap.maxHeight,
      );
      sw.stop();
      if (!mounted || seq != _encodeSeq) return;
      setState(() {
        _encoded = result;
        _encodeMs = sw.elapsedMicroseconds / 1000.0;
        _encoding = false;
        _encodedSig = _sig(q, _isSingle ? _bitDepth : 0);
      });
      if (!_isSingle) _runEstimate(); // refine the batch estimate with the anchor
    } catch (_) {
      if (!mounted || seq != _encodeSeq) return;
      setState(() => _encoding = false);
      if (!_isSingle) _runEstimate();
    }
  }

  /// Debounced batch estimate (multi only). Light: metadata prior calibrated by
  /// the active image's real encode (the anchor) — no per-image sampling.
  void _scheduleEstimate() {
    if (_isSingle || _ids.isEmpty) return;
    _estimateDebounce?.cancel();
    _estimateDebounce = Timer(const Duration(milliseconds: 250), _runEstimate);
  }

  Future<void> _runEstimate() async {
    if (_isSingle) return;
    final ctrl = CompressEstimateController(ref);
    final q = _quality.round();
    // Anchor on the active image once its real encode is in.
    final anchored = _encoded != null && !_encoding;
    final res = await ctrl.estimate(
      ids: _ids,
      target: _format,
      quality: q,
      anchorId: anchored ? _ids[_activeAssetIndex] : null,
      anchorRealBytes: anchored ? _encoded!.bytes.length : null,
      anchorMs: anchored ? _encodeMs : null,
    );
    if (!mounted) return;
    setState(() => _estimate = EstimateResult(
          size: res.size,
          refining: _encoding, // still computing the anchor
          etaSeconds: res.etaSeconds,
        ));
  }

  /// The "after" pane: the REAL full-resolution encode (single AND multi now —
  /// multi compresses the active image for the preview). While that encode is in
  /// flight it shows a CLEAR "compressing…" state over the dimmed source, never a
  /// fake desaturated "result", so the user always knows whether it's done.
  Widget _afterWidget() {
    final enc = _encoded;
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    if (_encoding || enc == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_previewBytes != null)
            Opacity(
              opacity: 0.3,
              child: Image.memory(_previewBytes!,
                  fit: BoxFit.contain, gaplessPlayback: true),
            ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: hc.accent),
                ),
                const SizedBox(height: AppSpacing.s3),
                Text(l.compressComputing,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: hc.text2)),
              ],
            ),
          ),
        ],
      );
    }
    if (enc.format == DefaultFormat.avif) {
      return AvifImage.memory(enc.bytes, fit: BoxFit.contain);
    }
    // Full-resolution decode on purpose: the comparison is for zooming in on
    // REAL compression artefacts. Falls back to the thumbnail if a format won't
    // decode in the engine.
    return Image.memory(
      enc.bytes,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          Image.memory(_previewBytes!, fit: BoxFit.contain),
    );
  }

  /// The "before" pane: the FULL-RESOLUTION original (so zooming compares true
  /// quality), with the quick thumbnail as the placeholder until it loads / if a
  /// format can't decode in the engine.
  Widget _beforeWidget() {
    final origin = _originBytes;
    if (origin != null) {
      return Image.memory(
        origin,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        // Bound the decode so a ~200 MP original can't OOM the preview; still
        // far more detail than the on-screen size for zoom-comparison.
        cacheWidth: 4096,
        errorBuilder: (_, __, ___) => _previewBytes != null
            ? Image.memory(_previewBytes!, fit: BoxFit.contain)
            : const SizedBox.shrink(),
      );
    }
    return Image.memory(_previewBytes!, fit: BoxFit.contain, gaplessPlayback: true);
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
      _encoded = null; // the old encode belonged to the previous image
    });
    HapticFeedback.selectionClick();
    _loadActive();
  }

  /// Signature of the settings an encode was produced with — used to decide
  /// whether the cached preview encode is still valid to reuse on save.
  String _sig(int q, int bitDepth) =>
      '${_ids[_activeAssetIndex]}|${_format.name}|$q|$_keepMetadata|$_keepOriginalTime|$bitDepth';

  void _apply() {
    HapticFeedback.lightImpact();
    final l = AppLocalizations.of(context);
    final q = _quality.round();
    final bitDepth = _isSingle ? _bitDepth : 0;
    // Hand the engine the active image's already-finished encode when it still
    // matches the current settings exactly — the task writes those bytes as-is
    // (metadata + time + format already baked in) instead of encoding it again.
    // For a single image that means the save is instant; for a batch it spares
    // the previewed image a second pass. A pending/changed encode → null, so we
    // never save stale bytes.
    final canReuse = !_encoding &&
        _encoded != null &&
        _encodedSig == _sig(q, bitDepth);
    final activeId = _ids[_activeAssetIndex];
    // Enqueue the real engine — it encodes each id + saves a new gallery asset,
    // surfacing in the floating Tasks badge with progress/cancel.
    unawaited(
      ref.read(taskRunnerProvider.notifier).enqueue(
            ImageCompressTask(
              assetIds: _ids,
              format: _format,
              quality: q,
              keepMetadata: _keepMetadata,
              keepOriginalTime: _keepOriginalTime,
              bitDepth: bitDepth,
              precomputedId: canReuse ? activeId : null,
              precomputed: canReuse ? _encoded : null,
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
      // The preview + Auto/Advanced toggle stay FIXED at the top; only the
      // settings/result/button below scroll. So you can zoom-compare and reach
      // the controls independently without the preview scrolling away.
      body: Column(
        children: [
          // ── Fixed: comparison preview ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.s2, AppSpacing.md, 0),
            child: AspectRatio(
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
                      before: _beforeWidget(),
                      after: _afterWidget(),
                    ),
            ),
          ),

          // ── Fixed: asset switcher (only when batch) ───────────────────
          if (isBatch)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.s2, AppSpacing.md, 0),
              child: SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _ids.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.s2),
                  itemBuilder: (ctx, i) => _AssetSwitcherTile(
                    id: _ids[i],
                    selected: i == _activeAssetIndex,
                    onTap: () => _switchActive(i),
                  ),
                ),
              ),
            ),

          // ── Fixed: Auto/Advanced toggle ───────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.s3, AppSpacing.md, AppSpacing.s3),
            child: HaynSegmentedPill<_Mode>(
              value: _mode,
              onChanged: (m) {
                setState(() => _mode = m);
                _scheduleEncode();
                _scheduleEstimate();
              },
              items: [
                HaynSegmentItem(value: _Mode.auto, label: l.compressModeAuto),
                HaynSegmentItem(
                    value: _Mode.advanced, label: l.compressModeAdvanced),
              ],
            ),
          ),

          // ── Scrollable: settings + result + action ────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, 120),
              children: [
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
                    bitDepth: _isSingle ? _bitDepth : null,
                    sourceBitDepth: _info?.bitDepth,
                    onBitDepthChanged: (v) {
                      setState(() => _bitDepth = v);
                      _scheduleEncode();
                    },
                    onFormatChanged: (v) {
                      setState(() => _format = v);
                      _scheduleEncode();
                      _scheduleEstimate();
                    },
                    onQualityChanged: (v) {
                      setState(() => _quality = v);
                      _scheduleEncode();
                      _scheduleEstimate();
                    },
                    onKeepMetaChanged: (v) {
                      setState(() => _keepMetadata = v);
                      _scheduleEncode();
                    },
                    keepOriginalTime: _keepOriginalTime,
                    onKeepOriginalTimeChanged: (v) =>
                        setState(() => _keepOriginalTime = v),
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
              estimate: _estimate,
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
