import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../../core/async/concurrency_limiter.dart';
import '../../../../core/diagnostics/media_diagnostics.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ThumbnailCache — in-memory map of asset.id → low-res bytes already loaded
// by MediaThumbnail. AssetDetailScreen paints these immediately so the Hero
// landing never shows a blank frame, then fades in the 1080-px version on
// top once it finishes loading.
//
// LRU-style eviction keeps memory bounded for large libraries. The cap is
// intentionally generous; thumbs are small (~30 KB each).
//
// `load()` funnels every fetch through a global concurrency limiter so a fast
// fling through thousands of tiles can't flood the platform bridge with
// decode requests. Callers pass a `cancelled` probe (usually `() => !mounted`)
// so a tile that scrolled off before its turn skips the native call.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class ThumbnailCache {
  static const _maxEntries = 240;
  static const thumbSize = ThumbnailSize.square(360);

  static final _store = <String, Uint8List>{};

  // 6 concurrent decodes: enough to keep a scrolling viewport filling quickly,
  // low enough that the native side never backs up. LIFO so on-screen tiles
  // win over ones already scrolled past.
  static final ConcurrencyLimiter _limiter = ConcurrencyLimiter(6);

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

  /// Returns the cached thumbnail or loads it through the limiter. Returns null
  /// if cancelled before the fetch starts or if the platform has no thumbnail.
  /// Platform failures are diagnosed in release and are never cached.
  static Future<Uint8List?> load(
    AssetEntity asset, {
    bool Function()? cancelled,
  }) {
    final hit = _store[asset.id];
    if (hit != null) return Future.value(hit);

    return _limiter.run(() async {
      // Re-check: while we waited for a slot another loader may have filled it,
      // or the requesting tile may have scrolled away.
      final again = _store[asset.id];
      if (again != null) return again;
      if (cancelled?.call() ?? false) return null;

      Uint8List? data;
      try {
        data = await asset.thumbnailDataWithSize(thumbSize);
      } on MissingPluginException {
        MediaDiagnostics.record(
          MediaBackend.gallery,
          MediaOperation.thumbnail,
          MediaDiagnosticCode.unavailable,
        );
        return null;
      } catch (_) {
        // Photos may store a format that its thumbnail service cannot render.
        // Keep the existing placeholder; never leak an unawaited UI exception
        // or cache the failure, so a later request can retry normally.
        MediaDiagnostics.record(
          MediaBackend.gallery,
          MediaOperation.thumbnail,
          MediaDiagnosticCode.exception,
        );
        return null;
      }
      if (data == null || data.isEmpty) {
        MediaDiagnostics.record(
          MediaBackend.gallery,
          MediaOperation.thumbnail,
          MediaDiagnosticCode.emptyOutput,
        );
        return null;
      }
      put(asset.id, data);
      return data;
    });
  }

  static void clear() => _store.clear();
}
