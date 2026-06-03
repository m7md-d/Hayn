import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/index/media_index_database.dart';
import '../../image_ops/data/gallery_saver.dart';
import '../data/trash_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Trash — originals kept restorable for a retention window. Local-only; nothing
// leaves the device. Backed by the drift TrashEntries table + byte-for-byte
// backup files (TrashRepository). Reusable infrastructure: the upcoming compress
// option "delete the original after compressing" moves originals here, and
// restore re-creates them in the gallery from the backup.
// ─────────────────────────────────────────────────────────────────────────────

class TrashItem {
  const TrashItem({
    required this.id,
    required this.filename,
    required this.deletedAt,
    required this.originalBytes,
    required this.backupPath,
    this.width = 0,
    this.height = 0,
    this.mimeType,
    this.assetType = TrashAssetType.image,
  });

  final String id;
  final String filename;
  final DateTime deletedAt;
  final int originalBytes;

  /// Absolute path to the backed-up bytes — drives the thumbnail + preview.
  final String backupPath;
  final int width;
  final int height;
  final String? mimeType;
  final TrashAssetType assetType;

  /// Days remaining until permanent deletion at the given retention setting.
  int daysRemaining(int retentionDays) {
    final cutoff = deletedAt.add(Duration(days: retentionDays));
    return cutoff.difference(DateTime.now()).inDays.clamp(0, retentionDays);
  }
}

enum TrashAssetType { image, video }

class TrashNotifier extends Notifier<List<TrashItem>> {
  @override
  List<TrashItem> build() {
    unawaited(_load());
    return const [];
  }

  Future<void> _load() async {
    final entries = await ref.read(trashRepositoryProvider).listCommitted();
    state = [for (final e in entries) _toItem(e)];
  }

  /// Re-create the trashed original in the gallery from its byte-for-byte
  /// backup (the un-delete for the future compress "delete original" option),
  /// then drop the entry. Returns false if the backup was gone or the save was
  /// refused (the entry stays so it isn't lost).
  Future<bool> restore(String id) async {
    final repo = ref.read(trashRepositoryProvider);
    final entry = await repo.byId(id);
    if (entry == null) {
      await _load();
      return false;
    }
    final bytes = await repo.readBackup(entry.backupPath);
    var ok = false;
    if (bytes != null) {
      final asset = await GallerySaver.saveImage(
        bytes,
        filename: entry.filename.isEmpty ? 'restored' : entry.filename,
        creationDate: entry.createdDateMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(entry.createdDateMs)
            : null,
        latitude: entry.latitude,
        longitude: entry.longitude,
      );
      if (asset != null) {
        await repo.drop(id);
        ok = true;
      }
    }
    await _load();
    return ok;
  }

  /// Purge the entry + its backup file permanently.
  Future<void> deleteForever(String id) async {
    await ref.read(trashRepositoryProvider).drop(id);
    await _load();
  }

  Future<void> emptyAll() async {
    final repo = ref.read(trashRepositoryProvider);
    for (final e in await repo.listCommitted()) {
      await repo.drop(e.id);
    }
    await _load();
  }

  static TrashItem _toItem(TrashEntry e) => TrashItem(
        id: e.id,
        filename: e.filename.isEmpty ? 'IMG' : e.filename,
        deletedAt: DateTime.fromMillisecondsSinceEpoch(
          e.deletedAtMs == 0
              ? DateTime.now().millisecondsSinceEpoch
              : e.deletedAtMs,
        ),
        originalBytes: e.originalBytes,
        backupPath: e.backupPath,
        width: e.width,
        height: e.height,
        mimeType: e.mimeType,
        assetType:
            e.assetType == 2 ? TrashAssetType.video : TrashAssetType.image,
      );
}

final trashProvider =
    NotifierProvider<TrashNotifier, List<TrashItem>>(TrashNotifier.new);
