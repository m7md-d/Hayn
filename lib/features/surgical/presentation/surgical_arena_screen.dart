import 'dart:async';
import 'dart:io' show Platform;
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
import '../../../shared/widgets/widgets.dart';
import '../../image_ops/data/image_encoder.dart';
import '../../image_ops/data/image_probe.dart';
import '../../image_ops/domain/image_format_policy.dart';
import '../../library/presentation/providers/asset_entity_cache.dart';
import '../../settings/providers/preferences_providers.dart';
import 'widgets/preserved_metadata_card.dart';
import 'widgets/surgical_stats_row.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SurgicalArenaScreen — the most consequential screen in the app.
//
//   ┌────────────────────────────────────────────────────────┐
//   │ [Cancel]      Surgical replace               [(i)]    │
//   ├────────────────────────────────────────────────────────┤
//   │   [Auto / Advanced]                                    │
//   │   ┌─ Comparison viewer (zoomable) ──────────────────┐  │
//   │   │  REAL original ↔ REAL compressed preview        │  │
//   │   └─────────────────────────────────────────────────┘  │
//   │   Auto banner OR advanced settings                     │
//   │   Saved % + size (real)                                │
//   │   Preserved metadata                                   │
//   │   Platform hint (Android: stays in place / iOS: path B)│
//   │   [Confirm replace]                                    │
//   └────────────────────────────────────────────────────────┘
//
// Stage 1 shows the TRUE compressed result (same encoder the replace will use)
// so the user can verify quality + size + metadata before any destructive op.
// The replace engine itself is wired in the next stage; here Confirm is an
// honest preview-only notice (never a fake "done").
// ─────────────────────────────────────────────────────────────────────────────

enum _ArenaMode { auto, advanced }

class SurgicalArenaScreen extends ConsumerStatefulWidget {
  const SurgicalArenaScreen({required this.assetId, super.key});
  final String assetId;

  @override
  ConsumerState<SurgicalArenaScreen> createState() =>
      _SurgicalArenaScreenState();
}

class _SurgicalArenaScreenState extends ConsumerState<SurgicalArenaScreen> {
  AssetEntity? _asset;
  Uint8List? _previewBytes; // quick thumbnail placeholder
  Uint8List? _originBytes; // full-res original (before pane + encode source)
  int _beforeSize = 0;
  bool _hasAlpha = false;

  _ArenaMode _mode = _ArenaMode.auto;
  DefaultFormat _format = DefaultFormat.auto;
  double _quality = 80;
  bool _keepMetadata = true;
  bool _keepTrashBackup = true;

  // ── Real encode of the result (the truth the user confirms against) ────────
  EncodedImage? _encoded;
  bool _encoding = false;
  int _encodeSeq = 0;
  Timer? _debounce;

  /// True while the comparison viewer has 2+ fingers (or scale > 1). The
  /// list freezes its physics so a pinch on the preview never accidentally
  /// scrolls the page.
  bool _viewerZoomLocked = false;

