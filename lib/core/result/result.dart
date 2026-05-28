sealed class Result<T, E> {
  const Result();

  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  T get value => (this as Ok<T, E>).value;
  E get error => (this as Err<T, E>).error;

  R fold<R>(R Function(T value) onOk, R Function(E error) onErr) {
    return switch (this) {
      Ok(:final value) => onOk(value),
      Err(:final error) => onErr(error),
    };
  }

  Result<U, E> map<U>(U Function(T value) f) {
    return switch (this) {
      Ok(:final value) => Ok(f(value)),
      Err(:final error) => Err(error),
    };
  }

  Result<T, F> mapErr<F>(F Function(E error) f) {
    return switch (this) {
      Ok(:final value) => Ok(value),
      Err(:final error) => Err(f(error)),
    };
  }

  T getOrElse(T Function(E error) fallback) {
    return switch (this) {
      Ok(:final value) => value,
      Err(:final error) => fallback(error),
    };
  }
}

final class Ok<T, E> extends Result<T, E> {
  const Ok(this.value);

  @override
  final T value;
}

final class Err<T, E> extends Result<T, E> {
  const Err(this.error);

  @override
  final E error;
}
