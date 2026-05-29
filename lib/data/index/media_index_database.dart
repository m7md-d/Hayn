import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'media_index_database.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MediaIndexDatabase — the on-device index of every media asset's metadata.
//
// Why it exists: sorting/filtering a 10k+ library correctly needs knowledge of
// the *whole* library, not just the pages currently loaded. photo_manager only
// paginates; it can't "ORDER BY size across everything". So we mirror the
// lightweight metadata into SQLite once, then answer sort/filter/paginate with
// indexed SQL — instant and correct at any scale.
//
// We store metadata only (≈250 bytes/asset incl. indexes → a few MB for 10k).
// The media bytes themselves are never copied here. `sizeBytes` is nullable
// because byte size is the one field that needs a native lookup; it's filled
// in after the cheap metadata scan.
// ─────────────────────────────────────────────────────────────────────────────

class MediaAssets extends Table {
  /// platform asset id (Android MediaStore id / iOS PhotoKit localIdentifier).
  TextColumn get id => text()();

  /// AssetType.index — 0 other, 1 image, 2 video, 3 audio.
  IntColumn get type => integer()();

  /// Epoch seconds. 0 when the platform didn't report a date.
  IntColumn get createdDate => integer().withDefault(const Constant(0))();
  IntColumn get modifiedDate => integer().withDefault(const Constant(0))();

  IntColumn get width => integer().withDefault(const Constant(0))();
  IntColumn get height => integer().withDefault(const Constant(0))();

  /// Video duration in milliseconds; 0 for stills.
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  /// File size in bytes. null = not yet resolved (filled by the size pass).
  IntColumn get sizeBytes => integer().nullable()();

