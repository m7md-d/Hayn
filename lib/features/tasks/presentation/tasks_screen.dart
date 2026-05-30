import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/motion.dart';
import '../../../core/isolates/media_task.dart';
import '../../../core/isolates/task_runner.dart';
import '../../../shared/widgets/widgets.dart';
import '../../library/presentation/widgets/id_thumbnail.dart';

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

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the queue dismisses the "all done" badge notification.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(tasksAcknowledgedProvider.notifier).state = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final theme = Theme.of(context);
    final tasks = ref.watch(taskRunnerProvider);
    final filter = ref.watch(_tasksFilterProvider);

    final filtered = _applyFilter(tasks, filter);
    final hasFinished = tasks.any((t) =>
        t.status == TaskStatus.completed ||
        t.status == TaskStatus.failed ||
        t.status == TaskStatus.cancelled);

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
            actions: hasFinished
                ? [
                    TextButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        ref.read(taskRunnerProvider.notifier).clearFinished();
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

// Maps a task type to its localised, human-readable title — so the queue
// reads "Compress · 3 images", not an opaque "compress-1a2b3c" id.
String taskTitleFor(TaskType t, AppLocalizations l) => switch (t) {
      TaskType.compress || TaskType.convert => l.toolCompress,
      TaskType.crop => l.toolCrop,
      TaskType.stripMetadata => l.toolStripMetadata,
      _ => l.tasksTitle,
    };

IconData taskIconFor(TaskType t) => switch (t) {
      TaskType.compress || TaskType.convert => Icons.compress_rounded,
      TaskType.crop => Icons.crop_rounded,
      TaskType.stripMetadata => Icons.cleaning_services_rounded,
      _ => Icons.auto_fix_high_rounded,
    };

/// Opens the first output of a finished task in the in-app viewer. Returns
/// false (so the caller can surface a message) when there's nothing to show.
bool openTaskOutput(BuildContext context, MediaTask task) {
  final out = task.outputAssetIds;
  if (out.isEmpty) return false;
  // iOS asset ids contain '/', which would break the path — encode it.
  context.push('/asset/${Uri.encodeComponent(out.first)}');
  return true;
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
    final task = taskState.task;

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
                // Thumbnail of the source photo so the task is recognisable.
                _TaskThumb(task: task),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        taskTitleFor(task.type, l),
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l.taskItemsCount(task.itemCount),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: hc.text2),
                      ),
                    ],
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
              const SizedBox(height: AppSpacing.s2),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: _actionsFor(context, status, l),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasAction(TaskStatus s) => s != TaskStatus.pending;

  List<Widget> _actionsFor(
      BuildContext context, TaskStatus status, AppLocalizations l) {
    final hc = context.hc;
    final notifier = ref.read(taskRunnerProvider.notifier);
    final task = taskState.task;

    switch (status) {
      case TaskStatus.running:
        return [
          TextButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              notifier.cancel(task.id);
            },
            icon: Icon(Icons.close_rounded, size: 16, color: hc.dangerColor),
            label: Text(l.taskCancelButton,
                style: TextStyle(color: hc.dangerColor)),
          ),
        ];
      case TaskStatus.completed:
        return [
          TextButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              notifier.remove(task.id);
            },
            icon: Icon(Icons.delete_outline_rounded,
                size: 16, color: hc.text2),
            label: Text(l.taskRemove, style: TextStyle(color: hc.text2)),
          ),
          const SizedBox(width: AppSpacing.s2),
          if (task.outputAssetIds.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                if (!openTaskOutput(context, task)) {
                  HaynSnack.info(context, l.taskOpenError);
                }
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text(l.taskViewOutputButton),
            ),
        ];
      case TaskStatus.failed:
      case TaskStatus.cancelled:
        return [
          TextButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              notifier.remove(task.id);
            },
            icon: Icon(Icons.delete_outline_rounded,
                size: 16, color: hc.text2),
            label: Text(l.taskRemove, style: TextStyle(color: hc.text2)),
          ),
        ];
      default:
        return const [SizedBox.shrink()];
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TaskThumb — 44×44 rounded thumbnail of the task's source photo, falling back
// to a type icon when the task has no representative asset.
// ─────────────────────────────────────────────────────────────────────────────
class _TaskThumb extends StatelessWidget {
  const _TaskThumb({required this.task});
  final MediaTask task;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final id = task.sourceAssetId;
    if (id == null) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: hc.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        alignment: Alignment.center,
        child: Icon(taskIconFor(task.type), color: hc.accent, size: 20),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        width: 44,
        height: 44,
        child: IdThumbnail(id: id, placeholderColor: hc.surfaceSunken),
      ),
    );
  }
}
