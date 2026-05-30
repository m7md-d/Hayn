import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderMetaData, BoxHitTestResult;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart' show AssetType;
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/motion.dart';
import '../../../shared/widgets/widgets.dart';
import '../../tasks/presentation/widgets/tasks_app_bar_button.dart';
import '../domain/entities/media_filter.dart';
import 'providers/library_provider.dart';
import 'widgets/album_picker_sheet.dart';
import 'widgets/album_strip.dart';
import 'widgets/media_thumbnail.dart';
import 'widgets/sort_filter_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LibraryScreen — root of the Library tab. Hosts:
//   • Large title that doubles as the selection-count display
//   • Cancel leading appears only in selection mode
//   • Filter pill (All / Photos / Videos)
//   • Album strip (when more than one album exists)
//   • Media grid with pagination + selection
//
// Selection toolbar is rendered by AppShell (outer scaffold), not here — keeps
// the bottom UI single-source-of-truth.
// ─────────────────────────────────────────────────────────────────────────────

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with WidgetsBindingObserver {
  final ScrollController _primaryController = ScrollController();

  // 3-column square grid geometry, cached per build for the return-to-current
  // scroll math (see _scrollGridToFocus).
  static const int _crossAxisCount = 3;
  double _rowStride = 1;

  // Captured when a tile is tapped, so on return we can place the photo the
  // user landed on at the same screen position the tapped tile occupied.
  int _enterIndex = 0;
  double _enterOffset = 0;

  // ── Drag-to-select (long-press a tile, then drag across the grid) ────────
  // A Listener over the grid observes the raw pointer (it never enters the
  // gesture arena, so the tile's long-press + our drag coexist). The tile under
  // the finger is found by hit-testing for its MetaData(index) — no fragile
  // sliver geometry. Auto-scrolls when the finger nears the top/bottom edge.
  final GlobalKey _gridListenerKey = GlobalKey();
  bool _dragSelecting = false;
  int _dragAnchorIndex = 0;
  AssetType? _dragType;
  Set<String> _dragBase = const {};
  int? _dragLastIndex;
  Offset? _lastDragLocalPos;
  Timer? _autoScrollTimer;
  double _autoScrollDir = 0;

  @override
  void initState() {
    super.initState();
    // Observe status-bar taps ourselves: ScaffoldState gates its own handler
    // behind a hit-test at the screen origin that the FloatingTasksBadge
    // overlay + RTL shell defeat (flutter/flutter#182403). A direct observer
    // bypasses that and reliably scrolls our grid to the top.
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(libraryProvider.notifier).init();
      // Publish the controller so the shell can scroll-to-top on tab re-tap.
      ref.read(libraryScrollControllerProvider.notifier).state =
          _primaryController;
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _primaryController.dispose();
    super.dispose();
  }

  @override
  void handleStatusBarTap() {
    if (!_primaryController.hasClients || _primaryController.offset <= 0) return;
    HapticFeedback.selectionClick();
    _primaryController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  // Pagination is driven by scroll notifications, so the grid keeps a stable
  // controller. The loadMore re-entrancy guard makes the high-frequency firing
  // here harmless.
  bool _onScrollNotification(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 800) {
      ref.read(libraryProvider.notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryProvider);
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final theme = Theme.of(context);
    final notifier = ref.read(libraryProvider.notifier);

    // Follow the open detail viewer LIVE: as the user swipes/scrubs to another
    // photo, scroll the grid (under the transparent overlay) to that cell, so
    // closing the viewer shrinks the Hero straight into the visible tile.
    ref.listen<int?>(detailFocusIndexProvider, (_, next) {
      if (next != null) _followGrid(next);
    });

    final title = state.isSelecting
        ? l.librarySelectedCount(state.selectedIds.length)
        : l.libraryTitle;

    return PrimaryScrollController(
      // The Scaffold's handleStatusBarTap reads PrimaryScrollController.maybeOf
      // — provide it here so it resolves to the same controller the grid uses.
      controller: _primaryController,
      child: Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Listener(
        key: _gridListenerKey,
        onPointerMove: _onDragPointerMove,
        onPointerUp: _onDragPointerEnd,
        onPointerCancel: _onDragPointerEnd,
        child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: CustomScrollView(
          controller: _primaryController,
          // Freeze the list while drag-selecting so a vertical drag selects
          // tiles instead of scrolling; our own edge auto-scroll handles paging.
          physics: _dragSelecting
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
          slivers: [
          // ── Pinned title bar — title + actions stay at the top at all
          // times (no large collapsing title), per the request to keep the
          // title up with the buttons.
          SliverAppBar(
            pinned: true,
            centerTitle: false,
            titleSpacing: AppSpacing.md,
            backgroundColor: theme.scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            shadowColor: hc.border,
            scrolledUnderElevation: 0.5,
            automaticallyImplyLeading: false,
            leading: state.isSelecting
                ? Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        notifier.clearSelection();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsetsDirectional.only(
                            start: AppSpacing.md, end: AppSpacing.s2),
                      ),
                      child: Text(l.selectionCancel),
                    ),
                  )
                : null,
            leadingWidth: state.isSelecting ? 80 : null,
            title: Text(title),
            actions: state.isSelecting
                ? [
                    // Toggle select-all / deselect-all so the user doesn't
                    // need to tap every tile to act on a full filter.
                    Builder(builder: (ctx) {
                      // "All selected" when the selection covers the whole
                      // spine — compared by count so it's O(1), not O(10k).
                      final allSelected = state.entries.isNotEmpty &&
                          state.selectedIds.length >= state.entries.length;
                      return IconButton(
                        tooltip: allSelected
                            ? l.librarySelectionClearAll
                            : l.librarySelectAll,
                        icon: Icon(allSelected
                            ? Icons.deselect_rounded
                            : Icons.select_all_rounded),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          if (allSelected) {
                            notifier.clearSelection();
                            // Re-enter selection mode (empty selection) so
                            // the user stays in the picker.
                            notifier.enterSelectionMode();
                          } else {
                            notifier.selectAll();
                          }
                        },
                      );
                    }),
                  ]
                : [
                    const TasksAppBarButton(),
                    if (state.permissionStatus ==
                        LibraryPermissionStatus.limited)
                      IconButton(
                        tooltip: l.libraryPermissionButton,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        onPressed: notifier.openSettings,
                      ),
                    // Explicit entry point into selection mode — long-press
                    // on a tile still works, but a button is faster.
                    IconButton(
                      tooltip: l.librarySelectMode,
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        notifier.enterSelectionMode();
                      },
                    ),
                    IconButton(
                      tooltip: l.librarySortAndFilter,
                      icon: Icon(
                        state.sortFilter.hasAnyActive
                            ? Icons.filter_alt_rounded
                            : Icons.tune_rounded,
                        color: state.sortFilter.hasAnyActive ? hc.accent : null,
                      ),
                      onPressed: () => _openSortFilter(context, state, notifier),
                    ),
                  ],
            systemOverlayStyle: theme.brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
          ),

          // ── Filter pill ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md, 0, AppSpacing.md, AppSpacing.s3,
              ),
              child: HaynSegmentedPill<MediaFilter>(
                value: state.filter,
                onChanged: notifier.setFilter,
                items: [
                  HaynSegmentItem(value: MediaFilter.all, label: l.filterAll),
                  HaynSegmentItem(
                      value: MediaFilter.photos, label: l.filterPhotos),
                  HaynSegmentItem(
                      value: MediaFilter.videos, label: l.filterVideos),
                ],
              ),
            ),
          ),

          // ── Album strip (only when more than one album exists) ──────────
          if (state.albums.length > 1 &&
              state.permissionStatus != LibraryPermissionStatus.denied)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                    bottom: AppSpacing.s3),
                child: AlbumStrip(
                  albums: state.albums,
                  selectedId: state.selectedAlbumId,
                  onSelected: notifier.selectAlbum,
                  onMoreTap: state.albums.length > 5
                      ? () => _openAlbumPicker(context, state, notifier)
                      : null,
                ),
              ),
            ),

          // ── Limited-access banner ───────────────────────────────────────
          if (state.permissionStatus == LibraryPermissionStatus.limited)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.s3,
                ),
                child: HaynInlineBanner(
                  tone: HaynBannerTone.info,
                  icon: Icons.lock_outline_rounded,
                  message: l.libraryPermissionMessage,
                  action: TextButton(
                    onPressed: notifier.openSettings,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text(l.libraryPermissionButton),
                  ),
                ),
              ),
            ),

          // ── Content (state-aware) ───────────────────────────────────────
          ..._buildContentSlivers(state, l, notifier),

          // ── Pagination loading footer ─────────────────────────────────
          if (state.isLoading && state.entries.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(
                  child: SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: hc.text3,
                    ),
                  ),
                ),
              ),
            ),

          // Padding for bottom nav / safe area
          const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
        ],
        ),
        ),
      ),
      ),
    );
  }

  List<Widget> _buildContentSlivers(
    LibraryState state,
    AppLocalizations l,
    LibraryNotifier notifier,
  ) {
    // Loading first page → skeleton grid
    if (state.isLoading && state.entries.isEmpty) {
      return [
        SliverPadding(
          padding: EdgeInsets.zero,
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: AppSpacing.gridGap,
              mainAxisSpacing: AppSpacing.gridGap,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, __) => HaynShimmerGroup(
                child: HaynSkeleton.rect(
                  width: double.infinity,
                  height: double.infinity,
                  radius: 0,
                ),
              ),
              childCount: 30,
            ),
          ),
        ),
      ];
    }

    // Permission denied → empty-state CTA
    if (state.permissionStatus == LibraryPermissionStatus.denied) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: HaynEmptyState(
            icon: Icons.photo_library_outlined,
            title: l.libraryPermissionTitle,
            message: l.libraryPermissionMessage,
            actionLabel: l.libraryPermissionButton,
            actionIcon: Icons.lock_open_rounded,
            onAction: notifier.openSettings,
          ),
        ),
      ];
    }

    // Permission granted but no media
    if (state.entries.isEmpty && !state.isLoading) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: HaynEmptyState(
            icon: Icons.photo_outlined,
            title: l.libraryEmptyTitle,
            message: l.libraryEmptyMessage,
          ),
        ),
      ];
    }

    // Has assets → virtualized grid over the whole spine. childCount is the
    // real total (10k+); each cell materialises its entity lazily on
    // scroll-in, so nothing is loaded until it's about to be seen.
    final entries = state.entries;
    // The type the selection is locked to (null = nothing selected). Other-type
    // tiles render disabled so photos and videos can't be mixed in one batch.
    final lockType = state.selectionType;
    // Cache the row stride for the return-to-current scroll math.
    final width = MediaQuery.sizeOf(context).width;
    final tileExtent =
        (width - (_crossAxisCount - 1) * AppSpacing.gridGap) / _crossAxisCount;
    _rowStride = tileExtent + AppSpacing.gridGap;
    return [
      SliverPadding(
        // Edge-to-edge: thumbnails reach the screen edges (no dark side
        // strips). Gaps between tiles remain.
        padding: EdgeInsets.zero,
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _crossAxisCount,
            crossAxisSpacing: AppSpacing.gridGap,
            mainAxisSpacing: AppSpacing.gridGap,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final entry = entries[index];
              return HaynStagger(
                index: index,
                // MetaData carries the grid index so drag-select can find the
                // tile under the finger by hit-testing (no sliver geometry).
                child: MetaData(
                  metaData: index,
                  child: MediaThumbnail(
                    key: ValueKey(entry.id),
                    id: entry.id,
                    type: entry.type,
                    sizeBytes: entry.sizeBytes,
                    durationSeconds: entry.durationSeconds,
                    isSelected: state.selectedIds.contains(entry.id),
                    isSelecting: state.isSelecting,
                    // Size badge stays visible during selection now.
                    showSize: true,
                    disabled: lockType != null && entry.type != lockType,
                    onTap: () => _onTap(entry.id, index, entry.type),
                    onLongPress: () =>
                        _onLongPress(entry.id, index, entry.type),
                  ),
                ),
              );
            },
            childCount: entries.length,
          ),
        ),
      ),
    ];
  }

  Future<void> _onTap(String id, int index, AssetType type) async {
    final notifier = ref.read(libraryProvider.notifier);
    if (ref.read(libraryProvider).isSelecting) {
      notifier.toggleSelection(id, type);
      return;
    }
    HapticFeedback.selectionClick();
    // Remember where we entered so we can land the photo the user swiped to at
    // the same spot when the viewer closes.
    _enterIndex = index;
    _enterOffset = _primaryController.hasClients ? _primaryController.offset : 0;
    ref.read(detailFocusIndexProvider.notifier).state = index;
    // iOS PhotoKit ids look like `UUID/L0/001` — the slashes would be read as
    // extra path segments and miss the `/asset/:id` route (Android ids are
    // plain numbers, so this only ever bit iOS). Encode so the id stays a
    // single segment; go_router decodes it back on the other side.
    await context.push('/asset/${Uri.encodeComponent(id)}');
    if (!mounted) return;
    // The grid already followed the viewer live (see the listener in build),
    // so the Hero close shrinks straight into the on-screen cell. Just clear
    // the focus marker.
    ref.read(detailFocusIndexProvider.notifier).state = null;
  }

  /// Position the grid so the [focus] cell sits where the tapped cell was, via
  /// a RELATIVE offset (so the app-bar/strip heights cancel out and we don't
  /// need to measure them). Instant: the detail route is a transparent overlay,
  /// so moving the grid underneath means the Hero close lands on the right
  /// on-screen tile instead of flying to a stale (or off-screen) position.
  void _followGrid(int focus) {
    if (!_primaryController.hasClients) return;
    final rowDelta =
        (focus ~/ _crossAxisCount) - (_enterIndex ~/ _crossAxisCount);
    final target = (_enterOffset + rowDelta * _rowStride)
        .clamp(0.0, _primaryController.position.maxScrollExtent);
    if ((_primaryController.offset - target).abs() < 0.5) return;
    _primaryController.jumpTo(target);
  }

  // ── Drag-to-select ───────────────────────────────────────────────────────

  void _onLongPress(String id, int index, AssetType type) {
    final st = ref.read(libraryProvider);
    final lock = st.selectionType;
    // Anchoring on a different type than the current lock isn't allowed.
    if (st.isSelecting && lock != null && lock != type) return;

    final base = st.isSelecting ? Set<String>.from(st.selectedIds) : <String>{};
    base.add(id);
    ref.read(libraryProvider.notifier).setSelection(base);

    setState(() {
      _dragSelecting = true;
      _dragAnchorIndex = index;
      _dragType = type;
      _dragBase = base;
      _dragLastIndex = index;
    });
  }

  void _onDragPointerMove(PointerMoveEvent e) {
    if (!_dragSelecting) return;
    _lastDragLocalPos = e.localPosition;
    _maybeAutoScroll(e.localPosition);
    final idx = _indexUnderPointer(e.localPosition);
    if (idx == null || idx == _dragLastIndex) return;
    _dragLastIndex = idx;
    _applyDragRange(idx);
  }

  void _onDragPointerEnd(PointerEvent e) {
    if (!_dragSelecting) return;
    _stopAutoScroll();
    setState(() {
      _dragSelecting = false;
      _dragType = null;
      _dragLastIndex = null;
      _lastDragLocalPos = null;
    });
  }

  /// Hit-test the tile under [localPos] (relative to the grid Listener) and read
  /// its MetaData index — no sliver geometry, robust to the pinned header.
  int? _indexUnderPointer(Offset localPos) {
    final box = _gridListenerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final result = BoxHitTestResult();
    box.hitTest(result, position: localPos);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData is int) {
        return target.metaData as int;
      }
    }
    return null;
  }

  /// Select the run [anchor..current] (single-type) on top of the pre-drag
  /// base, so dragging forward extends and dragging back releases the overshoot.
  void _applyDragRange(int current) {
    final entries = ref.read(libraryProvider).entries;
    if (entries.isEmpty) return;
    final lo = _dragAnchorIndex < current ? _dragAnchorIndex : current;
    final hi = _dragAnchorIndex < current ? current : _dragAnchorIndex;
    final sel = Set<String>.from(_dragBase);
    for (var i = lo; i <= hi && i < entries.length; i++) {
      final entry = entries[i];
      if (entry.type == _dragType) sel.add(entry.id);
    }
    ref.read(libraryProvider.notifier).setSelection(sel);
  }

  // Auto-scroll while the finger sits near the top/bottom edge during a drag.
  void _maybeAutoScroll(Offset localPos) {
    final box = _gridListenerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    const edge = 96.0;
    final h = box.size.height;
    double dir = 0;
    if (localPos.dy < edge) {
      dir = -1;
    } else if (localPos.dy > h - edge) {
      dir = 1;
    }
    if (dir == 0) {
      _stopAutoScroll();
      return;
    }
    _autoScrollDir = dir;
    if (_autoScrollTimer != null) return;
    _autoScrollTimer =
        Timer.periodic(const Duration(milliseconds: 16), (_) => _autoScrollTick());
  }

  void _autoScrollTick() {
    if (!_dragSelecting || !_primaryController.hasClients) {
      _stopAutoScroll();
      return;
    }
    final pos = _primaryController.position;
    final next = (_primaryController.offset + _autoScrollDir * 14)
        .clamp(0.0, pos.maxScrollExtent);
    if (next == _primaryController.offset) return; // hit an end
    _primaryController.jumpTo(next);
    // Tiles moved under the stationary finger → re-evaluate the run.
    final lp = _lastDragLocalPos;
    if (lp != null) {
      final idx = _indexUnderPointer(lp);
      if (idx != null && idx != _dragLastIndex) {
        _dragLastIndex = idx;
        _applyDragRange(idx);
      }
    }
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDir = 0;
  }

  Future<void> _openAlbumPicker(
    BuildContext context,
    LibraryState state,
    LibraryNotifier notifier,
  ) async {
    final result = await showAlbumPicker(
      context: context,
      albums: state.albums,
      currentId: state.selectedAlbumId,
    );
    if (result != state.selectedAlbumId) {
      await notifier.selectAlbum(result);
    }
  }

  Future<void> _openSortFilter(
    BuildContext context,
    LibraryState state,
    LibraryNotifier notifier,
  ) async {
    final result = await showSortFilterSheet(
      context: context,
      current: state.sortFilter,
    );
    if (result != null && result != state.sortFilter) {
      await notifier.setSortFilter(result);
    }
  }
}
