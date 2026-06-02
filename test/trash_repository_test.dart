import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/data/index/media_index_database.dart';
import 'package:hayn/features/trash/data/trash_repository.dart';

// The crash-safe journal state machine that guards Surgical Replace:
//   insertPending (pending) → markCommitted (committed/restorable) → drop.
// Tested against an in-memory drift DB (no device, no backup files — drafts
// carry a backupPath string; drop's file delete is a no-op when absent).
void main() {
  late MediaIndexDatabase db;
  late TrashRepository repo;

  setUp(() {
    db = MediaIndexDatabase(NativeDatabase.memory());
    repo = TrashRepository(db);
  });
  tearDown(() => db.close());

  TrashDraft draft(String id, {int width = 4000, int height = 3000}) => TrashDraft(
        id: id,
        originalAssetId: 'asset-$id',
        filename: '$id.jpg',
        backupPath: '/tmp/does-not-exist/$id.jpg',
        createdDateMs: 1000,
        modifiedDateMs: 2000,
        latitude: 21.0,
        longitude: 39.0,
        isFavorite: true,
        userAlbumIds: const ['alb1', 'alb2'],
        mimeType: 'image/jpeg',
        width: width,
        height: height,
        originalBytes: 5000000,
        newBytes: 1200000,
      );

  test('insertPending lands as pending, not in the committed list', () async {
    await repo.insertPending(draft('a'));
    expect((await repo.listPending()).map((e) => e.id), ['a']);
    expect(await repo.listCommitted(), isEmpty);
    final row = await repo.byId('a');
    expect(row, isNotNull);
    expect(row!.state, TrashState.pending.index);
    expect(row.originalAssetId, 'asset-a');
    expect(row.isFavorite, isTrue);
  });

  test('markCommitted moves it to the restorable trash list', () async {
    await repo.insertPending(draft('a'));
    await repo.markCommitted('a', newAssetId: 'asset-a', newBytes: 1200000);
    expect(await repo.listPending(), isEmpty);
    final committed = await repo.listCommitted();
    expect(committed.map((e) => e.id), ['a']);
    expect(committed.first.state, TrashState.committed.index);
    expect(committed.first.deletedAtMs, greaterThan(0));
    expect(committed.first.newAssetId, 'asset-a');
  });

  test('drop removes the row entirely', () async {
    await repo.insertPending(draft('a'));
    await repo.markCommitted('a');
    await repo.drop('a');
    expect(await repo.byId('a'), isNull);
    expect(await repo.listCommitted(), isEmpty);
  });

  test('listCommitted is newest-deletion-first', () async {
    await repo.insertPending(draft('old'));
    await repo.insertPending(draft('new'));
    await repo.markCommitted('old', deletedAtMs: 1000);
    await repo.markCommitted('new', deletedAtMs: 9000);
    expect((await repo.listCommitted()).map((e) => e.id), ['new', 'old']);
  });

  test('purgeExpired drops lapsed committed rows, keeps recent + pending',
      () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await repo.insertPending(draft('expired'));
    await repo.insertPending(draft('fresh'));
    await repo.insertPending(draft('pendingRow'));
    // 40 days ago vs just now; retention 14 days.
    await repo.markCommitted('expired',
        deletedAtMs: now - const Duration(days: 40).inMilliseconds);
    await repo.markCommitted('fresh', deletedAtMs: now);
    // 'pendingRow' stays pending.

    final removed = await repo.purgeExpired(14);
    expect(removed, 1);
    expect((await repo.listCommitted()).map((e) => e.id), ['fresh']);
    // A pending row is never purged by retention (it's mid-transaction).
    expect((await repo.listPending()).map((e) => e.id), ['pendingRow']);
  });

  test('userAlbumIds JSON round-trips through the journal', () async {
    await repo.insertPending(draft('a'));
    final row = await repo.byId('a');
    expect(TrashRepository.decodeIds(row!.userAlbumIds), ['alb1', 'alb2']);
  });

  test('decodeIds handles the empty list', () {
    expect(TrashRepository.decodeIds('[]'), isEmpty);
    expect(TrashRepository.decodeIds(''), isEmpty);
  });
}
