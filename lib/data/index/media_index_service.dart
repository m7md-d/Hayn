import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:photo_manager/photo_manager.dart';

import 'media_index_database.dart';
import 'media_size_channel.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MediaIndexService — keeps the on-device index in step with the real library.
//
//  • syncMetadata(): batched enumerate → upsert metadata → delete rows whose
//    assets vanished. Cheap fields only; never opens a file. Re-running is
//    idempotent and PRESERVES already-resolved byte sizes (the size pass owns
//    that column).
//  • resolveSizes(): fills the missing `sizeBytes` — native batch first
//    (MediaSizeChannel), the slow per-file fallback only for the leftovers,
//    bounded so it can never stampede the platform.
//
// The asset source is abstracted so the heavy logic is unit-testable without a
// device; production wires it to photo_manager.
// ─────────────────────────────────────────────────────────────────────────────

abstract interface class AssetMetadataSource {
  Future<int> count();
  Future<List<AssetEntity>> range(int start, int end);
}

class PhotoManagerAssetSource implements AssetMetadataSource {
  AssetPathEntity? _all;

  Future<AssetPathEntity?> _allPath() async {
    final cached = _all;
    if (cached != null) return cached;
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: true,
      onlyAll: true,
    );
    final path = paths.isNotEmpty ? paths.first : null;
    _all = path;
    return path;
  }

  @override
  Future<int> count() async {
    final path = await _allPath();
    if (path == null) return 0;
    return path.assetCountAsync;
  }

  @override
  Future<List<AssetEntity>> range(int start, int end) async {
    final path = await _allPath();
    if (path == null) return const [];
    return path.getAssetListRange(start: start, end: end);
  }
}

typedef SizeLookup = Future<Map<String, int>> Function(List<String> ids);

class MediaIndexService {
  MediaIndexService({
    required this.db,
    AssetMetadataSource? source,
    SizeLookup? sizeLookup,
  })  : source = source ?? PhotoManagerAssetSource(),
        sizeLookup = sizeLookup ?? MediaSizeChannel.getSizes;

  final MediaIndexDatabase db;
  final AssetMetadataSource source;
  final SizeLookup sizeLookup;

  /// Written when the platform can't resolve a size, so the row leaves the
  /// "missing size" set and the pass terminates instead of retrying forever.
  /// We deliberately do NOT fall back to `asset.file` — on iOS that exports a
  /// full copy of the original just to measure it, which ballooned app storage
  /// past a gigabyte while scrolling. A missing size simply shows no badge.
  static const int unknownSize = 0;

  /// Enumerate the whole library, upsert metadata, prune vanished rows.
  Future<void> syncMetadata({int batch = 500}) async {
    final total = await source.count();
    final seen = <String>{};

    for (var start = 0; start < total; start += batch) {
      final end = math.min(start + batch, total);
      final assets = await source.range(start, end);
      if (assets.isEmpty) break;
      await db.upsertAll(assets.map(_toRow));
      for (final a in assets) {
        seen.add(a.id);
      }
    }

    final removed = (await db.allIds()).difference(seen);
    if (removed.isNotEmpty) await db.deleteIds(removed);
  }

  /// Fill missing byte sizes from the platform's cheap native lookup only.
  /// Anything it can't answer is marked [unknownSize] so the pass terminates;
  /// no file is ever opened.
  Future<void> resolveSizes({int batch = 200, int maxBatches = 1000}) async {
    for (var i = 0; i < maxBatches; i++) {
      final ids = await db.idsMissingSize(limit: batch);
      if (ids.isEmpty) break;

      final native = await sizeLookup(ids);
      final resolved = <String, int>{
        for (final id in ids) id: native[id] ?? unknownSize,
      };
      await db.setSizes(resolved);
    }
  }

  /// Resolve sizes for a specific set of ids right now (native only), persist
  /// them, and return them. Called when a grid page loads so its badges appear
  /// immediately instead of waiting for the full background pass.
  Future<Map<String, int>> resolveSizesFor(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final native = await sizeLookup(ids);
    if (native.isNotEmpty) await db.setSizes(native);
    return native;
  }

  MediaAssetsCompanion _toRow(AssetEntity a) => MediaAssetsCompanion.insert(
        id: a.id,
        type: a.typeInt,
        createdDate: Value(a.createDateSecond ?? 0),
        modifiedDate: Value(a.modifiedDateSecond ?? 0),
        width: Value(a.width),
        height: Value(a.height),
        durationMs: Value(a.duration * 1000),
        title: Value(a.title),
        mimeType: Value(a.mimeType),
      );
}
