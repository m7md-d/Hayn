// ─────────────────────────────────────────────────────────────────────────────
// Sort + filter options applied on top of the (filter, album) selection.
// "Newest first" maps to photo_manager's OrderOption.createDateDesc; the size
// variants are client-side (photo_manager doesn't expose size sort natively).
// ─────────────────────────────────────────────────────────────────────────────

enum LibrarySort { newestFirst, oldestFirst, largestFirst, smallestFirst }

enum LibrarySizeFilter { any, small, medium, large }

class LibrarySortFilter {
  const LibrarySortFilter({
    this.sort = LibrarySort.newestFirst,
    this.sizeFilter = LibrarySizeFilter.any,
    this.formatFilter,
  });

  final LibrarySort sort;
  final LibrarySizeFilter sizeFilter;

  /// Lower-case extension or MIME suffix, e.g. 'jpeg' / 'png' / 'heic'.
  /// null = any.
  final String? formatFilter;

  bool get hasAnyActive =>
      sort != LibrarySort.newestFirst ||
      sizeFilter != LibrarySizeFilter.any ||
      formatFilter != null;

  LibrarySortFilter copyWith({
    LibrarySort? sort,
    LibrarySizeFilter? sizeFilter,
    Object? formatFilter = _absent,
  }) {
    return LibrarySortFilter(
      sort: sort ?? this.sort,
      sizeFilter: sizeFilter ?? this.sizeFilter,
      formatFilter: identical(formatFilter, _absent)
          ? this.formatFilter
          : formatFilter as String?,
    );
  }

  static const cleared = LibrarySortFilter();
}

const _absent = Object();
