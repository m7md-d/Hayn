import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/motion.dart';
import '../../../core/isolates/task_runner.dart';
import '../../../shared/widgets/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TasksScreen — queue view. Filter pill + list of task cards. Each card shows
// progress, status, and the appropriate action (cancel / retry / view).
//
// When there are no tasks (filtered or otherwise), an empty state explains
// where tasks come from. The "Clear completed" action appears in the AppBar
// only when at least one task is in the completed state.
// ─────────────────────────────────────────────────────────────────────────────

enum _TasksFilter { all, running, done, failed }

final _tasksFilterProvider = StateProvider<_TasksFilter>((ref) => _TasksFilter.all);

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final theme = Theme.of(context);
    final tasks = ref.watch(taskRunnerProvider);
    final filter = ref.watch(_tasksFilterProvider);

    final filtered = _applyFilter(tasks, filter);
    final hasCompleted =
        tasks.any((t) => t.status == TaskStatus.completed);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverAppBar.large(
            pinned: true,
            stretch: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            shadowColor: hc.border,
            scrolledUnderElevation: 0.5,
            // Tasks is now a pushed full-screen route, not a tab — show
            // the system back button.
            automaticallyImplyLeading: true,
            title: Text(l.tasksTitle),
            actions: hasCompleted
                ? [
                    TextButton(
                      onPressed: () {
                        // Will hook into TaskRunner.clearCompleted() once added.
                        HaynSnack.info(context, l.tasksClearCompleted);
                      },
                      child: Text(l.tasksClearCompleted),
                    ),
                  ]
                : null,
            expandedHeight: 112,
            systemOverlayStyle: theme.brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
          ),

          // Filter pill (only useful when tasks exist)
          if (tasks.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.s3,
                ),
                child: HaynSegmentedPill<_TasksFilter>(
                  value: filter,
                  onChanged: (f) =>
                      ref.read(_tasksFilterProvider.notifier).state = f,
                  items: [
                    HaynSegmentItem(
                        value: _TasksFilter.all, label: l.tasksFilterAll),
                    HaynSegmentItem(
                        value: _TasksFilter.running,
                        label: l.tasksFilterRunning),
                    HaynSegmentItem(
                        value: _TasksFilter.done, label: l.tasksFilterDone),
                    HaynSegmentItem(
                        value: _TasksFilter.failed,
                        label: l.tasksFilterFailed),
                  ],
                ),
              ),
            ),

          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: HaynEmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: l.tasksEmptyTitle,
                message: l.tasksEmptyMessage,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: AppSpacing.md),
              sliver: SliverList.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.s3),
                itemBuilder: (ctx, i) => HaynStagger(
                  index: i,
                  child: _TaskCard(taskState: filtered[i], ref: ref),
                ),
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
        ],
      ),
    );
  }

  List<TaskState> _applyFilter(List<TaskState> tasks, _TasksFilter f) =>
      switch (f) {
        _TasksFilter.all => tasks,
        _TasksFilter.running => tasks
            .where((t) =>
                t.status == TaskStatus.running ||
                t.status == TaskStatus.pending)
            .toList(),
        _TasksFilter.done =>
          tasks.where((t) => t.status == TaskStatus.completed).toList(),
        _TasksFilter.failed => tasks
            .where((t) =>
                t.status == TaskStatus.failed ||
                t.status == TaskStatus.cancelled)
            .toList(),
      };
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.taskState, required this.ref});
  final TaskState taskState;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final progress = taskState.progress;
    final status = taskState.status;

    final (statusLabel, statusKind) = switch (status) {
      TaskStatus.pending => (l.taskStatusPending, HaynStatusKind.pending),
      TaskStatus.running => (l.taskStatusRunning, HaynStatusKind.running),
      TaskStatus.completed => (l.taskStatusCompleted, HaynStatusKind.completed),
      TaskStatus.cancelled => (l.taskStatusCancelled, HaynStatusKind.cancelled),
      TaskStatus.failed => (l.taskStatusFailed, HaynStatusKind.failed),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () {
        HapticFeedback.selectionClick();
        context.push('/task/${taskState.task.id}');
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: hc.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(_iconFor(taskState),
                    color: hc.accent, size: 18),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Text(
                  taskState.task.id,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.s2),
              HaynStatusBadge(kind: statusKind, label: statusLabel),
            ],
          ),
          if (progress != null && status == TaskStatus.running) ...[
            const SizedBox(height: AppSpacing.s3),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: LinearProgressIndicator(
                value: progress.progress,
                minHeight: 4,
                backgroundColor: hc.surfaceSunken,
                color: hc.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.s1),
            Text(
              l.taskProgressLabel(progress.phase, progress.percent),
              style: theme.textTheme.labelSmall?.copyWith(
                color: hc.text2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (_hasAction(status)) ...[
            const SizedBox(height: AppSpacing.s3),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _actionFor(context, status, l),
            ),
          ],
        ],
        ),
      ),
    );
  }

  IconData _iconFor(TaskState s) {
    // Type-specific icons come once real task subclasses appear; placeholder
    // for now uses a generic spark for media work.
    return Icons.auto_fix_high_rounded;
  }

  bool _hasAction(TaskStatus s) =>
      s == TaskStatus.running ||
      s == TaskStatus.failed ||
      s == TaskStatus.completed;

  Widget _actionFor(BuildContext context, TaskStatus status, AppLocalizations l) {
    final hc = context.hc;
    switch (status) {
      case TaskStatus.running:
        return TextButton.icon(
          onPressed: () {
            HapticFeedback.lightImpact();
            ref.read(taskRunnerProvider.notifier).cancel(taskState.task.id);
          },
          icon: Icon(Icons.close_rounded, size: 16, color: hc.dangerColor),
          label: Text(
            l.taskCancelButton,
            style: TextStyle(color: hc.dangerColor),
          ),
        );
      case TaskStatus.failed:
        return TextButton.icon(
          onPressed: () {
            // Will re-enqueue once retry hook is added.
            HapticFeedback.lightImpact();
          },
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text(l.taskRetryButton),
        );
      case TaskStatus.completed:
        return TextButton.icon(
          onPressed: () {
            // Opens the result preview in D10.
          },
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(l.taskViewOutputButton),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