  @override
  void initState() {
    super.initState();
    // Seed from the user's saved defaults (same as Compress) so numbers agree.
    _format = ref.read(defaultFormatProvider);
    _quality = qualityIntFor(ref.read(defaultQualityProvider)).toDouble();
    _mode = _ArenaMode.auto;

    final cached = AssetEntityCache.get(widget.assetId);
    _asset = cached;
    if (cached == null) {
      AssetEntityCache.load(widget.assetId).then((a) {
        if (!mounted || a == null) return;
        setState(() => _asset = a);
        _loadSource();
      });
    } else {
      _loadSource();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Load the thumbnail (instant placeholder), then the full-res original +
  /// alpha probe, then kick the real encode for the preview.
  Future<void> _loadSource() async {
    final asset = _asset!;
    final thumb =
        await asset.thumbnailDataWithSize(const ThumbnailSize.square(1080));
    if (mounted) setState(() => _previewBytes = thumb);
    final origin = await asset.originBytes;
    if (!mounted) return;
    final alpha = origin == null ? false : await ImageProbe.hasAlpha(origin);
    if (!mounted) return;
    setState(() {
      _originBytes = origin;
      _beforeSize = origin?.length ?? 0;
      _hasAlpha = alpha;
    });
    _scheduleEncode();
  }

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
    try {
      final result = await ImageEncoder.encode(
        source: src,
        target: target.format,
        quality: q,
        hasAlpha: _hasAlpha,
        keepMetadata: _keepMetadata,
        // Surgical replace keeps the original capture time — that's the whole
        // point of preserving the library's order.
        keepOriginalTime: true,
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

  void _onSettingsChanged() {
    _scheduleEncode();
  }

  void _confirm() {
    // Stage 1: the destructive engine lands next. Be honest — never a fake
    // "done". The preview above is the REAL compressed result.
    HapticFeedback.selectionClick();
    HaynSnack.info(context, AppLocalizations.of(context).surgicalPreviewOnly);
  }

  Widget _afterWidget() {
    final enc = _encoded;
    final hc = context.hc;
    final l = AppLocalizations.of(context);
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
    return Image.memory(
      enc.bytes,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _previewBytes != null
          ? Image.memory(_previewBytes!, fit: BoxFit.contain)
          : const SizedBox.shrink(),
    );
  }

  Widget _beforeWidget() {
    final origin = _originBytes;
    if (origin != null) {
      return Image.memory(
        origin,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _previewBytes != null
            ? Image.memory(_previewBytes!, fit: BoxFit.contain)
            : const SizedBox.shrink(),
      );
    }
    if (_previewBytes != null) {
      return Image.memory(_previewBytes!,
          fit: BoxFit.contain, gaplessPlayback: true);
    }
    return const SizedBox.shrink();
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

    final caps = ref.watch(formatCapabilitiesProvider);

    // Real numbers from the actual encode (no heuristic).
    final ready = _encoded != null && !_encoding && _beforeSize > 0;
    final newBytes = _encoded?.bytes.length ?? 0;
    final savedPercent = (ready && newBytes > 0)
        ? (((_beforeSize - newBytes) / _beforeSize) * 100).round()
        : 0;

    return HaynScaffold(
      appBar: HaynModalAppBar(title: l.toolSurgicalReplace),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.s2, AppSpacing.md, 120,
        ),
        physics:
            _viewerZoomLocked ? const NeverScrollableScrollPhysics() : null,
        children: [
          // ── Mode toggle ────────────────────────────────────────────────
          HaynSegmentedPill<_ArenaMode>(
            value: _mode,
            onChanged: (m) => setState(() => _mode = m),
            items: [
              HaynSegmentItem(value: _ArenaMode.auto, label: l.surgicalModeAuto),
              HaynSegmentItem(
                  value: _ArenaMode.advanced, label: l.surgicalModeAdvanced),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Comparison viewer (real original ↔ real compressed) ────────
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
                    beforeLabel: l.surgicalBefore,
                    afterLabel: l.surgicalAfter,
                    onZoomStateChanged: (locked) =>
                        setState(() => _viewerZoomLocked = locked),
                    before: _beforeWidget(),
                    after: _afterWidget(),
                  ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Mode-dependent card (auto banner / advanced settings) ──────
          AnimatedSwitcher(
            duration: AppDuration.normal,
            switchInCurve: AppCurves.decelerate,
            transitionBuilder: fadeScaleTransition,
            child: _mode == _ArenaMode.auto
                ? HaynInlineBanner(
                    key: const ValueKey('auto'),
                    tone: HaynBannerTone.info,
                    icon: Icons.auto_awesome_rounded,
                    message: l.surgicalSettingsAuto,
                  )
                : HaynAdvancedSettingsCard(
                    key: const ValueKey('advanced'),
                    format: _format,
                    quality: _quality,
                    keepMetadata: _keepMetadata,
                    keepTrashBackup: _keepTrashBackup,
                    onFormatChanged: (v) {
                      setState(() => _format = v);
                      _onSettingsChanged();
                    },
                    onQualityChanged: (v) {
                      setState(() => _quality = v);
                      _onSettingsChanged();
                    },
                    onKeepMetaChanged: (v) {
                      setState(() => _keepMetadata = v);
                      _onSettingsChanged();
                    },
                    onKeepTrashChanged: (v) =>
                        setState(() => _keepTrashBackup = v),
                  ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Stats (real once encoded) ──────────────────────────────────
          if (ready)
            SurgicalStatsRow(
              savedPercent: savedPercent,
              originalBytes: _beforeSize,
              newBytes: newBytes,
            )
          else
            _StatsLoading(label: l.compressComputing),
          const SizedBox(height: AppSpacing.md),

          // ── Preserved metadata ─────────────────────────────────────────
          PreservedMetadataCard(asset: asset, inPlace: Platform.isAndroid),
          const SizedBox(height: AppSpacing.md),

          // ── Platform path hint ─────────────────────────────────────────
          if (Platform.isAndroid)
            _PathHint(
              badge: l.surgicalAndroidBadge,
              hint: l.surgicalAndroidHint,
              positive: true,
            )
          else if (Platform.isIOS)
            _PathHint(
              badge: l.surgicalIosBadge,
              hint: l.surgicalIosHint,
              positive: false,
            ),

          const SizedBox(height: AppSpacing.lg),

          // ── Confirm (Stage 1: honest preview-only notice) ──────────────
          HaynDestructiveButton(
            label: l.surgicalConfirm,
            icon: Icons.healing_rounded,
            onPressed: _confirm,
            size: HaynButtonSize.large,
          ),
          const SizedBox(height: AppSpacing.s3),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restore_rounded, size: 12, color: hc.text3),
              const SizedBox(width: 4),
              Text(
                l.surgicalReversible(ref.read(trashRetentionProvider)),
                style: theme.textTheme.labelSmall?.copyWith(color: hc.text3),
              ),
            ],
          ),
          // Auto resolves to this codec for the user's device (info only).
          const SizedBox(height: AppSpacing.s2),
          if (_mode == _ArenaMode.auto)
            Center(
              child: Text(
                DefaultFormat.labelFor(
                  _format == DefaultFormat.auto
                      ? DefaultFormat.resolveAuto(caps)
                      : _format,
                  supportsHeic: caps.supportsHeic,
                  supportsHeif: caps.supportsHeif,
                ),
                style: theme.textTheme.labelSmall?.copyWith(color: hc.text3),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatsLoading extends StatelessWidget {
  const _StatsLoading({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: hc.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: hc.text3),
          ),
          const SizedBox(width: AppSpacing.s3),
          Text(label,
              style: theme.textTheme.bodyMedium?.copyWith(color: hc.text2)),
        ],
      ),
    );
  }
}

class _PathHint extends StatelessWidget {
  const _PathHint({
    required this.badge,
    required this.hint,
    required this.positive,
  });
  final String badge;
  final String hint;

  /// true = reassuring (Android, everything preserved); false = caveat (iOS).
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final bg = positive ? hc.successSoft : hc.accentSoft;
    final fg = positive ? hc.successColor : hc.accent;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s2, vertical: 3),
            decoration: BoxDecoration(
              color: fg,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: fg,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
