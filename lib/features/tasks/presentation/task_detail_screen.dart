import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/isolates/task_runner.dart';
import '../../../shared/widgets/widgets.dart';

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

    return HaynScaffold(
      appBar: HaynDetailAppBar(title: task.task.id),
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
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: hc.accentSoft,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.auto_fix_high_rounded,
                          color: hc.accent, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.s3),
                    Expanded(
                      child: Text(
                        task.task.id,
                        style: theme.textTheme.titleLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
          else if (task.status == TaskStatus.failed)
            HaynPrimaryButton(
              label: l.taskRetryButton,
              icon: Icons.refresh_rounded,
              onPressed: () {},
            )
          else if (task.status == TaskStatus.completed)
            HaynPrimaryButton(
              label: l.taskViewOutputButton,
              icon: Icons.open_in_new_rounded,
              onPressed: () {},
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
                          task.error.toString(),
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
}
