import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart' show MethodCall;
import 'package:flutter/widgets.dart'
    show
        AppLifecycleState,
        ScrollController,
        VoidCallback,
        WidgetsBinding,
        WidgetsBindingObserver;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../../data/index/index_providers.dart';
import '../../../../data/index/media_index_database.dart';
import '../../domain/entities/library_sort_filter.dart';
import '../../domain/entities/media_filter.dart';
import 'asset_entity_cache.dart';
import 'asset_size_cache.dart';

enum LibraryPermissionStatus { unknown, granted, limited, denied }

const _pageSize = 100;

// Sentinel for nullable copyWith field
class _Absent {
  const _Absent();
}

const _absent = _Absent();

/// Lightweight row of the library "spine" — everything the grid/detail/strip
/// need to render a cell BEFORE its heavy [AssetEntity] is materialised. In
/// index-backed mode the spine spans the WHOLE library (10k+), so the grid's
/// childCount is the real total and each cell loads its entity lazily on
/// scroll-in (see [AssetEntityCache]). A few tens of bytes each → trivial even
/// at 10k. In album/legacy mode it's derived from the loaded entities.
class LibraryEntry {
  const LibraryEntry({
    required this.id,
    required this.type,
    this.sizeBytes,
    this.durationSeconds = 0,
    this.created,
  });

  final String id;
  final AssetType type;

  /// Resolved byte size (for the badge), or null when not yet known.
  final int? sizeBytes;

  /// Video length in whole seconds; 0 for stills (drives the duration badge).
  final int durationSeconds;

  /// Capture/creation time, for the detail-view title without the entity.
  final DateTime? created;

  bool get isVideo => type == AssetType.video;

