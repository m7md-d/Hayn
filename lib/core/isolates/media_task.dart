import 'task_progress.dart';

enum TaskType {
  compress,
  convert,
  stripMetadata,
  trim,
  smartCut,
  crop,
  stripAudio,
  extractFrames,
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

  /// Emits progress followed by one terminal event. Closing is not success.
  /// Throwing also fails the task. The runner owns cancellation and cleanup.
  Stream<TaskEvent> run();

  Future<void> cancel();

  /// Release temporary resources after the producer stops. Called once by the
  /// runner on every exit; failures are recorded without hiding the result.
  Future<void> cleanup();
}

/// Some requested items failed. Already saved outputs remain accessible.
class IncompleteBatch implements Exception {
  const IncompleteBatch({required this.saved, required this.total});
  final int saved;
  final int total;

  @override
  String toString() => 'Incomplete batch: $saved/$total saved';
}
