import 'dart:typed_data';

import '../../src/rust/api/codec.dart' as rust_codec;
import '../../src/rust/api/metadata.dart' as rust;
import '../../src/rust/frb_generated.dart';

/// Encode targets DarkLib can produce (mirrors the Rust `CodecFormat`).
typedef DarkLibFormat = rust_codec.CodecFormat;

// ─────────────────────────────────────────────────────────────────────────────
// DarkLibCore — thin Dart facade over the DarkLib Rust core (see
// docs/10-DARKLIB.md). All heavy work runs in Rust, off the Dart isolate.
//
// The native library is initialised once, lazily, on first use. DarkLib is
// NEVER a hard dependency: if init or any call fails (older build, missing .so,
// unsupported container) the facade degrades to null/false so callers fall back
// to the legacy Dart/iOS paths. This is how the migration stays safe (CLAUDE.md
// §7 — no silent failures, but graceful fallback).
// ─────────────────────────────────────────────────────────────────────────────

abstract final class DarkLibCore {
  static Future<bool>? _ready;

  /// Initialise the native library once. Never throws; returns whether DarkLib
  /// is usable on this build/device.
  static Future<bool> ensureReady() => _ready ??= _init();

  static Future<bool> _init() async {
    try {
      await DarkLib.init();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Strip metadata losslessly (no re-encode), keeping the ICC colour profile by
  /// default. Handles JPEG/PNG/WebP and — unlike the legacy paths on Android —
  /// AVIF/HEIF. Returns null when DarkLib is unavailable or can't safely handle
  /// the container (the caller then falls back). Never throws.
  static Future<Uint8List?> stripMetadata(
    Uint8List bytes, {
    bool stripIcc = false,
  }) async {
    if (!await ensureReady()) return null;
    try {
      return await rust.stripMetadata(bytes: bytes, stripIcc: stripIcc);
    } catch (_) {
      return null; // unsupported container / malformed → fall back
    }
  }

  /// Convert [bytes] to [format] at [quality] (1–100), carrying EXIF/XMP/ICC
  /// (and, for a full-size AVIF→AVIF convert, the HDR gain map) when
  /// [keepMetadata] is set. Source must be a container DarkLib decodes
  /// (JPEG/PNG/WebP/AVIF — NOT HEIC); huge opaque AVIF outputs tile
  /// automatically. [maxEdge] > 0 downscales (previews only). Returns null on
  /// any failure so the caller falls back to a platform encoder. Never throws.
  static Future<Uint8List?> transcode(
    Uint8List bytes, {
    required DarkLibFormat format,
    required int quality,
    bool keepMetadata = true,
    int maxEdge = 0,
  }) async {
    if (!await ensureReady()) return null;
    try {
      final out = keepMetadata
          ? await rust_codec.transcodeKeepMetadata(
              bytes: bytes,
              format: format,
              quality: quality,
              maxEdge: maxEdge,
            )
          : await rust_codec.transcode(
              bytes: bytes,
              format: format,
              quality: quality,
              maxEdge: maxEdge,
            );
      return out.isEmpty ? null : out;
    } catch (_) {
      return null; // undecodable source (e.g. HEIC) / failure → fall back
    }
  }

  /// Copy [source]'s metadata (EXIF/XMP/ICC) into the already-encoded [target]
  /// by lossless container surgery — e.g. give a hardware encoder's AVIF the
  /// camera metadata the platform encoder can't write. Returns [target]
  /// unchanged when nothing could be carried safely, or null when DarkLib is
  /// unavailable. Never throws.
  static Future<Uint8List?> transplantMetadata({
    required Uint8List source,
    required Uint8List target,
  }) async {
    if (!await ensureReady()) return null;
    try {
      return await rust.transplantMetadata(source: source, target: target);
    } catch (_) {
      return null;
    }
  }
}
