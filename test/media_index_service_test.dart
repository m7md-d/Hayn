import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/data/index/media_index_database.dart';
import 'package:hayn/data/index/media_index_service.dart';
import 'package:photo_manager/photo_manager.dart';

AssetEntity _a(String id, {int type = 1, int created = 0}) => AssetEntity(
      id: id,
      typeInt: type,
      width: 100,
      height: 100,
      createDateSecond: created,
    );

class _FakeSource implements AssetMetadataSource {
  _FakeSource(this.assets);
  List<AssetEntity> assets;
  int invalidateCalls = 0;

  @override
  Future<int> count() async => assets.length;

  @override
  Future<List<AssetEntity>> range(int start, int end) async =>
      assets.sublist(start, math.min(end, assets.length));

  @override
  void invalidate() => invalidateCalls++;
}

void main() {
  late MediaIndexDatabase db;
  setUp(() => db = MediaIndexDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('syncMetadata indexes every asset from the source', () async {
    final source = _FakeSource([_a('a'), _a('b'), _a('c')]);
    final svc = MediaIndexService(
      db: db,
      source: source,
      sizeLookup: (_) async => {},
    );

    await svc.syncMetadata(batch: 2); // exercises multi-batch paging
    expect(await db.allIds(), {'a', 'b', 'c'});
  });

  test('re-sync prunes assets that disappeared from the library', () async {
    final source = _FakeSource([_a('a'), _a('b'), _a('c')]);
    final svc = MediaIndexService(
      db: db,
      source: source,
      sizeLookup: (_) async => {},
    );
    await svc.syncMetadata();

    source.assets = [_a('a'), _a('c')]; // 'b' deleted on device
    final removed = await svc.syncMetadata();

    expect(await db.allIds(), {'a', 'c'});
    expect(removed, {'b'}); // surfaced so callers can evict caches at once
  });

  test('invalidateSource forwards to the asset source', () async {
    final source = _FakeSource([_a('a')]);
    final svc = MediaIndexService(
      db: db,
      source: source,
      sizeLookup: (_) async => {},
    );
    svc.invalidateSource();
    expect(source.invalidateCalls, 1);
  });

  test('re-sync preserves an already-resolved byte size', () async {
    final source = _FakeSource([_a('a')]);
    final svc = MediaIndexService(
      db: db,
      source: source,
      sizeLookup: (_) async => {},
    );
    await svc.syncMetadata();
    await db.setSize('a', 4242);

    await svc.syncMetadata(); // metadata refresh must not wipe the size
    final row = (await db.page(limit: 1, offset: 0)).single;
    expect(row.sizeBytes, 4242);
  });

  test('resolveSizes takes native sizes, sentinels the rest (no asset.file)',
      () async {
    final source = _FakeSource([_a('a'), _a('b'), _a('c')]);
    final svc = MediaIndexService(
      db: db,
      source: source,
      sizeLookup: (ids) async => {'a': 10, 'b': 20}, // native resolves a,b only
    );
    await svc.syncMetadata();

    await svc.resolveSizes(batch: 10);

    final byId = {
      for (final r in await db.page(limit: 10, offset: 0)) r.id: r.sizeBytes,
    };
    expect(byId['a'], 10);
    expect(byId['b'], 20);
    expect(byId['c'], MediaIndexService.unknownSize); // 0 = tried, unknown
    // The pass terminated — nothing left marked missing, no file ever opened.
    expect(await db.idsMissingSize(), isEmpty);
  });

  test('resolveSizesFor fills a specific page and persists', () async {
    final source = _FakeSource([_a('a'), _a('b')]);
    final svc = MediaIndexService(
      db: db,
      source: source,
      sizeLookup: (ids) async => {for (final id in ids) id: id.length},
    );
    await svc.syncMetadata();

    final fresh = await svc.resolveSizesFor(['a']);
    expect(fresh, {'a': 1});
    expect(await db.sizesFor(['a', 'b']), {'a': 1}); // 'b' untouched
  });
}
