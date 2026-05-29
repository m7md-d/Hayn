// ─────────────────────────────────────────────────────────────────────────────
// AssetSizeCache — in-memory assetId → byte size, read synchronously by the
// grid badge. It is a PURE cache: it never touches `asset.file` (which on iOS
// exports a full copy of the original just to read its length — the cause of
// runaway storage growth while scrolling). Sizes are seeded exclusively from
// the on-device index, which resolves them cheaply via the native size channel
// (MediaStore._size / PHAssetResource.fileSize).
// ─────────────────────────────────────────────────────────────────────────────

abstract final class AssetSizeCache {
  static const _maxEntries = 12000;
  static final _store = <String, int>{};

  static int? get(String id) => _store[id];

  static void put(String id, int bytes) {
    _store.remove(id); // bump to most-recent
    _store[id] = bytes;
    if (_store.length > _maxEntries) {
      final overflow = _store.length - (_maxEntries - 500);
      final dropKeys = _store.keys.take(overflow).toList();
      for (final k in dropKeys) {
        _store.remove(k);
      }
    }
  }

  static void putAll(Map<String, int> sizes) {
    for (final e in sizes.entries) {
      put(e.key, e.value);
    }
  }

  static void clear() => _store.clear();
}
