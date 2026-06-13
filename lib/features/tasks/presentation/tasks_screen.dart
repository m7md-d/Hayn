import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:url_launcher/url_launcher.dart';
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
      TaskType.stripAudio => l.toolRemoveAudio,
      TaskType.extractFrames => l.toolExtractFrames,
      _ => l.tasksTitle,
    };

IconData taskIconFor(TaskType t) => switch (t) {
      TaskType.compress || TaskType.convert => Icons.compress_rounded,
      TaskType.crop => Icons.crop_rounded,
      TaskType.stripMetadata => Icons.cleaning_services_rounded,
      TaskType.stripAudio => Icons.volume_off_rounded,
      TaskType.extractFrames => Icons.burst_mode_rounded,
      _ => Icons.auto_fix_high_rounded,
    };

enum TaskOpenResult { opened, deleted, none }

/// Opens the task's first output in the DEVICE gallery (not the app). On
/// Android we hand the asset's content URI to the system viewer; on iOS we open
/// the Photos app (it can't deep-link a single asset, but the result is dated
/// "now" so it sits at the top of Recents). Reports `deleted` if the output is
/// no longer on the device, so the caller can say so.
Future<TaskOpenResult> openTaskOutput(MediaTask task) async {
  final out = task.outputAssetIds;
  if (out.isEmpty) return TaskOpenResult.none;
  final asset = await AssetEntity.fromId(out.first);
  if (asset == null) return TaskOpenResult.deleted;
  try {
    if (Platform.isAndroid) {
      final url = await asset.getMediaUrl();
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return TaskOpenResult.opened;
      }
    }
    // iOS (and the Android fallback): open the system Photos app.
    final ok = await launchUrl(
      Uri.parse('photos-redirect://'),
      mode: LaunchMode.externalApplication,
    );
    return ok ? TaskOpenResult.opened : TaskOpenResult.none;
  } catch (_) {
    return TaskOpenResult.none;
  }
}

/// A compact relative time ("just now", "5 min ago", "2 hr ago", "3 days ago").
String taskRelativeTime(DateTime when, AppLocalizations l) {
  final d = DateTime.now().difference(when);
  if (d.inMinutes < 1) return l.timeJustNow;
  if (d.inMinutes < 60) return l.timeMinutesAgo(d.inMinutes);
  if (d.inHours < 24) return l.timeHoursAgo(d.inHours);
  return l.timeDaysAgo(d.inDays);
}

/// "2.4s" / "1m 04s" — wall-clock run time.
String taskElapsedLabel(Duration d) {
  if (d.inSeconds < 60) {
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '${m}m ${s}s';
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
                        '${l.taskItemsCount(task.itemCount)} · '
                        '${taskRelativeTime(taskState.enqueuedAt, l)}',
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
              onPressed: () async {
                HapticFeedback.lightImpact();
                final r = await openTaskOutput(task);
                if (!context.mounted) return;
                if (r == TaskOpenResult.deleted) {
                  HaynSnack.info(context, l.taskOutputDeleted);
                } else if (r == TaskOpenResult.none) {
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
