import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// One gate for every full-size image job (RUN-02): the compress and crop
// tasks and the compress screen's preview, through ImageEncoder; the crop
// holds one admission for its decode and transform too (RV-02). The strip
// task does not decode and stays outside. Before, each started at once: two tasks, or a
// task and a preview the slider kept restarting, decoded full images side by
// side with no ceiling.
//
// A job states its peak memory estimate. Jobs start in arrival order while
// fewer than [HeavyWork.maxConcurrent] run and the estimate fits the memory
// the platform reports available, less a reserve and less the estimates of
// the jobs running (RV-03): a job admitted a moment ago has not allocated its
// peak yet, so the platform's figure alone would admit a second one into the
// same room. Memory a running job already holds counts twice then, which
// only makes the next one wait. A job that does not fit waits for running
// ones to end; one that does not fit with nothing running is refused
// ([InsufficientMemory], RUN-01 step 6) instead of the system killing the app
// midway. A running job whose path changes to a costlier one (a format
// fallback) asks to [HeavyWork.grow] first. Android reports `MemoryInfo.availMem` and its
// threshold, iOS `os_proc_available_memory()` (M-08); where nothing is
// reported (the iOS simulator), only the count applies.
//
// Cancellation points: a waiting job can be withdrawn ([HeavyWorkTicket], a
// newer preview, a cancelled task); a started one runs to its end, since the
// native encoders (DarkLib, MediaCodec, ImageIO) take no cancel. Callers drop
// its result.

/// Memory the platform reports, in bytes.
class DeviceMemory {
  const DeviceMemory({required this.available, required this.reserve});

  /// What can be allocated without the system reclaiming (Android
  /// `MemoryInfo.availMem`).
  final int available;

  /// What to leave free: the platform's low-memory threshold.
  final int reserve;
}

/// A job's place in the queue; [withdraw] removes it if it has not started.
class HeavyWorkTicket {
  bool _withdrawn = false;
  bool _started = false;
  void Function()? _onWithdraw;

  bool get started => _started;

  /// Leaves the queue at once if not started; a started job runs on.
  void withdraw() {
    if (_withdrawn) return;
    _withdrawn = true;
    _onWithdraw?.call();
  }
}

/// The job was withdrawn before it started.
class HeavyWorkWithdrawn implements Exception {
  @override
  String toString() => 'Heavy work withdrawn before it started';
}

/// The job's estimate exceeds the memory available with nothing else running.
class InsufficientMemory implements Exception {
  const InsufficientMemory(this.estimate, this.available);
  final int estimate;
  final int available;

  @override
  String toString() =>
      'Needs about ${estimate >> 20} MB, ${available >> 20} MB available';
}

class _Job {
  _Job(this.estimate, this.ticket);
  int estimate;
  final HeavyWorkTicket ticket;
  final admitted = Completer<void>();
}

class HeavyWork {
  HeavyWork({Future<DeviceMemory?> Function()? memory, this.maxConcurrent = 2})
    : _memory = memory ?? _platformMemory;

  /// The gate every encode goes through.
  static HeavyWork get instance => _instance;
  static HeavyWork _instance = HeavyWork();

  /// A phone with less memory, for the device tests (one phone, by the
  /// user's decision): a gate that reads [DeviceMemory] from elsewhere.
  @visibleForTesting
  static set instance(HeavyWork gate) => _instance = gate;

  final Future<DeviceMemory?> Function() _memory;
  final int maxConcurrent;
  final _waiting = Queue<_Job>();
  final _running = <_Job>{};
  bool _admitting = false;

  /// Runs [body] once admitted. Throws [HeavyWorkWithdrawn] when [ticket] was
  /// withdrawn first, [InsufficientMemory] when it can never fit.
  Future<T> run<T>({
    required int estimateBytes,
    required Future<T> Function() body,
    HeavyWorkTicket? ticket,
  }) async {
    final job = _Job(estimateBytes, ticket ?? HeavyWorkTicket());
    if (job.ticket._withdrawn) throw HeavyWorkWithdrawn();
    job.ticket._onWithdraw = () {
      if (job.ticket._started || !_waiting.remove(job)) return;
      job.admitted.completeError(HeavyWorkWithdrawn());
      unawaited(_admit()); // the next one may fit now
    };
    _waiting.add(job);
    unawaited(_admit());
    await job.admitted.future;
    try {
      return await body();
    } finally {
      _running.remove(job);
      unawaited(_admit());
    }
  }

  /// Starts waiting jobs in order while they fit; one at a time, since each
  /// admission reads the memory left after the previous one.
  Future<void> _admit() async {
    if (_admitting) return;
    _admitting = true;
    try {
      while (_waiting.isNotEmpty && _running.length < maxConcurrent) {
        final job = _waiting.first;
        DeviceMemory? memory;
        try {
          memory = await _memory();
        } catch (_) {
          memory = null; // unknown: the count alone applies
        }
        final room = memory == null ? null : _room(memory, except: null);
        // Withdrawn while the memory was read.
        if (_waiting.isEmpty || !identical(_waiting.first, job)) continue;
        if (room != null && job.estimate > room) {
          if (_running.isNotEmpty) return; // admitted when one ends
          _waiting.removeFirst();
          job.admitted.completeError(InsufficientMemory(job.estimate, room));
          continue;
        }
        _waiting.removeFirst();
        job.ticket._started = true;
        _running.add(job);
        job.admitted.complete();
      }
    } finally {
      _admitting = false;
    }
  }

  /// Raises the estimate of the running job [ticket] holds to [estimateBytes]
  /// when that fits now beside the others; false, unchanged, when it does
  /// not. Never waits: a job waiting for room while holding its own could
  /// wait on another doing the same. Unknown memory: true.
  Future<bool> grow(HeavyWorkTicket ticket, int estimateBytes) async {
    final job = _running.where((j) => identical(j.ticket, ticket)).firstOrNull;
    if (job == null) return false;
    if (estimateBytes <= job.estimate) return true;
    DeviceMemory? memory;
    try {
      memory = await _memory();
    } catch (_) {
      memory = null;
    }
    if (memory != null && estimateBytes > _room(memory, except: job)) {
      return false;
    }
    job.estimate = estimateBytes;
    return true;
  }

  /// What a job may use: the platform's figure less its reserve and less
  /// what the running jobs other than [except] are expected to take.
  int _room(DeviceMemory memory, {required _Job? except}) {
    var reserved = 0;
    for (final j in _running) {
      if (!identical(j, except)) reserved += j.estimate;
    }
    return memory.available - memory.reserve - reserved;
  }

  @visibleForTesting
  int get runningCount => _running.length;

  @visibleForTesting
  int get waitingCount => _waiting.length;

  static const _channel = MethodChannel('hayn/metadata');

  static Future<DeviceMemory?> _platformMemory() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('memoryInfo');
      final available = m?['available'], reserve = m?['threshold'];
      if (available is! int || reserve is! int) return null;
      return DeviceMemory(available: available, reserve: reserve);
    } on MissingPluginException {
      return null;
    }
  }
}
