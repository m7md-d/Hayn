import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Trash — assets removed via the surgical-replace flow. Stays restorable for
// a configurable retention window (see settings). The model is local-only;
// nothing leaves the device.
//
// Real persistence (drift / isar) lives in the implementation phase. The
// notifier exposes the methods the UI needs so screens can be built and
// reviewed without the storage layer.
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
  List<TrashItem> build() => const [];

  Future<void> restore(String id) async {
    state = [for (final item in state) if (item.id != id) item];
  }

  Future<void> deleteForever(String id) async {
    state = [for (final item in state) if (item.id != id) item];
  }

  Future<void> emptyAll() async {
    state = const [];
  }
}

final trashProvider =
    NotifierProvider<TrashNotifier, List<TrashItem>>(TrashNotifier.new);
