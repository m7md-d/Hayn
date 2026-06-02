import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../data/index/index_providers.dart';
import '../../../data/index/media_index_database.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TrashRepository — the DATA layer for Surgical Replace's trash + crash-safe
// journal (the `TrashEntries` drift table) plus the byte-for-byte backup files.
//
// This layer is deliberately NON-destructive toward the device gallery: it only
// writes the app-private backup dir and the DB. The actual replace/restore that
// touches user assets lives in the surgical service (its own stage) and drives
// this repository through the journal state machine:
//   insertPending() + writeBackup()   ← before the original is ever touched
//   markCommitted()                    ← after the original is replaced
//   drop()                             ← rollback (deletes row + backup)
// Recovery + retention purge read the journal here and act through the service.
// ─────────────────────────────────────────────────────────────────────────────

/// Journal state of a trash entry. Stored as the int index in `state`.
enum TrashState { pending, committed }

/// Everything the journal needs to record an about-to-happen replacement,
/// captured from the original BEFORE anything is touched.
class TrashDraft {
  const TrashDraft({
    required this.id,
    required this.originalAssetId,
    required this.filename,
    required this.backupPath,
    this.createdDateMs = 0,
    this.modifiedDateMs = 0,
    this.latitude,
    this.longitude,
    this.isFavorite = false,
    this.userAlbumIds = const [],
    this.wasInSmartAlbum = false,
    this.mimeType,
    this.assetType = 1,
    this.width = 0,
    this.height = 0,
    this.originalBytes = 0,
    this.newBytes = 0,
  });

  final String id;
  final String originalAssetId;
  final String filename;
  final String backupPath;
  final int createdDateMs;
  final int modifiedDateMs;
  final double? latitude;
  final double? longitude;
  final bool isFavorite;
  final List<String> userAlbumIds;
  final bool wasInSmartAlbum;
  final String? mimeType;
  final int assetType;
  final int width;
  final int height;
  final int originalBytes;
  final int newBytes;
}

class TrashRepository {
  TrashRepository(this._db);
  final MediaIndexDatabase _db;

  static const _subdir = 'hayn_trash';

  /// App-private backup directory (never in the gallery). Created on demand.
  Future<Directory> _backupDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, _subdir));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Generate a unique entry id (timestamp + counter) — NOT a device asset id.
  static String newId() =>
      'trash-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

  /// Persist the original bytes to the backup dir; returns the absolute path.
  /// This is the byte-for-byte safety copy written BEFORE any replacement.
  Future<String> writeBackup(String entryId, Uint8List bytes,
      {String ext = 'bin'}) async {
    final dir = await _backupDir();
    final file = File(p.join(dir.path, '$entryId.$ext'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Read a backup file's bytes (for restore), or null if it's gone.
  Future<Uint8List?> readBackup(String path) async {
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> _deleteBackupFile(String path) async {
    if (path.isEmpty) return;
    final file = File(path);
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort; a stale backup is harmless.
    }
  }

  // ── Journal writes ────────────────────────────────────────────────────────

  /// Record a `pending` replacement. Call AFTER [writeBackup], BEFORE touching
  /// the original. Committing this row is the crash-safe point.
  Future<void> insertPending(TrashDraft d) async {
    await _db.into(_db.trashEntries).insert(
          TrashEntriesCompanion.insert(
            id: d.id,
            originalAssetId: d.originalAssetId,
            filename: Value(d.filename),
            backupPath: Value(d.backupPath),
            createdDateMs: Value(d.createdDateMs),
            modifiedDateMs: Value(d.modifiedDateMs),
            latitude: Value(d.latitude),
            longitude: Value(d.longitude),
            isFavorite: Value(d.isFavorite),
            userAlbumIds: Value(_encodeIds(d.userAlbumIds)),
            wasInSmartAlbum: Value(d.wasInSmartAlbum),
            mimeType: Value(d.mimeType),
            assetType: Value(d.assetType),
            width: Value(d.width),
            height: Value(d.height),
            originalBytes: Value(d.originalBytes),
            newBytes: Value(d.newBytes),
            state: Value(TrashState.pending.index),
          ),
        );
  }

  /// Flip a pending row to `committed` once the original has been replaced.
  Future<void> markCommitted(
    String id, {
    String? newAssetId,
    int? newBytes,
    int? deletedAtMs,
  }) async {
    await (_db.update(_db.trashEntries)..where((t) => t.id.equals(id))).write(
      TrashEntriesCompanion(
        state: Value(TrashState.committed.index),
        newAssetId: Value(newAssetId),
        newBytes: newBytes == null ? const Value.absent() : Value(newBytes),
        deletedAtMs: Value(
            deletedAtMs ?? DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Drop a row entirely (rollback or restore/delete-forever) + its backup.
  Future<void> drop(String id) async {
    final entry = await byId(id);
    if (entry != null) await _deleteBackupFile(entry.backupPath);
    await (_db.delete(_db.trashEntries)..where((t) => t.id.equals(id))).go();
  }

  // ── Journal reads ─────────────────────────────────────────────────────────

  Future<TrashEntry?> byId(String id) =>
      (_db.select(_db.trashEntries)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// Committed (restorable) items, newest deletion first — drives the screen.
  Future<List<TrashEntry>> listCommitted() => (_db.select(_db.trashEntries)
        ..where((t) => t.state.equals(TrashState.committed.index))
        ..orderBy([(t) => OrderingTerm.desc(t.deletedAtMs)]))
      .get();

  /// Leftover `pending` rows = a replacement interrupted mid-transaction.
  Future<List<TrashEntry>> listPending() => (_db.select(_db.trashEntries)
        ..where((t) => t.state.equals(TrashState.pending.index)))
      .get();

  /// Delete committed entries whose retention window has lapsed (+ backups).
  Future<int> purgeExpired(int retentionDays) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .millisecondsSinceEpoch;
    final expired = await (_db.select(_db.trashEntries)
          ..where((t) =>
              t.state.equals(TrashState.committed.index) &
              t.deletedAtMs.isSmallerThanValue(cutoff) &
              t.deletedAtMs.isBiggerThanValue(0)))
        .get();
    for (final e in expired) {
      await _deleteBackupFile(e.backupPath);
    }
    return (_db.delete(_db.trashEntries)
          ..where((t) =>
              t.state.equals(TrashState.committed.index) &
              t.deletedAtMs.isSmallerThanValue(cutoff) &
              t.deletedAtMs.isBiggerThanValue(0)))
        .go();
  }

  static String _encodeIds(List<String> ids) =>
      ids.isEmpty ? '[]' : '[${ids.map((e) => '"$e"').join(',')}]';

  static List<String> decodeIds(String json) {
    final s = json.trim();
    if (s.length < 2 || s == '[]') return const [];
    final inner = s.substring(1, s.length - 1);
    return [
      for (final part in inner.split(','))
        if (part.trim().length >= 2)
          part.trim().substring(1, part.trim().length - 1),
    ];
  }
}

final trashRepositoryProvider = Provider<TrashRepository>((ref) {
  return TrashRepository(ref.watch(mediaIndexDatabaseProvider));
});
