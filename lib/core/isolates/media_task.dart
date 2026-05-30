import '../errors/app_error.dart';
import '../result/result.dart';
import 'task_progress.dart';

enum TaskType {
  compress,
  convert,
  stripMetadata,
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
  MediaTask();

  String get id;
  TaskType get type;

  /// The first input asset id — drives the thumbnail shown for this task in the
  /// queue so the user recognises WHICH photo it is, not just an opaque id.
  /// Null when the task has no single representative source.
  String? get sourceAssetId => null;

  /// How many items this task processes (subtitle: "N images").
  int get itemCount => 1;

  /// Asset ids this task PRODUCED, appended as each output is saved to the
  /// gallery. Drives the "View" action (open the result). Mutable so a running
  /// task fills it in; read by the UI once completed.
  final List<String> outputAssetIds = <String>[];

  /// Emits progress events; completes with Ok or Err.
  Stream<TaskProgress> run();

  Future<void> cancel();

  /// Synchronously clean up temp files.
  Future<void> cleanup();
}

/// Result type returned from MediaTask execution.
typedef TaskResult<T> = Result<T, AppError>;
