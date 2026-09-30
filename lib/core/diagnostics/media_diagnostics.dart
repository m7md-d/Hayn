import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

enum MediaBackend {
  taskRunner,
  imageEncoder,
  ffmpeg,
  imageIO,
  androidAvif,
  androidDecoder,
  darklib,
  flutterAvif,
  imageCompress,
  gallery,
}

enum MediaOperation {
  initialize,
  probe,
  encode,
  bake,
  strip,
  transplant,
  task,
  cancel,
  cleanup,
  save,
  thumbnail,
}

enum MediaDiagnosticCode {
  unavailable,
  exception,
  emptyOutput,
  formatFallback,
  preservationUnverified,
  preservationRejected,
  outputFormatMismatch,
  alphaUnverified,
  alphaLost,

  /// JPEG was chosen for a transparent (or unknown) source: composited onto
  /// white by the user's choice (2026-09-29); the user is not warned.
  alphaFlattened,

  /// HDR policy outcomes (user decision 2026-09-28): the saved file is a
  /// correct SDR rendition; the user is not warned.
  hdrToSdr,

  /// The HDR-keeping path failed and the SDR base was saved instead.
  hdrKeepFailed,

  /// PQ/HLG source with no platform tone mapper: refused before any engine.
  hdrToneMapUnavailable,

  /// The source's HDR facts could not be established.
  hdrUnverified,
  incompleteBatch,
  missingResult,

  /// The source's header claims more pixels than the engine decodes; refused
  /// before any pixel buffer (RUN-01).
  tooLarge,
}

/// Codes only: never retain media, paths, asset IDs, metadata or raw exceptions.
class MediaDiagnostic {
  MediaDiagnostic(this.backend, this.operation, this.code)
    : timestamp = DateTime.now().toUtc();

  final DateTime timestamp;
  final MediaBackend backend;
  final MediaOperation operation;
  final MediaDiagnosticCode code;

  @override
  String toString() => '${backend.name}.${operation.name}.${code.name}';
}

class MediaDiagnosticTrace {
  final _events = ListQueue<MediaDiagnostic>();
  List<MediaDiagnostic> get events => List.unmodifiable(_events);

  void _add(MediaDiagnostic event) {
    if (_events.length == MediaDiagnostics.capacity) _events.removeFirst();
    _events.add(event);
  }
}

/// Bounded, in-memory diagnostics in debug AND release. No disk or network I/O.
abstract final class MediaDiagnostics {
  static const capacity = 100;
  static final _history = MediaDiagnosticTrace();
  static final _zoneKey = Object();

  static List<MediaDiagnostic> get recent => _history.events;

  /// Each asynchronous operation owns its trace, even when encodes overlap.
  static Future<T> trace<T>(Future<T> Function(MediaDiagnosticTrace) body) {
    final trace = MediaDiagnosticTrace();
    return runZoned(() => body(trace), zoneValues: {_zoneKey: trace});
  }

  static void record(
    MediaBackend backend,
    MediaOperation operation,
    MediaDiagnosticCode code,
  ) {
    final event = MediaDiagnostic(backend, operation, code);
    _history._add(event);
    (Zone.current[_zoneKey] as MediaDiagnosticTrace?)?._add(event);
    developer.log(event.toString(), name: 'hayn.media', level: 900);
  }
}
