class TaskProgress {
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
