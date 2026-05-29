import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/features/library/domain/entities/library_sort_filter.dart';
import 'package:hayn/features/library/presentation/providers/asset_size_cache.dart';
import 'package:hayn/features/library/presentation/providers/library_provider.dart';
import 'package:photo_manager/photo_manager.dart';

AssetEntity _img(String id) =>
    AssetEntity(id: id, typeInt: 1, width: 100, height: 100);

void main() {
  group('LibraryState.displayAssets memoization', () {
    test('selection toggles carry the same display list by reference', () {
      final assets = [_img('a'), _img('b'), _img('c')];
      final base = const LibraryState().copyWith(assets: assets);

      // A pure selection change must NOT rebuild the derived list.
      final selected = base.copyWith(selectedIds: {'a'});
      expect(identical(base.displayAssets, selected.displayAssets), isTrue);

      final more = selected.copyWith(selectedIds: {'a', 'b'});
      expect(identical(base.displayAssets, more.displayAssets), isTrue);
    });

    test('changing assets recomputes the display list', () {
      final base =
          const LibraryState().copyWith(assets: [_img('a'), _img('b')]);
      final grown = base.copyWith(assets: [_img('a'), _img('b'), _img('c')]);

      expect(identical(base.displayAssets, grown.displayAssets), isFalse);
      expect(grown.displayAssets.length, 3);
    });

    test('changing the sort recomputes the display list', () {
      final base =
          const LibraryState().copyWith(assets: [_img('a'), _img('b')]);
      final sorted = base.copyWith(
        sortFilter: const LibrarySortFilter(sort: LibrarySort.largestFirst),
      );
      expect(identical(base.displayAssets, sorted.displayAssets), isFalse);
    });

    test('largest-first orders by cached byte size', () {
      AssetSizeCache.clear();
      AssetSizeCache.put('small', 100);
      AssetSizeCache.put('big', 900);
      AssetSizeCache.put('mid', 400);

      final state = const LibraryState().copyWith(
        assets: [_img('small'), _img('big'), _img('mid')],
        sortFilter: const LibrarySortFilter(sort: LibrarySort.largestFirst),
      );

      expect(
        state.displayAssets.map((a) => a.id).toList(),
        ['big', 'mid', 'small'],
      );
      AssetSizeCache.clear();
    });

    test('the raw assets list is left untouched by sorting', () {
      AssetSizeCache.clear();
      AssetSizeCache.put('x', 100);
      AssetSizeCache.put('y', 900);

      final assets = [_img('x'), _img('y')];
      final state = const LibraryState().copyWith(
        assets: assets,
        sortFilter: const LibrarySortFilter(sort: LibrarySort.largestFirst),
      );

      // displayAssets is reordered, assets keeps insertion order for paging.
      expect(state.assets.map((a) => a.id).toList(), ['x', 'y']);
      expect(state.displayAssets.map((a) => a.id).toList(), ['y', 'x']);
      AssetSizeCache.clear();
    });
  });
}
