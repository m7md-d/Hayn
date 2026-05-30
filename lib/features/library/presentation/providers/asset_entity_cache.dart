import 'package:photo_manager/photo_manager.dart';

import '../../../../core/async/concurrency_limiter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AssetEntityCache — in-memory id → AssetEntity cache for the virtualized grid.
//
// The grid is driven by the lightweight index "spine" (id + size + type per
// row), so a cell knows what to show before it has an AssetEntity. It then
// materialises the real entity only when it scrolls into view, via
// AssetEntity.fromId — a cheap metadata lookup that never opens a file. Loads
// are bounded + cancellable so a fast fling through thousands of cells can't
// flood the platform bridge.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class AssetEntityCache {
  static const _maxEntries = 600;
  static final _store = <String, AssetEntity>{};

  // LIFO so on-screen cells win over ones already scrolled past.
  static final ConcurrencyLimiter _limiter = ConcurrencyLimiter(8);

  static AssetEntity? get(String id) => _store[id];

  static void put(String id, AssetEntity asset) {
    _store.remove(id); // bump to most-recent
    _store[id] = asset;
    if (_store.length > _maxEntries) {
      final overflow = _store.length - (_maxEntries - 60);
      for (final k in _store.keys.take(overflow).toList()) {
        _store.remove(k);
      }
    }
  }

  /// Returns the cached entity or loads it through the limiter. Returns null if
  /// cancelled before the fetch starts or if the id no longer resolves.
  static Future<AssetEntity?> load(String id, {bool Function()? cancelled}) {
    final hit = _store[id];
    if (hit != null) return Future.value(hit);

    return _limiter.run(() async {
      final again = _store[id];
      if (again != null) return again;
      if (cancelled?.call() ?? false) return null;
      final asset = await AssetEntity.fromId(id);
      if (asset != null) put(id, asset);
      return asset;
    });
  }

  /// Resolve many ids to entities through the limiter, preserving order and
  /// dropping any that no longer exist. Bounded by the shared limiter so even a
  /// 10k "select all" can't stampede the platform bridge. Pass `cancelled` to
  /// bail early (e.g. the screen was dismissed).
  static Future<List<AssetEntity>> loadAll(
    Iterable<String> ids, {
    bool Function()? cancelled,
  }) async {
    final out = <AssetEntity>[];
    final futures = <Future<AssetEntity?>>[
      for (final id in ids) load(id, cancelled: cancelled),
    ];
    for (final f in futures) {
      final a = await f;
      if (a != null) out.add(a);
    }
    return out;
  }

  static void clear() => _store.clear();
}
