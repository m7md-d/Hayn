import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/data/index/media_index_database.dart';
import 'package:hayn/features/library/domain/entities/library_sort_filter.dart';
import 'package:hayn/features/library/domain/entities/media_filter.dart';
import 'package:hayn/features/library/presentation/providers/library_provider.dart';
import 'package:photo_manager/photo_manager.dart';

void main() {
  group('LibraryNotifier.queryParamsFor', () {
    test('default: all media, newest first, no constraints', () {
      final q = LibraryNotifier.queryParamsFor(
          MediaFilter.all, const LibrarySortFilter());
      expect(q.typeFilter, isNull);
      expect(q.sortColumn, AssetSortColumn.createdDate);
      expect(q.descending, isTrue);
      expect(q.minSize, isNull);
      expect(q.maxSize, isNull);
      expect(q.formatNeedles, isEmpty);
    });

    test('media filter maps to the AssetType index', () {
      expect(
        LibraryNotifier.queryParamsFor(MediaFilter.photos, const LibrarySortFilter())
            .typeFilter,
        AssetType.image.index,
      );
      expect(
        LibraryNotifier.queryParamsFor(MediaFilter.videos, const LibrarySortFilter())
            .typeFilter,
        AssetType.video.index,
      );
    });

    test('sort maps to the right column + direction', () {
      ({AssetSortColumn sortColumn, bool descending}) s(LibrarySort sort) {
        final q = LibraryNotifier.queryParamsFor(
            MediaFilter.all, LibrarySortFilter(sort: sort));
        return (sortColumn: q.sortColumn, descending: q.descending);
      }

      expect(s(LibrarySort.newestFirst),
          (sortColumn: AssetSortColumn.createdDate, descending: true));
      expect(s(LibrarySort.oldestFirst),
          (sortColumn: AssetSortColumn.createdDate, descending: false));
      expect(s(LibrarySort.largestFirst),
          (sortColumn: AssetSortColumn.sizeBytes, descending: true));
      expect(s(LibrarySort.smallestFirst),
          (sortColumn: AssetSortColumn.sizeBytes, descending: false));
    });

    test('size buckets map to half-open [min, max) byte ranges', () {
      const mb = 1024 * 1024;
      ({int? min, int? max}) r(LibrarySizeFilter f) {
        final q = LibraryNotifier.queryParamsFor(
            MediaFilter.all, LibrarySortFilter(sizeFilter: f));
        return (min: q.minSize, max: q.maxSize);
      }

      expect(r(LibrarySizeFilter.small), (min: null, max: mb));
      expect(r(LibrarySizeFilter.medium), (min: mb, max: 10 * mb));
      expect(r(LibrarySizeFilter.large), (min: 10 * mb, max: null));
    });

    test('format filter expands the tricky aliases', () {
      List<String> needles(String fmt) => LibraryNotifier.queryParamsFor(
            MediaFilter.all,
            LibrarySortFilter(formatFilter: fmt),
          ).formatNeedles;

      expect(needles('jpeg'), ['jpeg', 'jpg']);
      expect(needles('mov'), ['mov', 'quicktime']);
      expect(needles('png'), ['png']);
    });
  });
}
