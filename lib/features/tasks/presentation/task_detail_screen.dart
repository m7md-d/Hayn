import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/isolates/task_runner.dart';
import '../../../shared/widgets/widgets.dart';
import '../../image_ops/data/image_compress_task.dart';
import '../../image_ops/data/metadata.dart' show StripUnsupportedFormat;
import '../../library/presentation/widgets/id_thumbnail.dart';
import 'tasks_screen.dart'
    show
        taskTitleFor,
        taskIconFor,
        openTaskOutput,
        taskRelativeTime,
        taskElapsedLabel,
        TaskOpenResult;

// ─────────────────────────────────────────────────────────────────────────────
// TaskDetailScreen — live progress, phase tail log, and the right action for
// the current status (Cancel / Retry / View output).
//
// When the task disappears from the runner (e.g. cleared), we route back to
// the tasks list automatically.
// ─────────────────────────────────────────────────────────────────────────────

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({required this.taskId, super.key});
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final theme = Theme.of(context);

    final tasks = ref.watch(taskRunnerProvider);
    final task = tasks.where((t) => t.task.id == taskId).firstOrNull;

    if (task == null) {
      // Task gone — show a transient placeholder and pop on next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return HaynScaffold(
        appBar: HaynDetailAppBar(title: l.tasksTitle),
        body: HaynEmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: l.tasksEmptyTitle,
          message: l.tasksEmptyMessage,
        ),
      );
    }

    final progress = task.progress;
    final (statusLabel, statusKind) = switch (task.status) {
      TaskStatus.pending => (l.taskStatusPending, HaynStatusKind.pending),
      TaskStatus.running => (l.taskStatusRunning, HaynStatusKind.running),
      TaskStatus.completed => (l.taskStatusCompleted, HaynStatusKind.completed),
      TaskStatus.cancelled => (l.taskStatusCancelled, HaynStatusKind.cancelled),
      TaskStatus.failed => (l.taskStatusFailed, HaynStatusKind.failed),
    };

    final srcId = task.task.sourceAssetId;

    return HaynScaffold(
      appBar: HaynDetailAppBar(title: taskTitleFor(task.task.type, l)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // ── Header card ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (srcId != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: IdThumbnail(
                              id: srcId, placeholderColor: hc.surfaceSunken),
                        ),
                      )
                    else
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: hc.accentSoft,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        alignment: Alignment.center,
                        child: Icon(taskIconFor(task.task.type),
                            color: hc.accent, size: 22),
                      ),
                    const SizedBox(width: AppSpacing.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            taskTitleFor(task.task.type, l),
                            style: theme.textTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l.taskItemsCount(task.task.itemCount),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: hc.text2),
                          ),
                        ],
                      ),
                    ),
                    HaynStatusBadge(kind: statusKind, label: statusLabel),
                  ],
                ),
                if (progress != null && task.status == TaskStatus.running) ...[
                  const SizedBox(height: AppSpacing.md),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: LinearProgressIndicator(
                      value: progress.progress,
                      minHeight: 6,
                      backgroundColor: hc.surfaceSunken,
                      color: hc.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        progress.phase,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: hc.text2,
                        ),
                      ),
                      Text(
                        '${progress.percent}%',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: hc.accent,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (progress.estimatedRemaining != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded,
                            size: 12, color: hc.text3),
                        const SizedBox(width: 4),
                        Text(
                          '~${_formatDuration(progress.estimatedRemaining!)} ${l.taskRemaining}',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: hc.text3),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Details ────────────────────────────────────────────────────
          _DetailsCard(rows: _detailRows(task, l)),

          const SizedBox(height: AppSpacing.md),

          // ── Action ─────────────────────────────────────────────────────
          if (task.status == TaskStatus.running)
            HaynDestructiveButton(
              label: l.taskCancelButton,
              icon: Icons.close_rounded,
              onPressed: () {
                HapticFeedback.mediumImpact();
                ref.read(taskRunnerProvider.notifier).cancel(task.task.id);
              },
            )
          else if (task.status == TaskStatus.completed &&
              task.task.outputAssetIds.isNotEmpty)
            HaynPrimaryButton(
              label: l.taskViewOutputButton,
              icon: Icons.open_in_new_rounded,
              onPressed: () async {
                HapticFeedback.lightImpact();
                final r = await openTaskOutput(task.task);
                if (!context.mounted) return;
                if (r == TaskOpenResult.deleted) {
                  HaynSnack.info(context, l.taskOutputDeleted);
                } else if (r == TaskOpenResult.none) {
                  HaynSnack.info(context, l.taskOpenError);
                }
              },
            )
          else
            HaynSecondaryButton(
              label: l.taskRemove,
              icon: Icons.delete_outline_rounded,
              onPressed: () {
                HapticFeedback.lightImpact();
                ref.read(taskRunnerProvider.notifier).remove(task.task.id);
              },
            ),

          // ── Error details ─────────────────────────────────────────────
          if (task.error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: hc.dangerSoft,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: hc.dangerColor, size: 18),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.taskStatusFailed,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: hc.dangerColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          task.error is StripUnsupportedFormat
                              ? l.stripHeicUnsupported
                              : task.error.toString(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: hc.dangerColor,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Label/value rows for the details card: when it ran, how long it took, and
  /// task-specific parameters (compression format/quality).
  List<({String label, String value})> _detailRows(
      TaskState task, AppLocalizations l) {
    final rows = <({String label, String value})>[
      (label: l.taskQueuedLabel, value: taskRelativeTime(task.enqueuedAt, l)),
    ];
    final elapsed = task.elapsed;
    if (elapsed != null) {
      rows.add((label: l.taskTimeTaken, value: taskElapsedLabel(elapsed)));
    }
    final t = task.task;
    if (t is ImageCompressTask) {
      rows.add((label: l.compressFormat, value: t.format.techName));
      rows.add((label: l.compressQuality, value: '${t.quality}'));
    }
    return rows;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DetailsCard — a compact label/value list (queued time, elapsed, params).
// ─────────────────────────────────────────────────────────────────────────────
class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.rows});
  final List<({String label, String value})> rows;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.s2),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
              child: Row(
                children: [
                  Text(r.label, style: theme.textTheme.bodyMedium),
                  const Spacer(),
                  Text(
                    r.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: hc.text2,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
