import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/async/concurrency_limiter.dart';

void main() {
  group('ConcurrencyLimiter', () {
    test('never exceeds maxConcurrent and runs every task', () async {
      final limiter = ConcurrencyLimiter(3);
      var active = 0;
      var peak = 0;
      var done = 0;

      final tasks = <Future<void>>[
        for (var i = 0; i < 20; i++)
          limiter.run(() async {
            active++;
            if (active > peak) peak = active;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            active--;
            done++;
          }),
      ];

      await Future.wait(tasks);

      expect(peak, lessThanOrEqualTo(3));
      expect(done, 20);
      expect(limiter.active, 0);
      expect(limiter.pending, 0);
    });

    test('LIFO serves the most recently queued task first', () async {
      final limiter = ConcurrencyLimiter(1); // lifo defaults to true
      final order = <String>[];
      final gate = Completer<void>();

      // A grabs the only slot and holds it until we open the gate.
      final a = limiter.run(() async {
        order.add('A-start');
        await gate.future;
        order.add('A-end');
      });
      await Future<void>.delayed(Duration.zero); // let A actually start

      // B then C queue behind A.
      final b = limiter.run(() async => order.add('B'));
      final c = limiter.run(() async => order.add('C'));

      gate.complete();
      await Future.wait([a, b, c]);

      // A was already running; the queue drains newest-first → C before B.
      expect(order, ['A-start', 'A-end', 'C', 'B']);
    });

    test('FIFO mode drains oldest-first', () async {
      final limiter = ConcurrencyLimiter(1, lifo: false);
      final order = <String>[];
      final gate = Completer<void>();

      final a = limiter.run(() async {
        await gate.future;
      });
      await Future<void>.delayed(Duration.zero);

      final b = limiter.run(() async => order.add('B'));
      final c = limiter.run(() async => order.add('C'));

      gate.complete();
      await Future.wait([a, b, c]);

      expect(order, ['B', 'C']);
    });

    test('a throwing task still releases its slot', () async {
      final limiter = ConcurrencyLimiter(1);

      await expectLater(
        limiter.run(() async => throw StateError('boom')),
        throwsStateError,
      );

      var ran = false;
      await limiter.run(() async => ran = true);
      expect(ran, true);
      expect(limiter.active, 0);
    });

    test('rejects a non-positive ceiling', () {
      expect(() => ConcurrencyLimiter(0), throwsA(isA<AssertionError>()));
    });
  });
}
