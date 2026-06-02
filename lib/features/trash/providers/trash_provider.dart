import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/index/media_index_database.dart';
import '../../surgical/data/surgical_replace_service.dart';
import '../data/trash_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Trash — originals replaced via Surgical Replace, restorable for the retention
// window (see settings). Local-only; nothing leaves the device. Backed by the
// drift TrashEntries table (= the crash-safe journal): committed rows are the
// trash list; restore rewrites the byte-for-byte backup over the asset.
// ─────────────────────────────────────────────────────────────────────────────

class TrashItem {
  const TrashItem({
    required this.id,
    required this.filename,
    required this.deletedAt,
    required this.originalBytes,
    this.thumbnail,
    this.assetType = TrashAssetType.image,
  });

  final String id;
  final String filename;
  final DateTime deletedAt;
  final int originalBytes;
  final Uint8List? thumbnail;
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

  /// Rewrite the byte-for-byte backup over the asset, then drop the entry.
  Future<void> restore(String id) async {
    final entry = await ref.read(trashRepositoryProvider).byId(id);
    if (entry != null) {
      await ref.read(surgicalReplaceServiceProvider).restore(entry);
    }
    await _load();
  }

  /// Purge the entry + its backup file permanently (the asset stays as-is).
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
        assetType:
            e.assetType == 2 ? TrashAssetType.video : TrashAssetType.image,
      );
}

final trashProvider =
    NotifierProvider<TrashNotifier, List<TrashItem>>(TrashNotifier.new);
