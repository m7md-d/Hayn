import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../core/isolates/task_runner.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TasksAppBarButton — a FIXED entry point to the task queue that lives in the
// app bar alongside the other actions (replaces the old draggable floating
// bubble). Always present; it tints + shows a count only when there's activity:
//   running/pending → warning + count
//   failed          → danger + count
//   all completed   → success dot
//   idle            → neutral icon
// Tapping opens the queue.
// ─────────────────────────────────────────────────────────────────────────────

class TasksAppBarButton extends ConsumerWidget {
  const TasksAppBarButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final tasks = ref.watch(taskRunnerProvider);

    final acknowledged = ref.watch(tasksAcknowledgedProvider);
    final running = tasks
        .where((t) =>
            t.status == TaskStatus.running || t.status == TaskStatus.pending)
        .length;
    final failed =
        tasks.where((t) => t.status == TaskStatus.failed).length;
    // The green "all done" dot is a NOTIFICATION — once the user has opened the
    // queue (acknowledged), it clears and the button goes neutral.
    final allDone = !acknowledged &&
        tasks.isNotEmpty &&
        tasks.every((t) => t.status == TaskStatus.completed);

    final (Color tint, int count, bool dot) = running > 0
        ? (hc.warningColor, running, false)
        : failed > 0
            ? (hc.dangerColor, failed, false)
            : allDone
                ? (hc.successColor, 0, true)
                : (hc.text2, 0, false);

    return IconButton(
      tooltip: 'Tasks',
      onPressed: () {
        HapticFeedback.selectionClick();
        context.push('/tasks');
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.task_alt_rounded, color: tint),
          if (count > 0)
            PositionedDirectional(
              end: -6,
              top: -6,
              child: Container(
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: hc.surface, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            )
          else if (dot)
            PositionedDirectional(
              end: -2,
              top: -2,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: tint,
                  shape: BoxShape.circle,
                  border: Border.all(color: hc.surface, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
