import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/isolates/media_task.dart';
import 'package:hayn/core/isolates/task_progress.dart';
import 'package:hayn/core/isolates/task_runner.dart';
import 'package:hayn/data/index/index_providers.dart';
import 'package:hayn/data/index/media_index_database.dart';
import 'package:hayn/features/library/domain/entities/media_filter.dart';
import 'package:hayn/features/library/presentation/providers/library_provider.dart';
import 'package:photo_manager/photo_manager.dart' show AssetType;

// RV-05: a grid load that ends after a newer one started publishes nothing.
// Before, switching the filter twice let the first query, finishing last,
// replace the second's grid under the second's filter.
// RV-07: copies a task saved reach the library when it ends, also when the
// batch failed or was cancelled partway.

/// An index whose photo query waits until [release] completes.
class _SlowPhotos extends MediaIndexDatabase {
  _SlowPhotos() : super(NativeDatabase.memory());
  final release = Completer<void>();

  @override
  Future<List<MediaAsset>> entries({
    int? typeFilter,
    int? minSize,
    int? maxSize,
    List<String> formatNeedles = const [],
    AssetSortColumn sortColumn = AssetSortColumn.createdDate,
    bool descending = true,
  }) async {
    final rows = await super.entries(
      typeFilter: typeFilter,
      minSize: minSize,
      maxSize: maxSize,
      formatNeedles: formatNeedles,
      sortColumn: sortColumn,
      descending: descending,
    );
    if (typeFilter == AssetType.image.index) await release.future;
    return rows;
  }
}

class _Task extends MediaTask {
  _Task(this.id);
  @override
  final String id;
  @override
  TaskType get type => TaskType.compress;
  @override
  Stream<TaskEvent> run() => const Stream.empty();
  @override
  Future<void> cancel() async {}
  @override
  Future<void> cleanup() async {}
}

TaskState _state(MediaTask task, TaskStatus status) =>
    TaskState(task: task, status: status, enqueuedAt: DateTime(2026));

void main() {
  test('a filter load that ends last does not replace the newer one', () async {
    final db = _SlowPhotos();
    await db.upsertAll([
      MediaAssetsCompanion.insert(
        id: 'photo',
        type: AssetType.image.index,
        sizeBytes: const Value(10),
      ),
      MediaAssetsCompanion.insert(
        id: 'video',
        type: AssetType.video.index,
        sizeBytes: const Value(10),
      ),
    ]);
    final container = ProviderContainer(
      overrides: [mediaIndexDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
    final library = container.read(libraryProvider.notifier)..markIndexReady();

    final photos = library.setFilter(MediaFilter.photos); // waits
    await library.setFilter(MediaFilter.videos);
    expect(container.read(libraryProvider).entries.map((e) => e.id), ['video']);

    db.release.complete();
    await photos;
    final state = container.read(libraryProvider);
    expect(state.filter, MediaFilter.videos);
    expect(state.entries.map((e) => e.id), ['video']);
  });

  test('copies saved by a task reach the library once it ends, '
      'whatever its end', () {
    final done = _Task('done')..outputAssetIds.add('a');
    final failed = _Task('failed')..outputAssetIds.add('b');
    final cancelled = _Task('cancelled')..outputAssetIds.add('c');
    final running = _Task('running')..outputAssetIds.add('d');

    final before = [
      _state(done, TaskStatus.running),
      _state(failed, TaskStatus.running),
      _state(cancelled, TaskStatus.running),
      _state(running, TaskStatus.running),
    ];
    final after = [
      _state(done, TaskStatus.completed),
      _state(failed, TaskStatus.failed),
      _state(cancelled, TaskStatus.cancelled),
      _state(running, TaskStatus.running),
    ];
    expect(freshTaskOutputs(before, after), ['a', 'b', 'c']);
    // Once: a later change to the list does not bring them again.
    expect(freshTaskOutputs(after, after), isEmpty);
  });
}
