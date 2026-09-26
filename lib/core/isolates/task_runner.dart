import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/media_diagnostics.dart';
import 'media_task.dart';
import 'task_progress.dart';

enum TaskStatus { pending, running, completed, cancelled, failed }

class TaskState {
  const TaskState({
    required this.task,
    required this.status,
    required this.enqueuedAt,
    this.progress,
    this.error,
    this.startedAt,
    this.endedAt,
  });

  final MediaTask task;
  final TaskStatus status;
  final TaskProgress? progress;
  final Object? error;

  /// When the task entered the queue — drives the relative-time label.
  final DateTime enqueuedAt;

  /// When it started running / finished — their delta is the elapsed time.
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// Wall-clock duration of the run, once it has both endpoints.
  Duration? get elapsed => (startedAt != null && endedAt != null)
      ? endedAt!.difference(startedAt!)
      : null;

  TaskState copyWith({
    TaskStatus? status,
    TaskProgress? progress,
    Object? error,
    DateTime? startedAt,
    DateTime? endedAt,
  }) {
    return TaskState(
      task: task,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
      enqueuedAt: enqueuedAt,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }
}

class _ActiveTask {
  _ActiveTask(this.task);
  final MediaTask task;
  final subscription = Completer<StreamSubscription<TaskEvent>?>();
  Completer<void>? finishing;
}

class TaskRunner extends Notifier<List<TaskState>> {
  final _active = <String, _ActiveTask>{};
  bool _disposed = false;

  @override
  List<TaskState> build() {
    ref.onDispose(() {
      _disposed = true;
      for (final run in _active.values.toList()) {
        unawaited(_finish(run, TaskStatus.cancelled));
      }
    });
    return [];
  }

  Future<void> enqueue(MediaTask task) async {
    if (_disposed) throw StateError('Task runner is disposed');
    if (state.any((s) => s.task.id == task.id)) {
      throw ArgumentError('Task ID already exists');
    }
    ref.read(tasksAcknowledgedProvider.notifier).state = false;
    final now = DateTime.now();
    state = [
      ...state,
      TaskState(
        task: task,
        status: TaskStatus.running,
        enqueuedAt: now,
        startedAt: now,
      ),
    ];
    final run = _ActiveTask(task);
    _active[task.id] = run;
    try {
      final sub = task.run().listen(
        (event) {
          if (run.finishing != null) return;
          switch (event) {
            case TaskProgress():
              _updateTask(task.id, (s) => s.copyWith(progress: event));
            case TaskSucceeded():
              unawaited(_finish(run, TaskStatus.completed));
            case TaskFailed(:final error):
              unawaited(_finish(run, TaskStatus.failed, error: error));
            case TaskCancelled():
              unawaited(_finish(run, TaskStatus.cancelled));
          }
        },
        onError: (Object error, StackTrace stack) {
          unawaited(_finish(run, TaskStatus.failed, error: error));
        },
        onDone: () {
          if (run.finishing != null) return;
          MediaDiagnostics.record(
            MediaBackend.taskRunner,
            MediaOperation.task,
            MediaDiagnosticCode.missingResult,
          );
          unawaited(
            _finish(
              run,
              TaskStatus.failed,
              error: StateError('Task closed without a terminal result'),
            ),
          );
        },
      );
      run.subscription.complete(sub);
    } catch (error) {
      run.subscription.complete(null);
      await _finish(run, TaskStatus.failed, error: error);
    }
  }

  /// Reserve the first terminal outcome before awaiting anything. In particular,
  /// cancel the producer BEFORE waiting for async* subscription cancellation.
  Future<void> _finish(_ActiveTask run, TaskStatus status, {Object? error}) {
    if (run.finishing case final existing?) return existing.future;
    final done = Completer<void>();
    run.finishing = done;
    unawaited(_stopAndClean(run, status, error).then((_) => done.complete()));
    return done.future;
  }

  Future<void> _stopAndClean(
    _ActiveTask run,
    TaskStatus status,
    Object? error,
  ) async {
    if (status == TaskStatus.failed) {
      MediaDiagnostics.record(
        MediaBackend.taskRunner,
        MediaOperation.task,
        MediaDiagnosticCode.exception,
      );
    }
    if (status != TaskStatus.completed) {
      try {
        await run.task.cancel();
      } catch (cancelError) {
        MediaDiagnostics.record(
          MediaBackend.taskRunner,
          MediaOperation.cancel,
          MediaDiagnosticCode.exception,
        );
        error ??= cancelError;
        status = TaskStatus.failed;
      }
    }
    try {
      await (await run.subscription.future)?.cancel();
    } catch (streamError) {
      MediaDiagnostics.record(
        MediaBackend.taskRunner,
        MediaOperation.cancel,
        MediaDiagnosticCode.exception,
      );
      error ??= streamError;
      status = TaskStatus.failed;
    }
    try {
      await run.task.cleanup();
    } catch (_) {
      MediaDiagnostics.record(
        MediaBackend.taskRunner,
        MediaOperation.cleanup,
        MediaDiagnosticCode.exception,
      );
    }
    _active.remove(run.task.id);
    _updateTask(
      run.task.id,
      (s) => s.copyWith(status: status, error: error, endedAt: DateTime.now()),
    );
  }

  Future<void> cancel(String taskId) async {
    final run = _active[taskId];
    if (run != null) await _finish(run, TaskStatus.cancelled);
  }

  /// Remove one finished task from the queue. No-op while it's still running.
  void remove(String taskId) {
    final s = state.where((t) => t.task.id == taskId).firstOrNull;
    if (s == null ||
        (s.status == TaskStatus.running || s.status == TaskStatus.pending)) {
      return;
    }
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
    if (_disposed) return;
    state = [
      for (final s in state)
        if (s.task.id == id) update(s) else s,
    ];
  }
}

final taskRunnerProvider = NotifierProvider<TaskRunner, List<TaskState>>(
  TaskRunner.new,
);

/// Whether the user has SEEN the current "all done" state. The Tasks app-bar
/// button shows its green completion dot only while this is false; opening the
/// Tasks screen sets it true (the notification is dismissed), and enqueuing new
/// work resets it to false. Starts true so a fresh, empty queue shows nothing.
final tasksAcknowledgedProvider = StateProvider<bool>((ref) => true);
