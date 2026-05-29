import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../domain/entities/library_sort_filter.dart';
import '../../domain/entities/media_filter.dart';
import 'asset_size_cache.dart';

enum LibraryPermissionStatus { unknown, granted, limited, denied }

const _pageSize = 100;

// Sentinel for nullable copyWith field
class _Absent {
  const _Absent();
}

const _absent = _Absent();

class LibraryState {
  const LibraryState({
    this.permissionStatus = LibraryPermissionStatus.unknown,
    this.filter = MediaFilter.all,
    this.sortFilter = const LibrarySortFilter(),
    this.isLoading = false,
    this.albums = const [],
    this.selectedAlbumId,
    this.assets = const [],
    this.displayAssets = const [],
    this.selectedIds = const {},
    this.isSelecting = false,
    this.totalCount = 0,
    this.hasMore = false,
  });

  final LibraryPermissionStatus permissionStatus;
  final MediaFilter filter;
  final LibrarySortFilter sortFilter;
  final bool isLoading;
  final List<AssetPathEntity> albums;
  final String? selectedAlbumId;
  final List<AssetEntity> assets;

  /// Sorted + filtered view of [assets], precomputed when the inputs change.
  /// The grid reads this directly; raw [assets] stays untouched for pagination
  /// math. Carried by reference across selection toggles, so tapping tiles
  /// never re-runs the sort/filter.
  final List<AssetEntity> displayAssets;

  final Set<String> selectedIds;
  final bool isSelecting;
  final int totalCount;
  final bool hasMore;

  LibraryState copyWith({
    LibraryPermissionStatus? permissionStatus,
    MediaFilter? filter,
    LibrarySortFilter? sortFilter,
    bool? isLoading,
    List<AssetPathEntity>? albums,
    Object? selectedAlbumId = _absent,
    List<AssetEntity>? assets,
    List<AssetEntity>? displayAssets,
    Set<String>? selectedIds,
    bool? isSelecting,
    int? totalCount,
    bool? hasMore,
  }) {
    final nextAssets = assets ?? this.assets;
    final nextSort = sortFilter ?? this.sortFilter;
    // Recompute the derived view only when its inputs change. Selection toggles
    // pass neither `assets` nor `sortFilter`, so they carry the existing list
    // by reference — the hot path never re-sorts. An explicit `displayAssets`
    // forces a refresh (used after warming sizes, where only the cache moved).
    final nextDisplay = displayAssets ??
        ((assets != null || sortFilter != null)
            ? _computeDisplay(nextAssets, nextSort)
            : this.displayAssets);
    return LibraryState(
      permissionStatus: permissionStatus ?? this.permissionStatus,
      filter: filter ?? this.filter,
      sortFilter: nextSort,
      isLoading: isLoading ?? this.isLoading,
      albums: albums ?? this.albums,
      selectedAlbumId: identical(selectedAlbumId, _absent)
          ? this.selectedAlbumId
          : selectedAlbumId as String?,
      assets: nextAssets,
      displayAssets: nextDisplay,
      selectedIds: selectedIds ?? this.selectedIds,
      isSelecting: isSelecting ?? this.isSelecting,
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
    );
  }

