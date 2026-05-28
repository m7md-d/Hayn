import 'dart:async';
import 'media_task.dart';
import 'task_progress.dart';

String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(16);

class DummyTask extends MediaTask {
  DummyTask() : id = 'dummy-${_newId()}';

  @override
  final String id;

  @override
  TaskType get type => TaskType.dummy;

  bool _cancelled = false;

  @override
  Stream<TaskProgress> run() async* {
    const steps = 20;
    for (var i = 0; i <= steps; i++) {
      if (_cancelled) return;
      await Future.delayed(const Duration(milliseconds: 200));
      if (_cancelled) return;
      yield TaskProgress(
        progress: i / steps,
        phase: 'Processing step $i / $steps',
        estimatedRemaining:
            Duration(milliseconds: (steps - i) * 200),
      );
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  @override
  Future<void> cleanup() async {}
}