  TextColumn get title => text().nullable()();
  TextColumn get mimeType => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Which column a [MediaIndexDatabase.page] query sorts by.
enum AssetSortColumn { createdDate, sizeBytes }

@DriftDatabase(tables: [MediaAssets])
class MediaIndexDatabase extends _$MediaIndexDatabase {
  /// Pass an in-memory executor in tests; production opens the file lazily.
  MediaIndexDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Indexes on every column we sort or filter by, so queries stay
          // O(log n) instead of scanning the whole table at 10k+ rows.
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_assets_created ON media_assets (created_date)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_assets_size ON media_assets (size_bytes)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_assets_type ON media_assets (type)');
        },
      );

  // ── Writes ──────────────────────────────────────────────────────────────

  /// Insert-or-replace a batch of assets. Used by the scan/sync service.
  Future<void> upsertAll(Iterable<MediaAssetsCompanion> rows) async {
    await batch((b) => b.insertAllOnConflictUpdate(mediaAssets, rows.toList()));
  }

  Future<void> setSize(String id, int bytes) async {
    await (update(mediaAssets)..where((t) => t.id.equals(id)))
        .write(MediaAssetsCompanion(sizeBytes: Value(bytes)));
  }

  /// Batched size writes — the size pass resolves a page at a time.
  Future<void> setSizes(Map<String, int> sizes) async {
    if (sizes.isEmpty) return;
    await batch((b) {
      for (final e in sizes.entries) {
        b.update(
          mediaAssets,
          MediaAssetsCompanion(sizeBytes: Value(e.value)),
          where: (t) => t.id.equals(e.key),
        );
      }
    });
  }

  Future<void> deleteIds(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (delete(mediaAssets)..where((t) => t.id.isIn(list))).go();
  }

  Future<void> clearAll() => delete(mediaAssets).go();

  // ── Reads ───────────────────────────────────────────────────────────────

  /// All indexed ids — used by sync to diff against the live library.
  Future<Set<String>> allIds() async {
    final q = selectOnly(mediaAssets)..addColumns([mediaAssets.id]);
    final rows = await q.get();
    return rows.map((r) => r.read(mediaAssets.id)!).toSet();
  }

  /// All ids matching the filter (no paging). Powers "select all" across the
  /// whole library — ids only, so no AssetEntity or thumbnail is materialised.
  Future<List<String>> matchingIds({
    int? typeFilter,
    int? minSize,
    int? maxSize,
    List<String> formatNeedles = const [],
  }) async {
    final q = selectOnly(mediaAssets)..addColumns([mediaAssets.id]);
    final pred = _predicate(
      typeFilter: typeFilter,
      minSize: minSize,
      maxSize: maxSize,
      formatNeedles: formatNeedles,
    );
    if (pred != null) q.where(pred);
    final rows = await q.get();
    return rows.map((r) => r.read(mediaAssets.id)!).toList();
  }

  Future<int> totalCount() async {
    final c = mediaAssets.id.count();
    final q = selectOnly(mediaAssets)..addColumns([c]);
    return (await q.getSingle()).read(c) ?? 0;
  }

  /// Resolved byte sizes for the given ids (skips unknown/missing). Lets any
  /// view — including the album path that still enumerates via photo_manager —
  /// seed its size badges from the index instead of touching files.
  Future<Map<String, int>> sizesFor(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final q = selectOnly(mediaAssets)
      ..addColumns([mediaAssets.id, mediaAssets.sizeBytes])
      ..where(mediaAssets.id.isIn(ids) & mediaAssets.sizeBytes.isNotNull());
    final rows = await q.get();
    final out = <String, int>{};
    for (final r in rows) {
      final s = r.read(mediaAssets.sizeBytes);
      if (s != null && s > 0) out[r.read(mediaAssets.id)!] = s;
    }
    return out;
  }

  /// Size + pixel dimensions for the given ids (only rows with a known, real
  /// size). Feeds the savings estimator so it can model output from dimensions
  /// across the WHOLE selection, not just the loaded pages.
  Future<List<({int sizeBytes, int width, int height})>> factsFor(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const [];
    final q = select(mediaAssets)
      ..where((t) => t.id.isIn(ids) & t.sizeBytes.isBiggerThanValue(0));
    final rows = await q.get();
    return [
      for (final r in rows)
        (sizeBytes: r.sizeBytes!, width: r.width, height: r.height),
    ];
  }

  /// Ids missing a resolved byte size — the size pass works through these.
  Future<List<String>> idsMissingSize({int limit = 200}) async {
    final q = selectOnly(mediaAssets)
      ..addColumns([mediaAssets.id])
      ..where(mediaAssets.sizeBytes.isNull())
      ..limit(limit);
    final rows = await q.get();
    return rows.map((r) => r.read(mediaAssets.id)!).toList();
  }

  /// Count matching the filter (no paging) — drives the grid's total + hasMore.
  Future<int> count({
    int? typeFilter,
    int? minSize,
    int? maxSize,
    List<String> formatNeedles = const [],
  }) async {
    final c = mediaAssets.id.count();
    final q = selectOnly(mediaAssets)..addColumns([c]);
    final pred = _predicate(
      typeFilter: typeFilter,
      minSize: minSize,
      maxSize: maxSize,
      formatNeedles: formatNeedles,
    );
    if (pred != null) q.where(pred);
    return (await q.getSingle()).read(c) ?? 0;
  }

  /// One sorted, filtered, paginated page — the query that replaces the old
  /// client-side sort over loaded pages.
  Future<List<MediaAsset>> page({
    int? typeFilter,
    int? minSize,
    int? maxSize,
    List<String> formatNeedles = const [],
    AssetSortColumn sortColumn = AssetSortColumn.createdDate,
    bool descending = true,
    required int limit,
    required int offset,
  }) {
    final q = select(mediaAssets);
    final pred = _predicate(
      typeFilter: typeFilter,
      minSize: minSize,
      maxSize: maxSize,
      formatNeedles: formatNeedles,
    );
    if (pred != null) q.where((_) => pred);

    final col = sortColumn == AssetSortColumn.sizeBytes
        ? mediaAssets.sizeBytes
        : mediaAssets.createdDate;
    q.orderBy([
      (_) => OrderingTerm(
            expression: col,
            mode: descending ? OrderingMode.desc : OrderingMode.asc,
          ),
      // Stable tiebreak so paging never duplicates/skips rows on ties.
      (_) => OrderingTerm(expression: mediaAssets.id, mode: OrderingMode.asc),
    ]);
    q.limit(limit, offset: offset);
    return q.get();
  }

  /// Every matching row in order — the full "spine" for a virtualized grid.
  /// Lightweight (no AssetEntity); a few MB for 10k. childCount = its length.
  Future<List<MediaAsset>> entries({
    int? typeFilter,
    int? minSize,
    int? maxSize,
    List<String> formatNeedles = const [],
    AssetSortColumn sortColumn = AssetSortColumn.createdDate,
    bool descending = true,
  }) {
    final q = select(mediaAssets);
    final pred = _predicate(
      typeFilter: typeFilter,
      minSize: minSize,
      maxSize: maxSize,
      formatNeedles: formatNeedles,
    );
    if (pred != null) q.where((_) => pred);

    final col = sortColumn == AssetSortColumn.sizeBytes
        ? mediaAssets.sizeBytes
        : mediaAssets.createdDate;
    q.orderBy([
      (_) => OrderingTerm(
            expression: col,
            mode: descending ? OrderingMode.desc : OrderingMode.asc,
          ),
      (_) => OrderingTerm(expression: mediaAssets.id, mode: OrderingMode.asc),
    ]);
    return q.get();
  }

  Expression<bool>? _predicate({
    int? typeFilter,
    int? minSize,
    int? maxSize,
    List<String> formatNeedles = const [],
  }) {
    Expression<bool>? pred;
    void and(Expression<bool> e) => pred = pred == null ? e : pred! & e;

    if (typeFilter != null) and(mediaAssets.type.equals(typeFilter));
    if (minSize != null) and(mediaAssets.sizeBytes.isBiggerOrEqualValue(minSize));
    if (maxSize != null) and(mediaAssets.sizeBytes.isSmallerThanValue(maxSize));

    if (formatNeedles.isNotEmpty) {
      Expression<bool>? fmt;
      for (final n in formatNeedles) {
        final byMime = mediaAssets.mimeType.like('%$n%');
        final byExt = mediaAssets.title.like('%.$n');
        final either = byMime | byExt;
        fmt = fmt == null ? either : fmt | either;
      }
      if (fmt != null) and(fmt);
    }
    return pred;
  }
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'media_index.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
