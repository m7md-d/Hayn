import 'dart:io';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import '../../../core/diagnostics/media_diagnostics.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GallerySaver — writes a processed image as a NEW asset in the device gallery
// (photo_manager's editor). The original is never touched; these ops are
// non-destructive; replacement of the original is outside this service.
//
// The save can carry the source's capture date + GPS so the new copy keeps its
// place in the timeline and its location (EXIF inside the bytes is handled by
// the encoder for the formats that support it).
// ─────────────────────────────────────────────────────────────────────────────

abstract final class GallerySaver {
  /// The source's location to stamp, or null when it has none. photo_manager
  /// reports none as (0, 0) on iOS (`PHAsset.location` nil) and null on
  /// Android 10+, and stamps a location only from both values. A zero on one
  /// axis is a real place, the equator or Greenwich (RV-06).
  static ({double latitude, double longitude})? location(
    double? latitude,
    double? longitude,
  ) {
    if (latitude == null || longitude == null) return null;
    if (latitude == 0 && longitude == 0) return null;
    if (!(latitude.abs() <= 90 && longitude.abs() <= 180)) return null; // NaN
    return (latitude: latitude, longitude: longitude);
  }

  /// Returns the new asset, or null if the platform refused the write (e.g.
  /// permission). Never throws.
  static Future<AssetEntity?> saveImage(
    Uint8List bytes, {
    required String filename,
    DateTime? creationDate,
    double? latitude,
    double? longitude,
  }) async {
    final at = location(latitude, longitude);
    try {
      return await PhotoManager.editor.saveImage(
        bytes,
        filename: filename,
        title: filename,
        creationDate: creationDate,
        latitude: at?.latitude,
        longitude: at?.longitude,
      );
    } catch (_) {
      MediaDiagnostics.record(
        MediaBackend.gallery,
        MediaOperation.save,
        MediaDiagnosticCode.exception,
      );
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
    final at = location(latitude, longitude);
    try {
      return await PhotoManager.editor.saveVideo(
        file,
        title: filename,
        creationDate: creationDate,
        latitude: at?.latitude,
        longitude: at?.longitude,
      );
    } catch (_) {
      MediaDiagnostics.record(
        MediaBackend.gallery,
        MediaOperation.save,
        MediaDiagnosticCode.exception,
      );
      return null;
    }
  }
}
