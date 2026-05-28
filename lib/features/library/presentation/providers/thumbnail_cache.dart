import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ThumbnailCache — in-memory map of asset.id → low-res bytes already loaded
// by MediaThumbnail. AssetDetailScreen paints these immediately so the Hero
// landing never shows a blank frame, then fades in the 1080-px version on
// top once it finishes loading.
//
// LRU-style eviction keeps memory bounded for large libraries. The cap is
// intentionally generous; thumbs are small (~30 KB each).
// ─────────────────────────────────────────────────────────────────────────────

abstract final class ThumbnailCache {
  static const _maxEntries = 240;
  static final _store = <String, Uint8List>{};

  static Uint8List? get(String id) => _store[id];

  static void put(String id, Uint8List bytes) {
    _store.remove(id); // bump to most-recent
    _store[id] = bytes;
    if (_store.length > _maxEntries) {
      // Evict ~10% oldest to amortise cost.
      final overflow = _store.length - (_maxEntries - 24);
      final dropKeys = _store.keys.take(overflow).toList();
      for (final k in dropKeys) {
        _store.remove(k);
      }
    }
  }

  static void clear() => _store.clear();
}
