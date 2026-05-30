import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'media_task.dart';
import 'task_progress.dart';

enum TaskStatus { pending, running, completed, cancelled, failed }

class TaskState {
  const TaskState({
    required this.task,
    required this.status,
    this.progress,
    this.error,
  });

  final MediaTask task;
  final TaskStatus status;
  final TaskProgress? progress;
  final Object? error;

  TaskState copyWith({
    TaskStatus? status,
    TaskProgress? progress,
    Object? error,
  }) {
    return TaskState(
      task: task,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
    );
  }
}

class TaskRunner extends Notifier<List<TaskState>> {
  final _subscriptions = <String, StreamSubscription<TaskProgress>>{};

  @override
  List<TaskState> build() => [];

  Future<void> enqueue(MediaTask task) async {
    state = [
      ...state,
      TaskState(task: task, status: TaskStatus.pending),
    ];
    await _start(task);
  }

  Future<void> _start(MediaTask task) async {
    _updateTask(task.id, (s) => s.copyWith(status: TaskStatus.running));

    final sub = task.run().listen(
      (progress) {
        _updateTask(
          task.id,
          (s) => s.copyWith(status: TaskStatus.running, progress: progress),
        );
      },
      onError: (Object err) {
        _updateTask(task.id,
            (s) => s.copyWith(status: TaskStatus.failed, error: err));
        _subscriptions.remove(task.id);
        task.cleanup();
      },
      // A throwing async* generator emits the error event AND THEN a done
      // event — so without this guard `onDone` would overwrite the just-set
      // `failed` (or `cancelled`) status with `completed`, which is exactly
      // why crashed tasks were showing up green. Only promote to completed if
      // the task is still running when the stream closes normally.
      onDone: () {
        _updateTask(
          task.id,
          (s) => s.status == TaskStatus.running
              ? s.copyWith(status: TaskStatus.completed)
              : s,
        );
        _subscriptions.remove(task.id);
      },
    );

    _subscriptions[task.id] = sub;
  }

  Future<void> cancel(String taskId) async {
    final taskState = state.where((s) => s.task.id == taskId).firstOrNull;
    if (taskState == null) return;

    await _subscriptions[taskId]?.cancel();
    _subscriptions.remove(taskId);
    await taskState.task.cancel();
    _updateTask(taskId, (s) => s.copyWith(status: TaskStatus.cancelled));
  }

  /// Remove one finished task from the queue. No-op while it's still running.
  void remove(String taskId) {
    final s = state.where((t) => t.task.id == taskId).firstOrNull;
    if (s == null || s.status == TaskStatus.running) return;
    state = [
      for (final t in state)
        if (t.task.id != taskId) t,
    ];
  }

  /// Clear every finished task (completed / failed / cancelled), leaving only
  /// the ones still running or pending. Backs the "Clear finished" action.
  void clearFinished() {
    state = [
      for (final t in state)
        if (t.status == TaskStatus.running || t.status == TaskStatus.pending) t,
    ];
  }

  void _updateTask(String id, TaskState Function(TaskState) update) {
    state = [
      for (final s in state)
        if (s.task.id == id) update(s) else s,
    ];
  }
}

final taskRunnerProvider = NotifierProvider<TaskRunner, List<TaskState>>(
  TaskRunner.new,
);
