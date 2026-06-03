import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/widgets.dart';
import '../../settings/providers/preferences_providers.dart';
import '../providers/trash_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TrashScreen — restorable originals. Expire after the configured retention
// window. Each row shows a real thumbnail + specs (dimensions · size · format)
// from the byte-for-byte backup, and tapping opens a zoomable preview.
// ─────────────────────────────────────────────────────────────────────────────

class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final theme = Theme.of(context);
    final items = ref.watch(trashProvider);
    final retention = ref.watch(trashRetentionProvider);

    return HaynScaffold(
      appBar: HaynDetailAppBar(
        title: l.trashTitle,
        actions: items.isEmpty
            ? null
            : [
                TextButton(
                  onPressed: () => _emptyAll(context, ref, l),
                  child: Text(
                    l.trashEmptyAction,
                    style: TextStyle(color: hc.dangerColor),
                  ),
                ),
              ],
      ),
      body: items.isEmpty
          ? HaynEmptyState(
              icon: Icons.delete_outline_rounded,
              title: l.trashEmptyStateTitle,
              message: l.trashEmptyStateMessage(retention),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length + 1,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.s3),
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(
                        bottom: AppSpacing.s2),
                    child: HaynInlineBanner(
                      tone: HaynBannerTone.info,
                      icon: Icons.restore_rounded,
                      message: l.trashRetentionBanner(retention),
                    ),
                  );
                }
                final item = items[i - 1];
                return _TrashRow(
                  item: item,
                  retention: retention,
                  theme: theme,
                  l: l,
                  onRestore: () => _restore(context, ref, item, l),
                  onDelete: () => _deleteForever(context, ref, item, l),
                );
              },
            ),
    );
  }

  Future<void> _emptyAll(
      BuildContext context, WidgetRef ref, AppLocalizations l) async {
    final ok = await showHaynDestructiveConfirm(
      context: context,
      title: l.trashConfirmEmpty,
      message: l.trashConfirmEmptyMsg,
      confirmLabel: l.trashConfirmEmptyAll,
      cancelLabel: l.commonCancel,
    );
    if (ok) ref.read(trashProvider.notifier).emptyAll();
  }

  Future<void> _restore(
      BuildContext context,
      WidgetRef ref,
      TrashItem item,
      AppLocalizations l) async {
    HapticFeedback.lightImpact();
    await ref.read(trashProvider.notifier).restore(item.id);
    if (context.mounted) HaynSnack.success(context, l.trashRestored(item.filename));
  }

  Future<void> _deleteForever(
      BuildContext context,
      WidgetRef ref,
      TrashItem item,
      AppLocalizations l) async {
    final ok = await showHaynDestructiveConfirm(
      context: context,
      title: l.trashConfirmDelete,
      message: l.trashConfirmDeleteMsg(item.filename),
      confirmLabel: l.commonDelete,
      cancelLabel: l.commonCancel,
    );
    if (ok) await ref.read(trashProvider.notifier).deleteForever(item.id);
  }
}

class _TrashRow extends StatelessWidget {
  const _TrashRow({
    required this.item,
    required this.retention,
    required this.theme,
    required this.l,
    required this.onRestore,
    required this.onDelete,
  });

  final TrashItem item;
  final int retention;
  final ThemeData theme;
  final AppLocalizations l;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final daysLeft = item.daysRemaining(retention);
    final dangerSoon = daysLeft <= 3;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _preview(context),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: hc.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              clipBehavior: Clip.antiAlias,
              child: _backupExists
                  ? Image.file(
                      File(item.backupPath),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      cacheWidth: 112,
                      errorBuilder: (_, __, ___) => _fallbackIcon(hc),
                    )
                  : _fallbackIcon(hc),
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.filename,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Specs: dimensions · size · format — straight from the entry.
                Text(
                  _specs(),
                  style: theme.textTheme.labelSmall?.copyWith(color: hc.text2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 12,
                      color: dangerSoon ? hc.dangerColor : hc.text2,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l.trashDaysLeft(daysLeft),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: dangerSoon ? hc.dangerColor : hc.text2,
                        fontWeight: dangerSoon ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.restore_rounded),
            color: hc.accent,
            tooltip: l.trashRestoreTooltip,
            onPressed: onRestore,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            color: hc.dangerColor,
            tooltip: l.trashDeleteForeverTooltip,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  bool get _backupExists =>
      item.backupPath.isNotEmpty && File(item.backupPath).existsSync();

  Widget _fallbackIcon(HaynColors hc) => Icon(
        item.assetType == TrashAssetType.video
            ? Icons.movie_outlined
            : Icons.photo_outlined,
        color: hc.text3,
        size: 22,
      );

  /// "4000×3000 · 2.4 MB · HEIC" — from the stored entry, no decode needed.
  String _specs() {
    final parts = <String>[];
    if (item.width > 0 && item.height > 0) {
      parts.add('${item.width}×${item.height}');
    }
    if (item.originalBytes > 0) parts.add(_fmtBytes(item.originalBytes));
    final fmt = _formatLabel(item.mimeType);
    if (fmt != null) parts.add(fmt);
    return parts.join(' · ');
  }

  /// Zoomable full preview of the backed-up original.
  void _preview(BuildContext context) {
    if (!_backupExists) return;
    HapticFeedback.selectionClick();
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 8,
                child: Center(
                  child: Image.file(File(item.backupPath), fit: BoxFit.contain),
                ),
              ),
            ),
            PositionedDirectional(
              top: 0,
              end: 0,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String? _formatLabel(String? mime) {
    if (mime == null || mime.isEmpty) return null;
    final m = mime.toLowerCase();
    if (m.contains('hei')) return 'HEIC';
    if (m.contains('avif')) return 'AVIF';
    if (m.contains('webp')) return 'WebP';
    if (m.contains('png')) return 'PNG';
    if (m.contains('jpeg') || m.contains('jpg')) return 'JPEG';
    final slash = m.indexOf('/');
    return slash >= 0 ? m.substring(slash + 1).toUpperCase() : null;
  }

  static String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
