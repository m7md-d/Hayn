import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/batch/batch_savings_estimator.dart';
import '../../../core/capabilities/format_capabilities.dart';
import '../../../shared/widgets/widgets.dart';
import '../../library/presentation/providers/library_provider.dart';
import '../../settings/providers/preferences_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SurgicalBatchScreen — batch entry point for the Surgical Replace flow.
// Displays the assets that will be processed, the projected total savings,
// the same Auto/Advanced settings card used by the single-item arena, and a
// single confirm button that enqueues the whole queue.
//
//   ┌── Stats card (sum) ──────────────────────────────────┐
//   │   12 items · ≈ 1.2 GB → 320 MB · −73%                 │
//   └──────────────────────────────────────────────────────┘
//   ┌── Grid preview (3 cols) ─────────────────────────────┐
//   │   [thumb] [thumb] [thumb]                             │
//   │   [thumb] [thumb] [thumb]                             │
//   │   ...                                                 │
//   └──────────────────────────────────────────────────────┘
//   ┌── Auto/Advanced toggle + settings card ─────────────┐
//   │   ...                                                 │
//   └──────────────────────────────────────────────────────┘
//   [Replace all]
//   Reversible from trash for N days
// ─────────────────────────────────────────────────────────────────────────────

enum _BatchMode { auto, advanced }

class SurgicalBatchScreen extends ConsumerStatefulWidget {
  const SurgicalBatchScreen({required this.assetIds, super.key});
  final List<String> assetIds;

  @override
  ConsumerState<SurgicalBatchScreen> createState() =>
      _SurgicalBatchScreenState();
}

class _SurgicalBatchScreenState
    extends ConsumerState<SurgicalBatchScreen> {
  _BatchMode _mode = _BatchMode.auto;
  DefaultFormat _format = DefaultFormat.auto;
  double _quality = 80;
  bool _keepMetadata = true;
  bool _keepTrashBackup = true;

  late final List<AssetEntity> _assets;
  Future<BatchSavingsEstimate>? _future;
  int? _lastKey;

  @override
  void initState() {
    super.initState();
    final all = ref.read(libraryProvider).assets;
    _assets = all
        .where((a) => widget.assetIds.contains(a.id))
        .toList(growable: false);
  }

  void _refreshEstimate(DefaultFormat effective) {
    final key = Object.hash(_mode, _quality.round(), effective);
    if (key == _lastKey) return;
    _lastKey = key;
    _future = BatchSavingsEstimator.estimate(
      assets: _assets,
      format: effective,
      quality: _mode == _BatchMode.auto ? 80 : _quality.round(),
    );
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
    final caps = ref.watch(formatCapabilitiesProvider);
    final effective = _format == DefaultFormat.auto
        ? DefaultFormat.resolveAuto(caps)
        : _format;
    _refreshEstimate(effective);

    return HaynScaffold(
      appBar: HaynModalAppBar(title: l.toolSurgicalReplace),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.s2, AppSpacing.md, 120,
        ),
        children: [
          // ── Mode toggle ────────────────────────────────────────────────
          HaynSegmentedPill<_BatchMode>(
            value: _mode,
            onChanged: (m) => setState(() => _mode = m),
            items: [
              HaynSegmentItem(
                  value: _BatchMode.auto, label: l.surgicalModeAuto),
              HaynSegmentItem(
                  value: _BatchMode.advanced, label: l.surgicalModeAdvanced),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Aggregate stats card ───────────────────────────────────────
          FutureBuilder<BatchSavingsEstimate>(
            future: _future,
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: hc.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: hc.border),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: hc.text3),
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      Text(l.tasksFilterRunning,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: hc.text2)),
                    ],
                  ),
                );
              }
              return _BatchStatsCard(estimate: snap.data!);
            },
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Asset thumbnails grid ─────────────────────────────────────
          Text(
            l.librarySelectedCount(_assets.length),
            style: theme.textTheme.labelMedium?.copyWith(
              color: hc.text2,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          _AssetGrid(assets: _assets),
          const SizedBox(height: AppSpacing.md),

          // ── Mode-dependent settings ───────────────────────────────────
          AnimatedSwitcher(
            duration: AppDuration.normal,
            child: _mode == _BatchMode.auto
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
          const SizedBox(height: AppSpacing.lg),

          // ── Confirm ───────────────────────────────────────────────────
          HaynDestructiveButton(
            label: '${l.surgicalConfirm} (${_assets.length})',
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
}

// ─────────────────────────────────────────────────────────────────────────────
// _BatchStatsCard — large readout: total saved size + percent + asset count.
// ─────────────────────────────────────────────────────────────────────────────

class _BatchStatsCard extends StatelessWidget {
  const _BatchStatsCard({required this.estimate});
  final BatchSavingsEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: hc.successSoft,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          estimate.isApproximation ? '≈ ' : '',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: hc.text2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _format(estimate.totalOriginalBytes),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: hc.text3,
                            decoration: TextDecoration.lineThrough,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        Icon(Icons.east_rounded, size: 16, color: hc.text3),
                        const SizedBox(width: AppSpacing.s2),
                        Text(
                          _format(estimate.estimatedNewBytes),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: hc.successColor,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    if (estimate.isApproximation) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Estimate from a sample of files',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: hc.text3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s3, vertical: 6),
                decoration: BoxDecoration(
                  color: hc.successColor,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  '−${estimate.savedPercent}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _format(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AssetGrid — compact thumbnails arranged in a 4-column grid. The grid is
// wrapped in a Container so the user can scroll past it once it gets large.
// ─────────────────────────────────────────────────────────────────────────────

class _AssetGrid extends StatelessWidget {
  const _AssetGrid({required this.assets});
  final List<AssetEntity> assets;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: AppSpacing.s2,
        mainAxisSpacing: AppSpacing.s2,
      ),
      itemCount: assets.length,
      itemBuilder: (ctx, i) => _AssetTile(asset: assets[i]),
    );
  }
}

class _AssetTile extends StatefulWidget {
  const _AssetTile({required this.asset});
  final AssetEntity asset;

  @override
  State<_AssetTile> createState() => _AssetTileState();
}

class _AssetTileState extends State<_AssetTile> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await widget.asset
        .thumbnailDataWithSize(const ThumbnailSize.square(160));
    if (mounted) setState(() => _bytes = data);
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        color: hc.surfaceSunken,
        child: _bytes == null
            ? const SizedBox.expand()
            : Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}
