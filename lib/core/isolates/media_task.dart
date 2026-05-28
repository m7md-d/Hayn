import '../errors/app_error.dart';
import '../result/result.dart';
import 'task_progress.dart';

enum TaskType {
  compress,
  convert,
  trim,
  smartCut,
  crop,
  stripAudio,
  gifify,
  animatedWebp,
  animatedAvif,
  surgicalReplace,
  audioSeparate,
  dummy,
}

abstract class MediaTask {
  const MediaTask();

  String get id;
  TaskType get type;

  /// Emits progress events; completes with Ok or Err.
  Stream<TaskProgress> run();

  Future<void> cancel();

  /// Synchronously clean up temp files.
  Future<void> cleanup();
}

/// Result type returned from MediaTask execution.
typedef TaskResult<T> = Result<T, AppError>;
