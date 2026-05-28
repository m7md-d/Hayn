sealed class AppError {
  const AppError();

  String get message;
}

final class FileAccessError extends AppError {
  const FileAccessError(this.message, {this.path});

  @override
  final String message;
  final String? path;
}

final class EncodingError extends AppError {
  const EncodingError(this.message, {this.codec});

  @override
  final String message;
  final String? codec;
}

final class TaskCancelledError extends AppError {
  const TaskCancelledError();

  @override
  String get message => 'Task was cancelled';
}

final class PermissionError extends AppError {
  const PermissionError(this.message);

  @override
  final String message;
}

final class VerificationError extends AppError {
  const VerificationError(this.message);

  @override
  final String message;
}

final class UnknownError extends AppError {
  const UnknownError(this.message, {this.cause});

  @override
  final String message;
  final Object? cause;
}