  /// Pure sort + filter pipeline. Reads the live [AssetSizeCache] for size
  /// ordering/filtering, so it must be re-run after sizes are warmed.
  static List<AssetEntity> _computeDisplay(
    List<AssetEntity> assets,
    LibrarySortFilter sortFilter,
  ) {
    var list = assets;

    // ── Sort
    int sizeOf(AssetEntity a) => AssetSizeCache.get(a.id) ?? 0;
    switch (sortFilter.sort) {
      case LibrarySort.newestFirst:
      case LibrarySort.oldestFirst:
        break; // already in correct order from photo_manager
      case LibrarySort.largestFirst:
        list = [...list]..sort((a, b) => sizeOf(b).compareTo(sizeOf(a)));
        break;
      case LibrarySort.smallestFirst:
        list = [...list]..sort((a, b) => sizeOf(a).compareTo(sizeOf(b)));
        break;
    }

    // ── Filter by file-size bucket
    if (sortFilter.sizeFilter != LibrarySizeFilter.any) {
      list = list.where((a) {
        final s = AssetSizeCache.get(a.id);
        if (s == null) return true; // keep until we know
        return switch (sortFilter.sizeFilter) {
          LibrarySizeFilter.small => s < 1024 * 1024,
          LibrarySizeFilter.medium =>
            s >= 1024 * 1024 && s < 10 * 1024 * 1024,
          LibrarySizeFilter.large => s >= 10 * 1024 * 1024,
          LibrarySizeFilter.any => true,
        };
      }).toList();
    }

    // ── Filter by format (mime / extension)
    final f = sortFilter.formatFilter;
    if (f != null) {
      list = list.where((a) => _matchesFormat(a, f)).toList();
    }

    return list;
  }

  /// Materialised list of the currently-selected assets, in chronological
  /// order. Reads from the raw `assets` list so items hidden by an active
  /// filter still appear in the batch (the selection count in the AppBar
  /// counts them too).
  List<AssetEntity> get selectedAssets =>
      assets.where((a) => selectedIds.contains(a.id)).toList();

  static bool _matchesFormat(AssetEntity a, String filter) {
    final mime = (a.mimeType ?? '').toLowerCase();
    if (mime.contains(filter)) return true;
    if (filter == 'mov' && mime.contains('quicktime')) return true;
    if (filter == 'jpeg' && mime.contains('jpg')) return true;
    final t = (a.title ?? '').toLowerCase();
    if (t.endsWith('.$filter')) return true;
    if (filter == 'jpeg' && t.endsWith('.jpg')) return true;
    return false;
  }
}

class LibraryNotifier extends Notifier<LibraryState> {
  AssetPathEntity? _currentPath;

  @override
  LibraryState build() => const LibraryState();

  Future<void> init() async {
    if (state.permissionStatus != LibraryPermissionStatus.unknown) return;
    state = state.copyWith(isLoading: true);

    final pmsState = await PhotoManager.requestPermissionExtend();
    final status = _mapPermission(pmsState);
    state = state.copyWith(permissionStatus: status);

    if (status == LibraryPermissionStatus.denied) {
      state = state.copyWith(isLoading: false);
      return;
    }

    await _loadAlbumsAndAssets();
  }

  Future<void> requestPermissionAndRetry() async {
    state = state.copyWith(
      permissionStatus: LibraryPermissionStatus.unknown,
      isLoading: true,
    );
    await init();
  }

  Future<void> openSettings() async {
    await PhotoManager.openSetting();
  }

  Future<void> setFilter(MediaFilter filter) async {
    if (state.filter == filter) return;
    // Keep existing assets visible while the new set loads — prevents the
    // jarring "clear → repopulate" flicker on filter swap. The new list will
    // replace the old in one frame when ready.
    state = state.copyWith(
      filter: filter,
      isLoading: true,
      selectedAlbumId: null,
    );
    await _loadAlbumsAndAssets();
  }

