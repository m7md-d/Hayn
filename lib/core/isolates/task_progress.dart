sealed class TaskEvent {
  const TaskEvent();
}

/// Emit only after all requested work has succeeded, including gallery saves.
final class TaskSucceeded extends TaskEvent {
  const TaskSucceeded();
}

final class TaskFailed extends TaskEvent {
  const TaskFailed(this.error);
  final Object error;
}

final class TaskCancelled extends TaskEvent {
  const TaskCancelled();
}

final class TaskProgress extends TaskEvent {
  const TaskProgress({
    required this.progress,
    required this.phase,
    this.estimatedRemaining,
  });

  /// 0.0 to 1.0
  final double progress;

  /// Human-readable phase description (localised by caller)
  final String phase;

  final Duration? estimatedRemaining;

  int get percent => (progress * 100).clamp(0, 100).round();

  TaskProgress copyWith({
    double? progress,
    String? phase,
    Duration? estimatedRemaining,
  }) {
    return TaskProgress(
      progress: progress ?? this.progress,
      phase: phase ?? this.phase,
      estimatedRemaining: estimatedRemaining ?? this.estimatedRemaining,
    );
  }
}
