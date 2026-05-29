import 'package:photo_manager/photo_manager.dart';
import '../../../../core/async/concurrency_limiter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AssetSizeCache — assetId → file byte size. Populated lazily by media
// thumbnails as they mount, and pre-warmed by LibraryNotifier when the
// user picks a size-based sort/filter.
//
// Reading a byte size means materialising the origin file (`asset.file`),
// which on some platforms copies/exports the whole file — far heavier than a
// thumbnail. So every read funnels through its own limiter with a *low* ceiling
// (3): even sorting a 10k library by size can't fan out into thousands of
// parallel file exports. `warm()` inherits the same bound for free because it
// just calls `load()` for each asset.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class AssetSizeCache {
  static const _maxEntries = 4000;
  static final _store = <String, int>{};

  // Heavier than thumbnails → keep the ceiling low. LIFO so a visible tile's
  // size resolves ahead of a bulk warm still draining in the background.
  static final ConcurrencyLimiter _limiter = ConcurrencyLimiter(3);

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

  /// Loads + caches the size through the limiter; returns null if the file
  /// isn't available or the caller cancelled before the read started.
  static Future<int?> load(
    AssetEntity asset, {
    bool Function()? cancelled,
  }) {
    final hit = _store[asset.id];
    if (hit != null) return Future.value(hit);

    return _limiter.run(() async {
      final again = _store[asset.id];
      if (again != null) return again;
      if (cancelled?.call() ?? false) return null;
      try {
        final file = await asset.file;
        if (file == null) return null;
        final size = await file.length();
        put(asset.id, size);
        return size;
      } catch (_) {
        return null;
      }
    });
  }

  /// Best-effort: fetches sizes for the missing assets and updates the cache.
  /// Concurrency is bounded by the limiter inside [load], so this is safe to
  /// call on a full page of assets without flooding the platform.
  static Future<void> warm(List<AssetEntity> assets) async {
    final missing = assets.where((a) => !_store.containsKey(a.id)).toList();
    if (missing.isEmpty) return;
    await Future.wait(missing.map((a) => load(a)));
  }

  static void clear() => _store.clear();
}