  /// Build a spine row from an already-materialised entity (legacy/album path).
  static LibraryEntry fromAsset(AssetEntity a) => LibraryEntry(
        id: a.id,
        type: a.type,
        sizeBytes: AssetSizeCache.get(a.id),
        durationSeconds: a.videoDuration.inSeconds,
        created: a.createDateTime,
      );
}

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
    this.entries = const [],
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

  /// The ordered "spine" the grid/detail/filmstrip render from. In index-backed
  /// mode this is the WHOLE matching library (childCount = its length, cells
  /// materialise lazily); in album/legacy mode it mirrors [displayAssets].
  final List<LibraryEntry> entries;

  final Set<String> selectedIds;
  final bool isSelecting;
  final int totalCount;
  final bool hasMore;

  /// The type the current selection is "locked" to — the type of the first
  /// selected item, or null when nothing is selected. Selections are
  /// single-type (you can't batch photos and videos together), so tiles of the
  /// other type are disabled while this is set.
  AssetType? get selectionType {
    if (selectedIds.isEmpty) return null;
    for (final e in entries) {
      if (selectedIds.contains(e.id)) return e.type;
    }
    return null;
  }

  LibraryState copyWith({
    LibraryPermissionStatus? permissionStatus,
    MediaFilter? filter,
    LibrarySortFilter? sortFilter,
    bool? isLoading,
    List<AssetPathEntity>? albums,
    Object? selectedAlbumId = _absent,
    List<AssetEntity>? assets,
    List<AssetEntity>? displayAssets,
    List<LibraryEntry>? entries,
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
    // The grid spine: index-backed loads pass `entries` explicitly (the whole
    // library); otherwise it mirrors displayAssets and is carried by reference
    // whenever displayAssets is (so selection toggles never rebuild it).
    final nextEntries = entries ??
        (identical(nextDisplay, this.displayAssets)
            ? this.entries
            : [for (final a in nextDisplay) LibraryEntry.fromAsset(a)]);
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
      entries: nextEntries,
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

/// Forwards app-resume events to the library so it can re-sync. Photo deletions
/// / edits made in the Photos app while Hayn is backgrounded don't fire the
/// in-app change callback, so resuming is our reliable cue to reconcile.
class _LifecycleObserver extends WidgetsBindingObserver {
  _LifecycleObserver(this.onResume);
  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

class LibraryNotifier extends Notifier<LibraryState> {
  AssetPathEntity? _currentPath;
  bool _indexReady = false;
  bool _syncing = false;
  bool _loadingMore = false;
  Timer? _changeDebounce;
  _LifecycleObserver? _lifecycle;

  /// Index-backed mode drives the whole library view (default browse AND
  /// sort/filter) once the index is populated — so byte sizes come from the
  /// index (no `asset.file`), select-all spans everything, and scrolling stays
  /// smooth. Only an album selection drops back to photo_manager paging (the
  /// index doesn't track album membership yet); the first launch before the
  /// index exists also falls back until the build completes.
  bool get _dbMode => _indexReady && state.selectedAlbumId == null;

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

    // Reclaim any file-cache bloat left by earlier asset.file usage (on iOS
    // that exported full-size copies of originals just to read their lengths).
    unawaited(PhotoManager.clearFileCache());

    _indexReady = (await ref.read(mediaIndexDatabaseProvider).totalCount()) > 0;

    // Keep the index live: when the device library changes (a photo taken,
    // deleted, edited while the app is open), re-sync after a short debounce.
    PhotoManager.addChangeCallback(_onLibraryChanged);
    PhotoManager.startChangeNotify();
    // And reconcile on resume — changes made in the Photos app while we were
    // backgrounded never reach the in-app callback, so this is what keeps a
    // deleted photo from lingering in the grid when the user comes back.
    _lifecycle = _LifecycleObserver(_onAppResumed);
    WidgetsBinding.instance.addObserver(_lifecycle!);
    ref.onDispose(() {
      _changeDebounce?.cancel();
      PhotoManager.removeChangeCallback(_onLibraryChanged);
      PhotoManager.stopChangeNotify();
      final obs = _lifecycle;
      if (obs != null) WidgetsBinding.instance.removeObserver(obs);
    });

    // Load albums (for the strip) + an immediate first page so the grid is
    // never blank. If the index is already built, switch the grid to it now;
    // otherwise the background sync builds it and switches when ready.
    await _loadAlbumsAndAssets();
    if (_dbMode) await _loadIndexSpine();
    unawaited(_ensureSync());
  }

  void _onLibraryChanged(MethodCall _) {
    _changeDebounce?.cancel();
    _changeDebounce = Timer(
      const Duration(seconds: 2),
      () => unawaited(_ensureSync(refresh: true)),
    );
  }

  void _onAppResumed() {
    // A photo may have been deleted/edited in the Photos app while we were
    // away. Re-sync now (no debounce) and force-refresh the source handle so a
    // stale count can't hide the change. Cancel any pending change-debounce so
    // we don't run twice back-to-back.
    _changeDebounce?.cancel();
    unawaited(_ensureSync(refresh: true));
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
    await _reload();
  }

  Future<void> selectAlbum(String? albumId) async {
    if (state.selectedAlbumId == albumId) return;
    state = state.copyWith(
      selectedAlbumId: albumId,
      isLoading: true,
    );
    await _reload();
  }

  Future<void> loadMore() async {
    // Re-entrancy guard: the scroll listener fires loadMore on every frame near
    // the end. Without this, several overlapping calls read the same offset and
    // append the SAME page repeatedly — the cause of duplicated tiles + badges.
    if (_loadingMore || state.isLoading || !state.hasMore) return;
    _loadingMore = true;
    try {
      // Index-backed mode loads the whole spine up front (hasMore == false), so
      // pagination only runs on the album/legacy photo_manager path.
      if (_currentPath == null) return;
      final start = state.assets.length;
      final end = min(state.totalCount, start + _pageSize);
      final more =
          await _currentPath!.getAssetListRange(start: start, end: end);
      // Badge sizes come from the index (every asset's size is there by id),
      // never asset.file. copyWith re-derives displayAssets from the now-seeded
      // sizes, so a client-side size sort stays correct as we page deeper.
      await _seedSizesFromIndex([for (final a in more) a.id]);
      state = state.copyWith(
        assets: [...state.assets, ...more],
        hasMore: end < state.totalCount,
      );
    } finally {
      _loadingMore = false;
    }
  }

  void enterSelectionMode([String? id]) {
    state = state.copyWith(
      isSelecting: true,
      selectedIds: id != null ? {id} : <String>{},
    );
  }

  void toggleSelection(String id, AssetType type) {
    final updated = Set<String>.from(state.selectedIds);
    if (updated.contains(id)) {
      updated.remove(id);
    } else {
      // Single-type lock: a selection can hold photos OR videos, not both.
      // Tapping a different type while one is locked is a no-op (the tile is
      // also shown disabled, so this is just defence-in-depth).
      final lock = state.selectionType;
      if (lock != null && lock != type) return;
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

  /// Replace the whole selection set (used by drag-select, which computes the
  /// dragged-over run in the screen). Always keeps selection mode on.
  void setSelection(Set<String> ids) {
    state = state.copyWith(selectedIds: ids, isSelecting: true);
  }

  Future<void> selectAll() async {
    // Selections are single-type, so select-all picks ONE type: an existing
    // lock if there is one, else the filter's type (defaulting to photos under
    // "All"). Pulled from the index as ids only — no thumbnails load, so 10k+
    // won't blow up. Falls back to the loaded set inside an album / pre-index.
    final lock = state.selectionType;
    final typeIdx = lock != null
        ? lock.index
        : (state.filter == MediaFilter.videos
            ? AssetType.video.index
            : AssetType.image.index);
    if (_indexReady && state.selectedAlbumId == null) {
      final q = queryParamsFor(state.filter, state.sortFilter);
      final ids = await ref.read(mediaIndexDatabaseProvider).matchingIds(
            typeFilter: typeIdx,
            minSize: q.minSize,
            maxSize: q.maxSize,
            formatNeedles: q.formatNeedles,
          );
      state = state.copyWith(selectedIds: ids.toSet(), isSelecting: true);
      return;
    }
    final wantType = AssetType.values[typeIdx];
    final ids = state.entries
        .where((e) => e.type == wantType)
        .map((e) => e.id)
        .toSet();
    state = state.copyWith(selectedIds: ids, isSelecting: true);
  }

  void clearSelection() {
    state = state.copyWith(selectedIds: <String>{}, isSelecting: false);
  }

  Future<void> setSortFilter(LibrarySortFilter sortFilter) async {
    state = state.copyWith(sortFilter: sortFilter, isLoading: true);
    await _reload();
  }

  Future<void> clearSortFilter() async {
    if (!state.sortFilter.hasAnyActive) return;
    await setSortFilter(LibrarySortFilter.cleared);
  }

  // ── Private ────────────────────────────────────────────────────

  /// Routes a fresh load to the index (whole-library, no asset.file) or, inside
  /// an album / before the index is built, the legacy photo_manager path.
  Future<void> _reload() async {
    if (_dbMode) {
      await _loadIndexSpine();
    } else {
      await _loadAlbumsAndAssets();
    }
  }

  /// Pulls resolved sizes for [ids] from the index into the badge cache — never
  /// asset.file. The index holds every asset's size by id regardless of album,
  /// so the legacy/album path can show badges without exporting files.
  Future<void> _seedSizesFromIndex(List<String> ids) async {
    if (ids.isEmpty) return;
    final sizes = await ref.read(mediaIndexDatabaseProvider).sizesFor(ids);
    AssetSizeCache.putAll(sizes);
  }

  /// Background: bring the index up to date, then refresh the view if the user
  /// is sorting/filtering so results expand to the whole library. Pass
  /// [refresh] after a device-library change (or app resume) to first drop the
  /// source's cached handle so a stale count can't mask the change.
  Future<void> _ensureSync({bool refresh = false}) async {
    if (_syncing) return;
    _syncing = true;
    try {
      final index = ref.read(mediaIndexServiceProvider);
      final db = ref.read(mediaIndexDatabaseProvider);
      if (refresh) index.invalidateSource();
      final removed = await index.syncMetadata();
      // Drop deleted assets from the entity cache at once so the grid stops
      // rendering their (now-dangling) thumbnails before the spine reloads.
      for (final id in removed) {
        AssetEntityCache.evict(id);
      }
      _indexReady = (await db.totalCount()) > 0;
      if (_dbMode) await _loadIndexSpine();
      await index.resolveSizes();
      // Refresh the spine once sizes are in so every badge fills (and a
      // size-sort re-orders), not just the eagerly-resolved first screens.
      if (_dbMode) await _loadIndexSpine();
    } catch (_) {
      // Best-effort: the photo_manager path keeps the library usable.
    } finally {
      _syncing = false;
    }
  }

  /// Load the WHOLE matching library as a lightweight spine (ids + metadata,
  /// no AssetEntities). The grid renders every row (childCount = total) and
  /// materialises each cell's entity lazily on scroll-in, so 10k+ never blocks
  /// or bloats. Eagerly resolves byte sizes for the first few screens so top
  /// badges appear at once; the background pass fills the rest.
  Future<void> _loadIndexSpine() async {
    final db = ref.read(mediaIndexDatabaseProvider);
    final q = queryParamsFor(state.filter, state.sortFilter);

    final rows = await db.entries(
      typeFilter: q.typeFilter,
      minSize: q.minSize,
      maxSize: q.maxSize,
      formatNeedles: q.formatNeedles,
      sortColumn: q.sortColumn,
      descending: q.descending,
    );

    // Eagerly resolve sizes for the first screenfuls that lack one, so the
    // visible badges aren't blank while the background pass works the tail.
    final firstMissing = <String>[];
    for (final r in rows) {
      if (r.sizeBytes == null) {
        firstMissing.add(r.id);
        if (firstMissing.length >= _pageSize * 3) break;
      }
    }
    final fresh = firstMissing.isEmpty
        ? const <String, int>{}
        : await ref
            .read(mediaIndexServiceProvider)
            .resolveSizesFor(firstMissing);

    int? sizeOf(MediaAsset r) {
      final s = r.sizeBytes;
      if (s != null && s > 0) return s;
      final f = fresh[r.id];
      return (f != null && f > 0) ? f : null;
    }

    final entries = <LibraryEntry>[
      for (final r in rows)
        LibraryEntry(
          id: r.id,
          type: AssetType.values[r.type],
          sizeBytes: sizeOf(r),
          durationSeconds: (r.durationMs / 1000).round(),
          created: r.createdDate > 0
              ? DateTime.fromMillisecondsSinceEpoch(r.createdDate * 1000)
              : null,
        ),
    ];
    // Mirror known sizes into the badge cache (used by the legacy badge path
    // and any cell that reads it directly).
    AssetSizeCache.putAll({
      for (final e in entries)
        if (e.sizeBytes != null) e.id: e.sizeBytes!,
    });

    state = state.copyWith(
      // The spine is the whole library; raw entities are materialised per-cell.
      entries: entries,
      assets: const [],
      displayAssets: const [],
      totalCount: entries.length,
      hasMore: false,
      isLoading: false,
    );
  }

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
      // Seed badge sizes from the index before copyWith re-derives the display
      // list — so a client-side size sort here is correct, and no asset.file.
      await _seedSizesFromIndex([for (final a in raw) a.id]);

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

  /// Pure mapping from the high-level filter/sort to index query params. Kept
  /// static + free of state so it can be unit-tested directly. Size-bucket
  /// boundaries mirror the client-side path in [LibraryState._computeDisplay].
  static ({
    int? typeFilter,
    int? minSize,
    int? maxSize,
    List<String> formatNeedles,
    AssetSortColumn sortColumn,
    bool descending,
  }) queryParamsFor(MediaFilter filter, LibrarySortFilter sf) {
    final typeFilter = switch (filter) {
      MediaFilter.all => null,
      MediaFilter.photos => AssetType.image.index,
      MediaFilter.videos => AssetType.video.index,
    };

    int? minSize;
    int? maxSize;
    switch (sf.sizeFilter) {
      case LibrarySizeFilter.any:
        break;
      case LibrarySizeFilter.small:
        maxSize = 1024 * 1024;
      case LibrarySizeFilter.medium:
        minSize = 1024 * 1024;
        maxSize = 10 * 1024 * 1024;
      case LibrarySizeFilter.large:
        minSize = 10 * 1024 * 1024;
    }

    final needles = <String>[];
    final fmt = sf.formatFilter;
    if (fmt != null) {
      if (fmt == 'jpeg') {
        needles.addAll(['jpeg', 'jpg']);
      } else if (fmt == 'mov') {
        needles.addAll(['mov', 'quicktime']);
      } else {
        needles.add(fmt);
      }
    }

    final (AssetSortColumn sortColumn, bool descending) = switch (sf.sort) {
      LibrarySort.newestFirst => (AssetSortColumn.createdDate, true),
      LibrarySort.oldestFirst => (AssetSortColumn.createdDate, false),
      LibrarySort.largestFirst => (AssetSortColumn.sizeBytes, true),
      LibrarySort.smallestFirst => (AssetSortColumn.sizeBytes, false),
    };

    return (
      typeFilter: typeFilter,
      minSize: minSize,
      maxSize: maxSize,
      formatNeedles: needles,
      sortColumn: sortColumn,
      descending: descending,
    );
  }
}

final libraryProvider =
    NotifierProvider<LibraryNotifier, LibraryState>(LibraryNotifier.new);

/// Exposes the Library grid's scroll controller so the shell can jump it to the
/// top when the user re-taps the active Library tab. This is the reliable
/// substitute for the iOS status-bar tap, which the new scene-based iOS
/// template does not deliver to the app (flutter/flutter#182403).
final libraryScrollControllerProvider =
    StateProvider<ScrollController?>((ref) => null);

/// The spine index the detail viewer is currently showing. The grid seeds it on
/// open and reads it back when the viewer pops, so exiting returns you to the
/// photo you navigated TO (after swiping through siblings), not the one you
/// entered from. Null while no viewer is open.
final detailFocusIndexProvider = StateProvider<int?>((ref) => null);