  Future<void> selectAlbum(String? albumId) async {
    if (state.selectedAlbumId == albumId) return;
    state = state.copyWith(
      selectedAlbumId: albumId,
      isLoading: true,
    );
    await _loadAlbumsAndAssets();
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoading || _currentPath == null) return;
    final start = state.assets.length;
    final end = min(state.totalCount, start + _pageSize);
    final more = await _currentPath!.getAssetListRange(start: start, end: end);
    state = state.copyWith(
      assets: [...state.assets, ...more],
      hasMore: end < state.totalCount,
    );
    // Under a size-based sort/filter, the freshly paged-in assets sort as 0
    // until their sizes are known. Warm just the new page, then re-derive so
    // ordering stays correct as the user scrolls deeper.
    if (state.sortFilter.needsSizes && more.isNotEmpty) {
      await AssetSizeCache.warm(more);
      state = state.copyWith(
        displayAssets:
            LibraryState._computeDisplay(state.assets, state.sortFilter),
      );
    }
  }

  void enterSelectionMode([String? id]) {
    state = state.copyWith(
      isSelecting: true,
      selectedIds: id != null ? {id} : <String>{},
    );
  }

  void toggleSelection(String id) {
    final updated = Set<String>.from(state.selectedIds);
    if (updated.contains(id)) {
      updated.remove(id);
    } else {
      updated.add(id);
    }
    state = state.copyWith(
      selectedIds: updated,
      // Stay in selection mode even after the user deselects every item —
      // the cancel button in the AppBar is the only way out, so an empty
      // selection during browsing doesn't accidentally exit.
      isSelecting: true,
    );
  }

  void selectAll() {
    final ids = state.displayAssets.map((a) => a.id).toSet();
    state = state.copyWith(selectedIds: ids, isSelecting: true);
  }

  void clearSelection() {
    state = state.copyWith(selectedIds: <String>{}, isSelecting: false);
  }

  Future<void> setSortFilter(LibrarySortFilter sortFilter) async {
    state = state.copyWith(sortFilter: sortFilter, isLoading: true);
    await _loadAlbumsAndAssets();

    if (sortFilter.needsSizes && state.assets.isNotEmpty) {
      await AssetSizeCache.warm(state.assets);
      // Sizes moved but assets/sortFilter didn't — force a fresh derive so the
      // newly-known sizes feed the sort/filter.
      state = state.copyWith(
        displayAssets:
            LibraryState._computeDisplay(state.assets, state.sortFilter),
      );
    }
  }

  Future<void> clearSortFilter() async {
    if (!state.sortFilter.hasAnyActive) return;
    await setSortFilter(LibrarySortFilter.cleared);
  }

  // ── Private ────────────────────────────────────────────────────

  Future<void> _loadAlbumsAndAssets() async {
    try {
      final type = _requestType(state.filter);
      final filterOption = _filterOptionFor(state.sortFilter);
      final paths = await PhotoManager.getAssetPathList(
        type: type,
        hasAll: true,
        onlyAll: false,
        filterOption: filterOption,
      );

      if (paths.isEmpty) {
        state = state.copyWith(
          albums: [],
          assets: [],
          totalCount: 0,
          hasMore: false,
          isLoading: false,
        );
        return;
      }

      AssetPathEntity currentPath;
      if (state.selectedAlbumId != null) {
        currentPath = paths.firstWhere(
          (p) => p.id == state.selectedAlbumId,
          orElse: () => paths.first,
        );
      } else {
        currentPath = paths.first;
      }
      _currentPath = currentPath;

      final total = await currentPath.assetCountAsync;
      final end = min(total, _pageSize);
      final raw = end > 0
          ? await currentPath.getAssetListRange(start: 0, end: end)
          : <AssetEntity>[];

      state = state.copyWith(
        albums: paths,
        assets: raw,
        totalCount: total,
        hasMore: total > _pageSize,
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Build photo_manager's FilterOptionGroup from our high-level sort/filter.
  /// Date order is supported natively; size/format are handled client-side
  /// once the assets are loaded.
  static FilterOptionGroup _filterOptionFor(LibrarySortFilter f) {
    final orders = <OrderOption>[
      OrderOption(
        type: OrderOptionType.createDate,
        asc: f.sort == LibrarySort.oldestFirst,
      ),
    ];
    return FilterOptionGroup(orders: orders);
  }

  static LibraryPermissionStatus _mapPermission(PermissionState s) =>
      switch (s) {
        PermissionState.authorized => LibraryPermissionStatus.granted,
        PermissionState.limited => LibraryPermissionStatus.limited,
        _ => LibraryPermissionStatus.denied,
      };

  static RequestType _requestType(MediaFilter f) => switch (f) {
        MediaFilter.all => RequestType.common,
        MediaFilter.photos => RequestType.image,
        MediaFilter.videos => RequestType.video,
      };
}

final libraryProvider =
    NotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);
