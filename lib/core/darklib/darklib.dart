import 'dart:typed_data';

import '../diagnostics/media_diagnostics.dart';
import '../../src/rust/api/codec.dart' as rust_codec;
import '../../src/rust/api/inspect.dart' as rust_inspect;
import '../../src/rust/api/metadata.dart' as rust;
import '../../src/rust/api/region.dart' as rust_region;
import '../../src/rust/api/verify.dart' as rust_verify;
import '../../src/rust/engine/codec.dart';
import '../../src/rust/engine/codec/heif_alpha.dart';
import '../../src/rust/engine/inspect.dart';
import '../../src/rust/engine/verify.dart';
import '../../src/rust/frb_generated.dart';

export '../../src/rust/engine/codec.dart' show HdrOutcome, Transcoded;
export '../../src/rust/engine/codec/heif_alpha.dart' show AlphaStream;
export '../../src/rust/api/inspect.dart' show ProfileSpace;
export '../../src/rust/api/region.dart' show RegionReader, RegionTile;
export '../../src/rust/engine/inspect.dart' show Facts, Presence, Transfer;
export '../../src/rust/engine/verify.dart' show AlphaKept;

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
      if (error.startsWith('unsupported:')) {
        MediaDiagnostics.record(
          MediaBackend.darklib,
          operation,
          MediaDiagnosticCode.unsupportedSource,
        );
        return null;
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
  /// The result reports what happened to an HDR gain map. [bitDepth] 8 or 10
  /// is the user's choice for AVIF; 0 keeps DarkLib's default, 10.
  static Future<Transcoded?> transcode(
    Uint8List bytes, {
    required DarkLibFormat format,
    required int quality,
    bool keepMetadata = true,
    int maxEdge = 0,
    int bitDepth = 0,
  }) => _call(
    MediaOperation.encode,
    () => rust_codec.transcode(
      bytes: bytes,
      format: format,
      quality: quality,
      maxEdge: maxEdge,
      keepMetadata: keepMetadata,
      bitDepth: bitDepth,
    ),
    isEmpty: (t) => t.bytes.isEmpty,
  );

  /// The JPEG [bytes] re-encoded at [quality] a band of rows at a time
  /// (RUN-01 step 6): libjpeg-turbo's settings with optimal Huffman tables,
  /// the stored orientation and every metadata segment kept as they are, a
  /// gain map included. Null for a source this path does not take
  /// (`unsupportedSource`: progressive, CMYK…), past the budget, or damaged.
  static Future<Uint8List?> jpegReencode(
    Uint8List bytes, {
    required int quality,
  }) => _call(
    MediaOperation.encode,
    () => rust_codec.jpegReencode(bytes: bytes, quality: quality),
    isEmpty: (b) => b.isEmpty,
  );

  /// Opaque, upright PNG of [bytes] over white (JPEG of a transparent source).
  /// Null when DarkLib is unavailable or cannot decode the container.
  static Future<Uint8List?> flattenOnWhite(Uint8List bytes) => _call(
    MediaOperation.bake,
    () => rust_codec.flattenOnWhite(bytes: bytes),
    isEmpty: (b) => b.isEmpty,
  );

  /// The alpha plane of a HEIF primary image as an HEVC stream for FFmpeg
  /// (IMG-15). Null when DarkLib is unavailable, the layout is unreadable, or
  /// the image has no alpha; check [inspect] first to tell them apart.
  static Future<AlphaStream?> heifAlphaStream(Uint8List bytes) =>
      _call<AlphaStream?>(
        MediaOperation.bake,
        () => rust_codec.heifAlphaStream(bytes: bytes),
      );

  /// [base] (the platform's decode of [source]) with [grey], the stream's
  /// frames decoded to 8-bit grey, as its alpha: an RGBA PNG. Null when the
  /// plane does not fit or DarkLib is unavailable.
  static Future<Uint8List?> heifAttachAlpha({
    required Uint8List source,
    required Uint8List base,
    required Uint8List grey,
  }) => _call(
    MediaOperation.bake,
    () => rust_codec.heifAttachAlpha(source: source, base: base, grey: grey),
    isEmpty: (b) => b.isEmpty,
  );

  /// HDR facts read from the container, without decoding pixels. Null when
  /// DarkLib is unavailable; unreadable containers come back as unknown.
  static Future<Facts?> inspect(Uint8List bytes) => _call(
    MediaOperation.probe,
    () => rust_inspect.inspectImage(bytes: bytes),
  );

  /// The colour profile of [bytes] as an RGB space (D50 matrix and transfer
  /// for Android's `ColorSpace.Rgb`), from an ICC, `nclx` or `cICP`. Null
  /// without a matrix/TRC profile, or when DarkLib is unavailable (IMG-21).
  static Future<rust_inspect.ProfileSpace?> profileSpace(Uint8List bytes) =>
      _call<rust_inspect.ProfileSpace?>(
        MediaOperation.probe,
        () => rust_inspect.profileSpace(bytes: bytes),
      );

  /// Whether [output] keeps the transparency of [source], from decoded alpha
  /// values: a channel whose samples are all opaque is not transparency
  /// (IMG-15). Null when DarkLib is unavailable.
  static Future<AlphaKept?> alphaKept({
    required Uint8List source,
    required Uint8List output,
  }) => _call(
    MediaOperation.probe,
    () => rust_verify.alphaKept(source: source, output: output),
  );

  /// An AVIF read by regions for display (PERF-03), from the file at [path]
  /// (deletable once this returns); one item is decoded whole into raw files
  /// under [cacheDir], gone when the reader is disposed. Null, recorded, for
  /// anything but an SDR AVIF whose colours convert to sRGB here.
  static Future<rust_region.RegionReader?> openRegion({
    required String path,
    required String cacheDir,
  }) => _call(
    MediaOperation.display,
    () => rust_region.RegionReader.open(path: path, cacheDir: cacheDir),
  );

  /// Tiles of [reader] for one row of a view (see `RegionReader.tiles`).
  static Future<List<rust_region.RegionTile>?> regionTiles(
    rust_region.RegionReader reader, {
    required List<int> rect,
    required List<int> cuts,
    required int sample,
  }) => _call(
    MediaOperation.display,
    () => reader.tiles(rect: rect, cuts: cuts, sample: sample),
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
