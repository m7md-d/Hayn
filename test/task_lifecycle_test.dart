import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/core/isolates/media_task.dart';
import 'package:hayn/core/isolates/task_progress.dart';
import 'package:hayn/core/isolates/task_runner.dart';

class _ControlledTask extends MediaTask {
  final events = StreamController<TaskEvent>();
  final cleaned = Completer<void>();
  final stop = Completer<void>();
  bool waitForStop = false;
  bool failCleanup = false;
  int cancels = 0;
  int cleanups = 0;
  @override
  String get id => 'controlled';
  @override
  TaskType get type => TaskType.dummy;
  @override
  Stream<TaskEvent> run() => events.stream;
  @override
  Future<void> cancel() async {
    cancels++;
    if (waitForStop) await stop.future;
  }

  @override
  Future<void> cleanup() async {
    cleanups++;
    cleaned.complete();
    if (failCleanup) throw StateError('sensitive-path-must-not-be-logged');
  }
}

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late ProviderContainer container;
  late TaskRunner runner;
  late _ControlledTask task;
  setUp(() async {
    container = ProviderContainer();
    runner = container.read(taskRunnerProvider.notifier);
    task = _ControlledTask();
    await runner.enqueue(task);
  });
  tearDown(() async {
    if (!task.stop.isCompleted) task.stop.complete();
    await runner.cancel(task.id);
    container.dispose();
    await task.events.close();
  });

  test(
    'error wins over queued progress and success, with one cleanup',
    () async {
      task.events.addError(StateError('failed'));
      task.events.add(const TaskProgress(progress: 1, phase: 'late'));
      task.events.add(const TaskSucceeded());
      await task.cleaned.future;
      await flush();
      final state = container.read(taskRunnerProvider).single;
      expect(state.status, TaskStatus.failed);
      expect(state.error, isA<StateError>());
      expect(task.cleanups, 1);
    },
  );

  test(
    'successful task is cleaned; later cancellation cannot change outcome',
    () async {
      task.events.add(const TaskSucceeded());
      await task.cleaned.future;
      await flush();
      await runner.cancel(task.id);
      expect(
        container.read(taskRunnerProvider).single.status,
        TaskStatus.completed,
      );
      expect(task.cancels, 0);
      expect(task.cleanups, 1);
    },
  );

  test('concurrent cancellation waits for producer before cleanup', () async {
    task.waitForStop = true;
    final first = runner.cancel(task.id);
    final second = runner.cancel(task.id);
    task.events.add(const TaskSucceeded());
    await flush();
    expect(task.cancels, 1);
    expect(task.cleanups, 0);
    task.stop.complete();
    await Future.wait([first, second]);
    expect(task.cleanups, 1);
    expect(
      container.read(taskRunnerProvider).single.status,
      TaskStatus.cancelled,
    );
  });

  test(
    'cleanup failure stays visible without replacing successful output',
    () async {
      task.failCleanup = true;
      task.events.add(const TaskSucceeded());
      await task.cleaned.future;
      await flush();
      expect(
        container.read(taskRunnerProvider).single.status,
        TaskStatus.completed,
      );
      expect(MediaDiagnostics.recent.last.operation, MediaOperation.cleanup);
      expect(MediaDiagnostics.recent.last.code, MediaDiagnosticCode.exception);
      expect(MediaDiagnostics.recent.join(), isNot(contains('sensitive-path')));
    },
  );

  test('duplicate identity is rejected without losing running task', () async {
    await expectLater(runner.enqueue(_ControlledTask()), throwsArgumentError);
    expect(container.read(taskRunnerProvider), hasLength(1));
    expect(task.cancels, 0);
  });

  test(
    'provider disposal cancels producer and cleans without late state writes',
    () async {
      container.dispose();
      await task.cleaned.future;
      await flush();
      expect(task.cancels, 1);
      expect(task.cleanups, 1);
    },
  );

  test('typed failure is a terminal result', () async {
    task.events.add(const TaskFailed(IncompleteBatch(saved: 1, total: 2)));
    await task.cleaned.future;
    await flush();
    expect(container.read(taskRunnerProvider).single.status, TaskStatus.failed);
    expect(
      container.read(taskRunnerProvider).single.error,
      isA<IncompleteBatch>(),
    );
  });
  test('producer cancellation is a terminal result', () async {
    task.events.add(const TaskCancelled());
    await task.cleaned.future;
    await flush();
    expect(
      container.read(taskRunnerProvider).single.status,
      TaskStatus.cancelled,
    );
  });
}
