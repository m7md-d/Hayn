import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';

void main() {
  test('history is bounded, immutable, and stores only classified events', () {
    for (var i = 0; i < 130; i++) {
      MediaDiagnostics.record(
        MediaBackend.darklib,
        MediaOperation.encode,
        MediaDiagnosticCode.emptyOutput,
      );
    }
    final snapshot = MediaDiagnostics.recent;
    expect(snapshot, hasLength(100));
    expect(() => snapshot.clear(), throwsUnsupportedError);
    expect(snapshot.last.toString(), 'darklib.encode.emptyOutput');
    MediaDiagnostics.record(
      MediaBackend.gallery,
      MediaOperation.save,
      MediaDiagnosticCode.exception,
    );
    expect(snapshot.last.backend, MediaBackend.darklib);
  });

  test(
    'interleaved operations own separate immutable diagnostic traces',
    () async {
      final started = Completer<void>();
      final resume = Completer<void>();
      final first = MediaDiagnostics.trace((trace) async {
        MediaDiagnostics.record(
          MediaBackend.darklib,
          MediaOperation.encode,
          MediaDiagnosticCode.exception,
        );
        started.complete();
        await resume.future;
        MediaDiagnostics.record(
          MediaBackend.imageIO,
          MediaOperation.bake,
          MediaDiagnosticCode.unavailable,
        );
        return trace.events;
      });
      await started.future;
      final second = await MediaDiagnostics.trace((trace) async {
        MediaDiagnostics.record(
          MediaBackend.androidAvif,
          MediaOperation.probe,
          MediaDiagnosticCode.unavailable,
        );
        return trace.events;
      });
      resume.complete();
      expect((await first).map((e) => e.backend), [
        MediaBackend.darklib,
        MediaBackend.imageIO,
      ]);
      expect(second.single.backend, MediaBackend.androidAvif);
    },
  );
}
