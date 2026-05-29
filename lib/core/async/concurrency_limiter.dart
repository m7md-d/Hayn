import 'dart:async';
import 'dart:collection';

// ─────────────────────────────────────────────────────────────────────────────
// ConcurrencyLimiter — caps how many async operations run at once.
//
// Why it exists: a fast fling through a 10k-item media grid mounts hundreds of
// tiles in a second. If every tile fires its own native thumbnail / file call
// with no ceiling, the platform bridge floods, the queue never drains, and the
// UI stalls. This bounds the in-flight work to a sane number; the rest waits.
//
// Policy: [lifo] (default true) serves the *most recently* requested work
// first — exactly right for scrolling. The tiles on screen *now* jump ahead of
// the ones the user already scrolled past, so what you're looking at fills in
// first. Pair it with a cancellation check inside the task so work for tiles
// that scrolled away is skipped cheaply when its turn finally comes.
// ─────────────────────────────────────────────────────────────────────────────

class ConcurrencyLimiter {
  ConcurrencyLimiter(this.maxConcurrent, {this.lifo = true})
      : assert(maxConcurrent > 0, 'maxConcurrent must be > 0');

  final int maxConcurrent;
  final bool lifo;

  int _active = 0;
  final DoubleLinkedQueue<Completer<void>> _waiting = DoubleLinkedQueue();

  /// Operations currently executing.
  int get active => _active;

  /// Operations queued, waiting for a free slot.
  int get pending => _waiting.length;

  /// Runs [task] once a slot is free, releasing the slot when it settles
  /// (success or error). The slot is always released, so a throwing task can't
  /// permanently shrink the pool.
  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < maxConcurrent) {
      _active++;
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiting.isEmpty) {
      _active--; // pool shrinks back toward idle
      return;
    }
    // A waiter is promoted into the slot we just vacated, so _active stays
    // pinned at the cap. LIFO hands it to the newest requester.
    final next = lifo ? _waiting.removeLast() : _waiting.removeFirst();
    next.complete();
  }
}
