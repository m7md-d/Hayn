import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/data/index/media_index_database.dart';

MediaAssetsCompanion _row(
  String id, {
  int type = 1,
  int created = 0,
  int? size,
  String? title,
  String? mime,
}) =>
    MediaAssetsCompanion.insert(
      id: id,
      type: type,
      createdDate: Value(created),
      sizeBytes: Value(size),
      title: Value(title),
      mimeType: Value(mime),
    );

void main() {
  late MediaIndexDatabase db;

  setUp(() => db = MediaIndexDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('upsert + total count, and upsert replaces on conflict', () async {
    await db.upsertAll([_row('a'), _row('b'), _row('c')]);
    expect(await db.totalCount(), 3);

    // Same id again → replace, not duplicate.
    await db.upsertAll([_row('a', size: 999)]);
    expect(await db.totalCount(), 3);
  });

  test('page sorts by date, newest and oldest', () async {
    await db.upsertAll([
      _row('old', created: 100),
      _row('new', created: 300),
      _row('mid', created: 200),
    ]);

    final newest = await db.page(descending: true, limit: 10, offset: 0);
    expect(newest.map((r) => r.id).toList(), ['new', 'mid', 'old']);

    final oldest = await db.page(descending: false, limit: 10, offset: 0);
    expect(oldest.map((r) => r.id).toList(), ['old', 'mid', 'new']);
  });

  test('page sorts by size across the whole set', () async {
    await db.upsertAll([
      _row('small', size: 100),
      _row('big', size: 900),
      _row('mid', size: 400),
    ]);

    final largest = await db.page(
      sortColumn: AssetSortColumn.sizeBytes,
      descending: true,
      limit: 10,
      offset: 0,
    );
    expect(largest.map((r) => r.id).toList(), ['big', 'mid', 'small']);
  });

  test('type filter narrows to images or videos', () async {
    await db.upsertAll([
      _row('img1', type: 1),
      _row('vid1', type: 2),
      _row('img2', type: 1),
    ]);

    final videos = await db.page(typeFilter: 2, limit: 10, offset: 0);
    expect(videos.map((r) => r.id).toList(), ['vid1']);
    expect(await db.count(typeFilter: 1), 2);
  });

  test('size-bucket filter uses a half-open [min, max) range', () async {
    await db.upsertAll([
      _row('tiny', size: 500), // < 1MB
      _row('mid', size: 5 * 1024 * 1024), // 1–10MB
      _row('huge', size: 20 * 1024 * 1024), // >= 10MB
    ]);

    final medium = await db.page(
      minSize: 1024 * 1024,
      maxSize: 10 * 1024 * 1024,
      limit: 10,
      offset: 0,
    );
    expect(medium.map((r) => r.id).toList(), ['mid']);
  });

  test('format needles match by mime or by filename extension', () async {
    await db.upsertAll([
      _row('a', title: 'IMG.jpg', mime: 'image/jpeg'),
      _row('b', title: 'pic.png', mime: 'image/png'),
      _row('c', title: 'clip.mov', mime: 'video/quicktime'),
    ]);

    // 'jpeg' should also catch the .jpg extension via the needle list.
    final jpegs =
        await db.page(formatNeedles: ['jpeg', 'jpg'], limit: 10, offset: 0);
    expect(jpegs.map((r) => r.id).toList(), ['a']);

    final movs =
        await db.page(formatNeedles: ['mov', 'quicktime'], limit: 10, offset: 0);
    expect(movs.map((r) => r.id).toList(), ['c']);
  });

  test('pagination with limit/offset is stable on ties', () async {
    await db.upsertAll([
      for (var i = 0; i < 10; i++) _row('id$i', created: 0), // all tied
    ]);

    final page1 = await db.page(limit: 4, offset: 0);
    final page2 = await db.page(limit: 4, offset: 4);
    final page3 = await db.page(limit: 4, offset: 8);

    final all = [...page1, ...page2, ...page3].map((r) => r.id).toList();
    expect(all.toSet().length, 10); // no dupes, no skips across pages
  });

  test('size pass helpers: missing ids, setSize, then none missing', () async {
    await db.upsertAll([_row('a'), _row('b', size: 50), _row('c')]);

    final missing = await db.idsMissingSize();
    expect(missing.toSet(), {'a', 'c'});

    await db.setSize('a', 123);
    await db.setSize('c', 456);
    expect(await db.idsMissingSize(), isEmpty);
  });

  test('allIds + deleteIds support sync diffing', () async {
    await db.upsertAll([_row('a'), _row('b'), _row('c')]);
    expect(await db.allIds(), {'a', 'b', 'c'});

    await db.deleteIds(['b']);
    expect(await db.allIds(), {'a', 'c'});
  });
}
