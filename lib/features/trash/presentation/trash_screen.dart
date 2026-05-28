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
// TrashScreen — items removed via Surgical Replace. Expire after the
// configured retention window. Fully localised.
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
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: hc.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            clipBehavior: Clip.antiAlias,
            child: item.thumbnail != null
                ? Image.memory(item.thumbnail!,
                    fit: BoxFit.cover, gaplessPlayback: true)
                : Icon(
                    item.assetType == TrashAssetType.video
                        ? Icons.movie_outlined
                        : Icons.photo_outlined,
                    color: hc.text3,
                    size: 22,
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
}
