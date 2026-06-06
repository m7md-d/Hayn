import 'package:flutter/foundation.dart';

import '../../src/rust/api/metadata.dart' as rust;
import '../../src/rust/frb_generated.dart';

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
      if (kDebugMode) debugPrint('[DarkLib] init OK');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[DarkLib] init FAILED: $e');
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
    } catch (e) {
      if (kDebugMode) debugPrint('[DarkLib] strip threw: $e');
      return null; // unsupported container / malformed → fall back
    }
  }
}
