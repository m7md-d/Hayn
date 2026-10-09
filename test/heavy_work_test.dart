import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/isolates/heavy_work.dart';

// RUN-02: full-size image jobs start in order, at most two at once, while
// their memory estimates fit what the platform reports; one that can never fit
// is refused before it starts, and a waiting one can be withdrawn.

const _mb = 1 << 20;

void main() {
  late int available;
  late HeavyWork gate;

  setUp(() {
    available = 1000 * _mb;
    gate = HeavyWork(
      memory: () async =>
          DeviceMemory(available: available, reserve: 100 * _mb),
    );
  });

  /// Starts a job of [mb] whose body waits for the returned completer.
  (Future<String>, Completer<void>) job(
    String name,
    int mb, {
    HeavyWorkTicket? ticket,
    List<String>? started,
  }) {
    final release = Completer<void>();
    final result = gate.run(
      estimateBytes: mb * _mb,
      ticket: ticket,
      body: () async {
        started?.add(name);
        await release.future;
        return name;
      },
    );
    return (result, release);
  }

  test('two at once; the third starts when one ends', () async {
    final started = <String>[];
    final (a, releaseA) = job('a', 10, started: started);
    final (_, releaseB) = job('b', 10, started: started);
    final (c, releaseC) = job('c', 10, started: started);
    await pumpEventQueue();
    expect(started, ['a', 'b']);
    expect(gate.waitingCount, 1);
    releaseA.complete();
    expect(await a, 'a');
    await pumpEventQueue();
    expect(started, ['a', 'b', 'c']);
    releaseB.complete();
    releaseC.complete();
    expect(await c, 'c');
  });

  test('a job that can never fit is refused before it starts', () async {
    final started = <String>[];
    final (big, _) = job('big', 2000, started: started);
    await expectLater(big, throwsA(isA<InsufficientMemory>()));
    expect(started, isEmpty);
  });

  test('one that fits once the running job ends waits for it', () async {
    final started = <String>[];
    final (_, releaseA) = job('a', 500, started: started);
    await pumpEventQueue();
    available = 400 * _mb; // a's memory is in use
    final (b, releaseB) = job('b', 600, started: started);
    await pumpEventQueue();
    expect(started, ['a']);
    available = 1000 * _mb;
    releaseA.complete();
    await pumpEventQueue();
    expect(started, ['a', 'b']);
    releaseB.complete();
    expect(await b, 'b');
  });

  test('a small job does not overtake a large one waiting', () async {
    final started = <String>[];
    final (_, releaseA) = job('a', 500, started: started);
    await pumpEventQueue();
    available = 400 * _mb;
    final (_, releaseB) = job('b', 600, started: started);
    final (_, releaseC) = job('c', 10, started: started);
    await pumpEventQueue();
    expect(started, ['a']);
    available = 1000 * _mb;
    releaseA.complete();
    await pumpEventQueue();
    expect(started, ['a', 'b', 'c']);
    releaseB.complete();
    releaseC.complete();
  });

  test('a withdrawn job never runs; a started one is not stopped', () async {
    final started = <String>[];
    final first = HeavyWorkTicket();
    final (a, releaseA) = job('a', 10, ticket: first, started: started);
    final (_, releaseB) = job('b', 10, started: started);
    final third = HeavyWorkTicket();
    final (c, _) = job('c', 10, ticket: third, started: started);
    await pumpEventQueue();
    final refused = expectLater(c, throwsA(isA<HeavyWorkWithdrawn>()));
    first.withdraw(); // started: runs to its end
    third.withdraw();
    releaseA.complete();
    expect(await a, 'a');
    await refused;
    expect(started, ['a', 'b']);
    expect(third.started, isFalse);
    releaseB.complete();
  });

  test('unknown memory: only the count applies', () async {
    gate = HeavyWork(memory: () async => null);
    final started = <String>[];
    final (a, releaseA) = job('a', 1 << 20, started: started);
    await pumpEventQueue();
    expect(started, ['a']);
    releaseA.complete();
    expect(await a, 'a');
    gate = HeavyWork(memory: () => Future.error(StateError('no channel')));
    final (b, releaseB) = job('b', 1 << 20, started: started);
    await pumpEventQueue();
    releaseB.complete();
    expect(await b, 'b');
  });

  test('withdrawn from the middle of the queue, it leaves at once', () async {
    final started = <String>[];
    final (_, releaseA) = job('a', 10, started: started);
    final (_, releaseB) = job('b', 10, started: started);
    final ticket = HeavyWorkTicket();
    final (c, _) = job('c', 10, ticket: ticket, started: started);
    final (d, releaseD) = job('d', 10, started: started);
    await pumpEventQueue();
    final refused = expectLater(c, throwsA(isA<HeavyWorkWithdrawn>()));
    ticket.withdraw();
    await refused;
    expect(gate.waitingCount, 1, reason: 'd still waits for a or b');
    releaseA.complete();
    await pumpEventQueue();
    expect(started, ['a', 'b', 'd']);
    releaseB.complete();
    releaseD.complete();
    expect(await d, 'd');
  });

  test('a failing job frees its place', () async {
    final failing = gate.run<void>(
      estimateBytes: 10 * _mb,
      body: () => Future.error(StateError('encode failed')),
    );
    await expectLater(failing, throwsStateError);
    expect(gate.runningCount, 0);
  });

  test('a job admitted a moment ago keeps its room before it allocates '
      '(RV-03)', () async {
    // 900 MB to use, the platform's figure unchanged until a job allocates:
    // two jobs of 700 MB must not both start.
    final started = <String>[];
    final (a, releaseA) = job('a', 700, started: started);
    final (b, releaseB) = job('b', 700, started: started);
    await pumpEventQueue();
    expect(started, ['a'], reason: '700 + 700 does not fit in 900');
    releaseA.complete();
    expect(await a, 'a');
    await pumpEventQueue();
    expect(started, ['a', 'b']);
    releaseB.complete();
    expect(await b, 'b');
  });

  test('a running job grows only into room beside the others', () async {
    final ticket = HeavyWorkTicket();
    final (a, releaseA) = job('a', 100, ticket: ticket);
    final (_, releaseB) = job('b', 300);
    await pumpEventQueue();
    // 900 to use: b holds 300, so a may take up to 600, not 700.
    expect(await gate.grow(ticket, 700 * _mb), isFalse);
    expect(await gate.grow(ticket, 600 * _mb), isTrue);
    // Now a holds 600: a third job of 100 waits.
    final started = <String>[];
    final (c, releaseC) = job('c', 100, started: started);
    releaseB.complete();
    await pumpEventQueue();
    expect(started, ['c'], reason: 'b ended: 600 + 100 fits');
    expect(
      await gate.grow(HeavyWorkTicket(), 10),
      isFalse,
      reason: 'not a running job',
    );
    releaseA.complete();
    releaseC.complete();
    expect(await a, 'a');
    expect(await c, 'c');
  });
}
