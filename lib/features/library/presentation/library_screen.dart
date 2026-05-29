import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/motion.dart';
import '../../../shared/widgets/widgets.dart';
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

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  // Shared explicitly so BOTH the grid (via primary) and the Scaffold (via
  // PrimaryScrollController.maybeOf in handleStatusBarTap) reference the SAME
  // controller — that link is what makes the iOS status-bar tap scroll to top,
  // and it was missing before (no PrimaryScrollController in scope).
  final ScrollController _primaryController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(libraryProvider.notifier).init();
    });
  }

  @override
  void dispose() {
    _primaryController.dispose();
    super.dispose();
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
          // ── Large-title app bar ─────────────────────────────────────────
          SliverAppBar.large(
            pinned: true,
            stretch: true,
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
                      final visibleIds = state.displayAssets
                          .map((a) => a.id)
                          .toSet();
                      final allSelected = visibleIds.isNotEmpty &&
                          visibleIds.every(state.selectedIds.contains);
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
            expandedHeight: 112,
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
          if (state.isLoading && state.assets.isNotEmpty)
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
    if (state.isLoading && state.assets.isEmpty) {
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
    if (state.assets.isEmpty && !state.isLoading) {
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

    // Has assets → grid (display list applies sort/size/format filters)
    final visible = state.displayAssets;
    return [
      SliverPadding(
        // Edge-to-edge: thumbnails reach the screen edges (no dark side
        // strips). Gaps between tiles remain.
        padding: EdgeInsets.zero,
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: AppSpacing.gridGap,
            mainAxisSpacing: AppSpacing.gridGap,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final asset = visible[index];
              return HaynStagger(
                index: index,
                child: MediaThumbnail(
                  key: ValueKey(asset.id),
                  asset: asset,
                  isSelected: state.selectedIds.contains(asset.id),
                  isSelecting: state.isSelecting,
                  showSize: !state.isSelecting,
                  onTap: () => _onTap(asset),
                  onLongPress: () => _onLongPress(asset),
                ),
              );
            },
            childCount: visible.length,
          ),
        ),
      ),
    ];
  }

  void _onTap(AssetEntity asset) {
    final state = ref.read(libraryProvider);
    if (state.isSelecting) {
      ref.read(libraryProvider.notifier).toggleSelection(asset.id);
      return;
    }
    HapticFeedback.selectionClick();
    // iOS PhotoKit ids look like `UUID/L0/001` — the slashes would be read as
    // extra path segments and miss the `/asset/:id` route (Android ids are
    // plain numbers, so this only ever bit iOS). Encode so the id stays a
    // single segment; go_router decodes it back on the other side.
    context.push('/asset/${Uri.encodeComponent(asset.id)}');
  }

  void _onLongPress(AssetEntity asset) {
    ref.read(libraryProvider.notifier).enterSelectionMode(asset.id);
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
