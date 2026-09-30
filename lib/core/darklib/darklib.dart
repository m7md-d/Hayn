import 'dart:typed_data';

import '../diagnostics/media_diagnostics.dart';
import '../../src/rust/api/codec.dart' as rust_codec;
import '../../src/rust/api/inspect.dart' as rust_inspect;
import '../../src/rust/api/metadata.dart' as rust;
import '../../src/rust/engine/codec.dart';
import '../../src/rust/engine/inspect.dart';
import '../../src/rust/frb_generated.dart';

export '../../src/rust/engine/codec.dart' show HdrOutcome, Transcoded;
export '../../src/rust/engine/inspect.dart' show Facts, Presence, Transfer;

/// Encode targets DarkLib can produce (mirrors the Rust `CodecFormat`).
typedef DarkLibFormat = rust_codec.CodecFormat;

/// Thin, lazily initialized bridge. Operational errors return null; a preservation
/// veto throws DarkLibPreservationFailure and must never trigger fallback. A bounded
/// diagnostic records why in release too. Non-empty bytes are NOT a verified
/// preservation result: Rust-side colour/HDR validation remains phase B work.
abstract final class DarkLibCore {
  static Future<bool>? _ready;

  static Future<bool> ensureReady() => _ready ??= _init();

  static Future<bool> _init() async {
    try {
      if (!DarkLib.instance.initialized) await DarkLib.init();
      return true;
    } catch (_) {
      MediaDiagnostics.record(
        MediaBackend.darklib,
        MediaOperation.initialize,
        MediaDiagnosticCode.exception,
      );
      return false;
    }
  }

  static Future<T?> _call<T>(
    MediaOperation operation,
    Future<T> Function() body, {
    bool Function(T)? isEmpty,
  }) async {
    if (!await ensureReady()) {
      MediaDiagnostics.record(
        MediaBackend.darklib,
        operation,
        MediaDiagnosticCode.unavailable,
      );
      return null;
    }
    try {
      final result = await body();
      if (isEmpty?.call(result) ?? false) {
        MediaDiagnostics.record(
          MediaBackend.darklib,
          operation,
          MediaDiagnosticCode.emptyOutput,
        );
        return null;
      }
      return result;
    } on String catch (error) {
      // The generated Result<Vec<u8>, String> decoder throws a Dart String.
      if (error.startsWith('preservation_required:')) {
        MediaDiagnostics.record(
          MediaBackend.darklib,
          operation,
          MediaDiagnosticCode.preservationRejected,
        );
        throw const DarkLibPreservationFailure();
      }
      if (error == 'too_large') {
        MediaDiagnostics.record(
          MediaBackend.darklib,
          operation,
          MediaDiagnosticCode.tooLarge,
        );
        return null;
      }
      MediaDiagnostics.record(
        MediaBackend.darklib,
        operation,
        MediaDiagnosticCode.exception,
      );
      return null;
    } catch (_) {
      MediaDiagnostics.record(
        MediaBackend.darklib,
        operation,
        MediaDiagnosticCode.exception,
      );
      return null;
    }
  }

  /// Container edit without re-encoding. Correct display/auxiliary references
  /// still need the independent checks listed in docs/12-STABILIZATION.md.
  static Future<Uint8List?> stripMetadata(
    Uint8List bytes, {
    bool stripIcc = false,
  }) => _call(
    MediaOperation.strip,
    () => rust.stripMetadata(bytes: bytes, stripIcc: stripIcc),
    isEmpty: (b) => b.isEmpty,
  );

  /// Uses the existing Rust codecs. keepMetadata is a request, not proof of
  /// semantic preservation. maxEdge > 0 permits downscaling in that backend.
  /// The result reports what happened to an HDR gain map.
  static Future<Transcoded?> transcode(
    Uint8List bytes, {
    required DarkLibFormat format,
    required int quality,
    bool keepMetadata = true,
    int maxEdge = 0,
  }) => _call(
    MediaOperation.encode,
    () => rust_codec.transcode(
      bytes: bytes,
      format: format,
      quality: quality,
      maxEdge: maxEdge,
      keepMetadata: keepMetadata,
    ),
    isEmpty: (t) => t.bytes.isEmpty,
  );

  /// Opaque, upright PNG of [bytes] over white (JPEG of a transparent source).
  /// Null when DarkLib is unavailable or cannot decode the container.
  static Future<Uint8List?> flattenOnWhite(Uint8List bytes) => _call(
    MediaOperation.bake,
    () => rust_codec.flattenOnWhite(bytes: bytes),
    isEmpty: (b) => b.isEmpty,
  );

  /// HDR facts read from the container, without decoding pixels. Null when
  /// DarkLib is unavailable; unreadable containers come back as unknown.
  static Future<Facts?> inspect(Uint8List bytes) => _call(
    MediaOperation.probe,
    () => rust_inspect.inspectImage(bytes: bytes),
  );

  /// Best-effort metadata transfer. Rust may return an unchanged target without
  /// an error; this facade cannot yet distinguish that from a verified transfer.
  static Future<Uint8List?> transplantMetadata({
    required Uint8List source,
    required Uint8List target,
  }) => _call(
    MediaOperation.transplant,
    () => rust.transplantMetadata(source: source, target: target),
    isEmpty: (b) => b.isEmpty,
  );
}

/// Terminal veto from the current String-error FFI. No source data is retained.
class DarkLibPreservationFailure implements Exception {
  const DarkLibPreservationFailure();
  @override
  String toString() => 'Image preservation requirements could not be met';
}
