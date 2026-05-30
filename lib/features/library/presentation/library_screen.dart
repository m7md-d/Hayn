import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: CustomScrollView(
          controller: _primaryController,
          physics: const BouncingScrollPhysics(
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
                child: MediaThumbnail(
                  key: ValueKey(entry.id),
                  id: entry.id,
                  type: entry.type,
                  sizeBytes: entry.sizeBytes,
                  durationSeconds: entry.durationSeconds,
                  isSelected: state.selectedIds.contains(entry.id),
                  isSelecting: state.isSelecting,
                  showSize: !state.isSelecting,
                  onTap: () => _onTap(entry.id, index),
                  onLongPress: () => _onLongPress(entry.id),
                ),
              );
            },
            childCount: entries.length,
          ),
        ),
      ),
    ];
  }

  Future<void> _onTap(String id, int index) async {
    final notifier = ref.read(libraryProvider.notifier);
    if (ref.read(libraryProvider).isSelecting) {
      notifier.toggleSelection(id);
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

  void _onLongPress(String id) {
    ref.read(libraryProvider.notifier).enterSelectionMode(id);
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
