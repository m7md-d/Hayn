import 'dart:io';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GallerySaver — writes a processed image as a NEW asset in the device gallery
// (photo_manager's editor). The original is never touched; these ops are
// non-destructive (only Surgical Replace, its own phase, overwrites in place).
//
// The save can carry the source's capture date + GPS so the new copy keeps its
// place in the timeline and its location (EXIF inside the bytes is handled by
// the encoder for the formats that support it).
// ─────────────────────────────────────────────────────────────────────────────

abstract final class GallerySaver {
  /// Returns the new asset, or null if the platform refused the write (e.g.
  /// permission). Never throws.
  static Future<AssetEntity?> saveImage(
    Uint8List bytes, {
    required String filename,
    DateTime? creationDate,
    double? latitude,
    double? longitude,
  }) async {
    try {
      return await PhotoManager.editor.saveImage(
        bytes,
        filename: filename,
        title: filename,
        creationDate: creationDate,
        // Only pass a real fix — 0/null means "unknown", don't stamp (0,0).
        latitude: (latitude != null && latitude != 0) ? latitude : null,
        longitude: (longitude != null && longitude != 0) ? longitude : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Save a video [file] as a NEW gallery asset (used by Duplicate). Returns the
  /// new asset or null. Never throws.
  static Future<AssetEntity?> saveVideo(
    File file, {
    required String filename,
    DateTime? creationDate,
    double? latitude,
    double? longitude,
  }) async {
    try {
      return await PhotoManager.editor.saveVideo(
        file,
        title: filename,
        creationDate: creationDate,
        latitude: (latitude != null && latitude != 0) ? latitude : null,
        longitude: (longitude != null && longitude != 0) ? longitude : null,
      );
    } catch (_) {
      return null;
    }
  }
}
