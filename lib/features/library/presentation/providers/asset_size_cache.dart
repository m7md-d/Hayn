import 'package:photo_manager/photo_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AssetSizeCache — assetId → file byte size. Populated lazily by media
// thumbnails as they mount, and pre-warmed by LibraryNotifier when the
// user picks a size-based sort/filter.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class AssetSizeCache {
  static const _maxEntries = 4000;
  static final _store = <String, int>{};

  static int? get(String id) => _store[id];

  static void put(String id, int bytes) {
    _store.remove(id);
    _store[id] = bytes;
    if (_store.length > _maxEntries) {
      final overflow = _store.length - (_maxEntries - 200);
      final dropKeys = _store.keys.take(overflow).toList();
      for (final k in dropKeys) {
        _store.remove(k);
      }
    }
  }

  /// Loads + caches the size; returns null if the file isn't available.
  static Future<int?> load(AssetEntity asset) async {
    final hit = _store[asset.id];
    if (hit != null) return hit;
    try {
      final file = await asset.file;
      if (file == null) return null;
      final size = await file.length();
      put(asset.id, size);
      return size;
    } catch (_) {
      return null;
    }
  }

  /// Best-effort: fetches sizes for assets in parallel and updates the cache.
  static Future<void> warm(List<AssetEntity> assets) async {
    final missing = assets.where((a) => !_store.containsKey(a.id)).toList();
    if (missing.isEmpty) return;
    await Future.wait(missing.map(load));
  }

  static void clear() => _store.clear();
}
