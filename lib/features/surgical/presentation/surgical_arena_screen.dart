import 'dart:io' show Platform;
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
import 'widgets/preserved_metadata_card.dart';
import 'widgets/surgical_stats_row.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SurgicalArenaScreen — the most consequential screen in the app.
//
//   ┌────────────────────────────────────────────────────────┐
//   │ [Cancel]      Surgical replace               [(i)]    │
//   ├────────────────────────────────────────────────────────┤
//   │   ┌─ Auto / Advanced ──┐                              │
//   │   └────────────────────┘                              │
//   │                                                        │
//   │   ┌─────────────────────────────────────────────────┐ │
//   │   │   Comparison viewer (zoomable)                  │ │
//   │   │   pinch + pan; drag handle splits before/after  │ │
//   │   └─────────────────────────────────────────────────┘ │
//   │                                                        │
//   │   Auto banner OR advanced settings card                │
//   │                                                        │
//   │   Saved % + size                                       │
//   │   Preserved metadata                                   │
//   │   (iOS-only path hint)                                 │
//   │                                                        │
//   │   [Confirm replace]                                    │
//   │   Reversible from trash for N days                     │
//   └────────────────────────────────────────────────────────┘
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
  Uint8List? _previewBytes;

  _ArenaMode _mode = _ArenaMode.auto;
  DefaultFormat _format = DefaultFormat.auto;
  double _quality = 80;
  bool _keepMetadata = true;
  bool _keepTrashBackup = true;

  /// True while the comparison viewer has 2+ fingers (or scale > 1). The
  /// list freezes its physics so a pinch on the preview never accidentally
  /// scrolls the page.
  bool _viewerZoomLocked = false;

  @override
  void initState() {
    super.initState();
    final all = ref.read(libraryProvider).assets;
    _asset = all.firstWhere(
      (a) => a.id == widget.assetId,
      orElse: () => all.first,
    );
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final data = await _asset!.thumbnailDataWithSize(
      const ThumbnailSize.square(1080),
    );
    if (mounted) setState(() => _previewBytes = data);
  }

  Future<void> _confirm() async {
    final l = AppLocalizations.of(context);
    final ok = await showHaynDestructiveConfirm(
      context: context,
      title: l.surgicalConfirmTitle,
      message: l.surgicalConfirmMessage,
      confirmLabel: l.surgicalConfirm,
      cancelLabel: l.commonCancel,
      icon: Icons.healing_rounded,
      reassurance: l.surgicalReversible(ref.read(trashRetentionProvider)),
    );
    if (!ok || !mounted) return;
    HapticFeedback.mediumImpact();
    HaynSnack.success(context, l.surgicalCompleted);
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

    // Placeholder estimate while the real encoder is offline.
    final caps = ref.watch(formatCapabilitiesProvider);
    final effectiveFormat = _format == DefaultFormat.auto
        ? DefaultFormat.resolveAuto(caps)
        : _format;
    final originalBytes = (asset.width * asset.height * 0.6).round();
    final newBytes = (originalBytes *
            _estimateRatio(_mode, _quality.round(), effectiveFormat))
        .round();
    final savedPercent = (((originalBytes - newBytes) / originalBytes) * 100)
        .round();

    return HaynScaffold(
      appBar: HaynModalAppBar(title: l.toolSurgicalReplace),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.s2, AppSpacing.md, 120,
        ),
        physics: _viewerZoomLocked
            ? const NeverScrollableScrollPhysics()
            : null,
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

          // ── Comparison viewer ──────────────────────────────────────────
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
                    before: Image.memory(
                      _previewBytes!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                    after: Image.memory(
                      _previewBytes!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
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
                    onFormatChanged: (v) => setState(() => _format = v),
                    onQualityChanged: (v) => setState(() => _quality = v),
                    onKeepMetaChanged: (v) =>
                        setState(() => _keepMetadata = v),
                    onKeepTrashChanged: (v) =>
                        setState(() => _keepTrashBackup = v),
                  ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Stats ──────────────────────────────────────────────────────
          SurgicalStatsRow(
            savedPercent: savedPercent,
            originalBytes: originalBytes,
            newBytes: newBytes,
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Preserved metadata ─────────────────────────────────────────
          PreservedMetadataCard(asset: asset),
          const SizedBox(height: AppSpacing.md),

          if (Platform.isIOS) _IosPathHint(),

          const SizedBox(height: AppSpacing.lg),

          // ── Confirm destructive button ────────────────────────────────
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
        ],
      ),
    );
  }

  /// Same heuristic used by CompressEstimateCard so users see consistent
  /// numbers between Surgical and Compress when they pick the same options.
  double _estimateRatio(_ArenaMode mode, int quality, DefaultFormat format) {
    final formatMul = switch (format) {
      DefaultFormat.avif => 0.32,
      DefaultFormat.heic => 0.50,
      DefaultFormat.webp => 0.60,
      DefaultFormat.jpeg => 0.90,
      DefaultFormat.auto => 0.40,
    };
    final effectiveQuality = mode == _ArenaMode.auto ? 80 : quality;
    final qFactor = 0.7 + ((effectiveQuality - 30) / 70) * 0.7;
    return (formatMul * qFactor).clamp(0.05, 0.95);
  }
}

class _IosPathHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: hc.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s2, vertical: 3),
            decoration: BoxDecoration(
              color: hc.accent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              l.surgicalIosBadge,
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
              l.surgicalIosHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: hc.accent,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
