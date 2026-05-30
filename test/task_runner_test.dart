import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/isolates/media_task.dart';
import 'package:hayn/core/isolates/task_progress.dart';
import 'package:hayn/core/isolates/task_runner.dart';

// A task whose run() yields progress then THROWS — exercising the case where a
// Dart async* generator emits an error event followed by a done event.
class _FailTask extends MediaTask {
  _FailTask(this.id);
  @override
  final String id;
  @override
  TaskType get type => TaskType.dummy;
  @override
  Stream<TaskProgress> run() async* {
    yield const TaskProgress(progress: 0.3, phase: 'working');
    throw StateError('boom');
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> cleanup() async {}
}

class _OkTask extends MediaTask {
  _OkTask(this.id);
  @override
  final String id;
  @override
  TaskType get type => TaskType.dummy;
  @override
  Stream<TaskProgress> run() async* {
    yield const TaskProgress(progress: 0.5, phase: 'half');
    yield const TaskProgress(progress: 1, phase: 'done');
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> cleanup() async {}
}

Future<TaskState> _settle(ProviderContainer c, String id) async {
  for (var i = 0; i < 200; i++) {
    final s = c.read(taskRunnerProvider).where((t) => t.task.id == id).first;
    if (s.status != TaskStatus.running && s.status != TaskStatus.pending) {
      return s;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('task $id never reached a terminal status');
}

void main() {
  test('a throwing task ends FAILED — done must not overwrite the error', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    await c.read(taskRunnerProvider.notifier).enqueue(_FailTask('f1'));
    final s = await _settle(c, 'f1');

    expect(s.status, TaskStatus.failed);
    expect(s.error, isA<StateError>());
  });

  test('a normal task ends completed', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    await c.read(taskRunnerProvider.notifier).enqueue(_OkTask('ok1'));
    final s = await _settle(c, 'ok1');

    expect(s.status, TaskStatus.completed);
    expect(s.error, isNull);
  });

  test('clearFinished removes completed + failed, keeps the list tidy', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final runner = c.read(taskRunnerProvider.notifier);

    await runner.enqueue(_OkTask('ok'));
    await runner.enqueue(_FailTask('fail'));
    await _settle(c, 'ok');
    await _settle(c, 'fail');
    expect(c.read(taskRunnerProvider).length, 2);

    runner.clearFinished();
    expect(c.read(taskRunnerProvider), isEmpty);
  });

  test('remove drops a single finished task', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final runner = c.read(taskRunnerProvider.notifier);

    await runner.enqueue(_OkTask('ok'));
    await _settle(c, 'ok');
    runner.remove('ok');

    expect(c.read(taskRunnerProvider), isEmpty);
  });
}
