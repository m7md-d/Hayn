import 'dart:typed_data';

import '../diagnostics/media_diagnostics.dart';
import '../../src/rust/api/codec.dart' as rust_codec;
import '../../src/rust/api/metadata.dart' as rust;
import '../../src/rust/frb_generated.dart';

/// Encode targets DarkLib can produce (mirrors the Rust `CodecFormat`).
typedef DarkLibFormat = rust_codec.CodecFormat;

/// Thin, lazily initialized bridge. Null means fallback is needed; a bounded
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

  static Future<Uint8List?> _call(
    MediaOperation operation,
    Future<Uint8List> Function() body,
  ) async {
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
      if (result.isEmpty) {
        MediaDiagnostics.record(
          MediaBackend.darklib,
          operation,
          MediaDiagnosticCode.emptyOutput,
        );
        return null;
      }
      return result;
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
  );

  /// Uses the existing Rust codecs. keepMetadata is a request, not proof of
  /// semantic preservation. maxEdge > 0 permits downscaling in that backend.
  static Future<Uint8List?> transcode(
    Uint8List bytes, {
    required DarkLibFormat format,
    required int quality,
    bool keepMetadata = true,
    int maxEdge = 0,
  }) => _call(
    MediaOperation.encode,
    () => keepMetadata
        ? rust_codec.transcodeKeepMetadata(
            bytes: bytes,
            format: format,
            quality: quality,
            maxEdge: maxEdge,
          )
        : rust_codec.transcode(
            bytes: bytes,
            format: format,
            quality: quality,
            maxEdge: maxEdge,
          ),
  );

  /// Best-effort metadata transfer. Rust may return an unchanged target without
  /// an error; this facade cannot yet distinguish that from a verified transfer.
  static Future<Uint8List?> transplantMetadata({
    required Uint8List source,
    required Uint8List target,
  }) => _call(
    MediaOperation.transplant,
    () => rust.transplantMetadata(source: source, target: target),
  );
}
