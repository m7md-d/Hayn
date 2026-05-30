import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../core/isolates/task_runner.dart';
import '../../../shared/widgets/widgets.dart';
import '../../image_ops/data/metadata.dart';
import '../../image_ops/data/strip_metadata_task.dart';
import 'providers/asset_entity_cache.dart';
import 'providers/library_provider.dart';
import 'providers/thumbnail_cache.dart';
import 'widgets/asset_filmstrip.dart';
import 'widgets/asset_metadata_sheet.dart';
import 'widgets/asset_video_player.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AssetDetailScreen — full-screen photo/video viewer with horizontal swipe
// between siblings. UI auto-hides on single tap. Pinch + double-tap to zoom.
//
// Hero tag uses the asset id, matching MediaThumbnail in the Library grid.
// Sibling list is read from libraryProvider so swiping never goes stale.
// ─────────────────────────────────────────────────────────────────────────────

class AssetDetailScreen extends ConsumerStatefulWidget {
  const AssetDetailScreen({required this.assetId, super.key});
  final String assetId;

  @override
  ConsumerState<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends ConsumerState<AssetDetailScreen> {
  PageController? _ctrl;
  int _currentIndex = 0;
  bool _uiVisible = true;
  // The spine (ids + light metadata) shared with the grid. Pages materialise
  // their AssetEntity lazily, so this can span the whole 10k library.
  List<LibraryEntry> _entries = const [];

  /// True when opened on an asset that isn't in the library spine (e.g. a
  /// task's freshly-saved output). We then keep a one-item spine and don't
  /// adopt the live library entries in build.
  bool _standalone = false;

  /// Fade factor for the bottom action bar — driven by the active page's
  /// inline info sheet (0 = sheet closed, 1 = sheet fully open). The bar
  /// fades out while the sheet rises so they never visually overlap.
  double _infoProgress = 0;

  /// Mirrors the active page's zoom state. While true the PageView is locked
  /// (NeverScrollableScrollPhysics) so 2-finger pinches can't be hijacked as
  /// horizontal swipes to neighbouring assets.
  bool _zoomLocked = false;

  @override
  void initState() {
    super.initState();
    _entries = ref.read(libraryProvider).entries;
    final found = _entries.indexWhere((e) => e.id == widget.assetId);
    if (found < 0) {
      // The id isn't in the current spine — e.g. opened straight from a task's
      // "View" before the index has synced the freshly-saved asset. Stand up a
      // one-item spine for exactly this asset so the viewer shows the right
      // photo instead of silently landing on library item #0. The page
      // materialises the real AssetEntity by id, so the type here is just a
      // placeholder.
      _entries = [LibraryEntry(id: widget.assetId, type: AssetType.image)];
      _currentIndex = 0;
      _standalone = true;
    } else {
      _currentIndex = found;
    }
    _ctrl = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(detailFocusIndexProvider.notifier).state = _currentIndex;
    });
    _preloadNeighbors(_currentIndex);
  }

  /// Warms the immediate neighbours' SMALL (360-px) thumbnail through the
  /// shared bounded cache so the next swipe shows something instantly. The
  /// crisp 1080-px version is loaded by the page itself only once it's the
  /// active one (see [_AssetPageState._scheduleHiRes]) — decoding full-res for
  /// neighbours is what made scrubbing large photos lurch.
  void _preloadNeighbors(int index) {
    for (final offset in const [-1, 1]) {
      final i = index + offset;
      if (i < 0 || i >= _entries.length) continue;
      final id = _entries[i].id;
      if (ThumbnailCache.get(id) != null) continue;
      AssetEntityCache.load(id).then((asset) {
        if (asset != null) ThumbnailCache.load(asset);
      });
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  void _toggleUi() {
    HapticFeedback.selectionClick();
    setState(() => _uiVisible = !_uiVisible);
  }

  void _onPageChanged(int i) {
    setState(() {
      _currentIndex = i;
      // A fresh asset starts with no info-sheet pull-in.
      _infoProgress = 0;
    });
    // Report the focused index so closing the viewer returns the grid here.
    ref.read(detailFocusIndexProvider.notifier).state = i;
    _preloadNeighbors(i);
    // Album/legacy mode loads in pages — pull more as we approach the end so
    // swiping never dead-ends. No-op in index-backed mode (whole spine loaded).
    if (i >= _entries.length - 5) {
      ref.read(libraryProvider.notifier).loadMore();
    }
  }

  void _jumpToIndex(int i) {
    if (_ctrl == null) return;
    HapticFeedback.selectionClick();
    _ctrl!.animateToPage(
      i,
      duration: AppDuration.normal,
      curve: AppCurves.standard,
    );
  }

  /// Live follow while the filmstrip is scrubbed: snap the main image to the
  /// centred tile instantly (no animation). `onPageChanged` syncs _currentIndex.
  void _scrubToIndex(int i) {
    if (_ctrl == null || i == _currentIndex) return;
    _ctrl!.jumpToPage(i);
  }

  Future<void> _openInfo(BuildContext context) async {
    final asset = await AssetEntityCache.load(_entries[_currentIndex].id);
    if (asset == null || !context.mounted) return;
    showHaynSheet(
      context: context,
      builder: (_) => AssetMetadataSheet(asset: asset),
    );
  }

  void _action(String name) {
    HapticFeedback.lightImpact();
    final l = AppLocalizations.of(context);
    HaynSnack.info(context, l.assetDetailComingSoon(name));
  }

  // iOS PhotoKit ids contain '/' (e.g. UUID/L0/001); a raw interpolation into
  // a `/route/:id` path splits into extra segments and the target screen
  // resolves the wrong (or no) asset. Encode so the id stays one segment;
  // go_router decodes pathParameters back on the other side.
  String get _curId => _entries[_currentIndex].id;
  String get _curIdPath => Uri.encodeComponent(_curId);

  void _compress() {
    HapticFeedback.lightImpact();
    context.push('/compress', extra: [_curId]);
  }

  void _crop() {
    HapticFeedback.lightImpact();
    context.push('/crop/$_curIdPath');
  }

  void _surgical() {
    HapticFeedback.lightImpact();
    context.push('/surgical/$_curIdPath');
  }

  void _videoEdit() {
    HapticFeedback.lightImpact();
    context.push('/video-edit/$_curIdPath');
  }

  void _trim() {
    HapticFeedback.lightImpact();
    context.push('/trim/$_curIdPath');
  }

  void _cropVideo() {
    HapticFeedback.lightImpact();
    context.push('/crop-video/$_curIdPath');
  }

  void _removeAudio() {
    HapticFeedback.lightImpact();
    context.push('/remove-audio/$_curIdPath');
  }

  Future<void> _stripMetadata() async {
    final l = AppLocalizations.of(context);
    final id = _entries[_currentIndex].id;
    // Peek at what's actually there — skip the whole flow if there's nothing
    // to remove (no pointless clean-copy).
    final entity = await AssetEntityCache.load(id);
    final bytes = await entity?.originBytes;
    if (!mounted) return;
    if (bytes != null) {
      // HEIC & co. have no lossless pure-Dart stripper — tell the user up front
      // (and point them at Compress) instead of queuing a task that just skips.
      if (!MetadataStripper.canStrip(bytes)) {
        HaynSnack.info(context, l.stripHeicUnsupported);
        return;
      }
      final summary = await MetadataReader.read(bytes);
      if (!mounted) return;
      if (summary.isEmpty) {
        HaynSnack.info(context, l.stripNothingFound);
        return;
      }
    }
    final ok = await showHaynDestructiveConfirm(
      context: context,
      title: l.toolStripMetadata,
      message: l.toolStripDesc,
      confirmLabel: l.commonContinue,
      cancelLabel: l.commonCancel,
      icon: Icons.auto_fix_high_rounded,
      reassurance: l.settingsPrivacy,
    );
    if (!ok || !mounted) return;
    unawaited(
      ref.read(taskRunnerProvider.notifier).enqueue(
            StripMetadataTask(assetIds: [id]),
          ),
    );
    HaynSnack.success(context, l.stripMetadataQueued(1));
  }

  @override
  Widget build(BuildContext context) {
    // Track spine growth (album/legacy load-more) so swiping never dead-ends —
    // but only in the normal in-library case. A standalone viewer (task output
    // not yet in the spine) keeps its one-item spine.
    if (!_standalone) {
      _entries = ref.watch(libraryProvider.select((s) => s.entries));
    }
    if (_entries.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    if (_currentIndex >= _entries.length) _currentIndex = _entries.length - 1;

    final l = AppLocalizations.of(context);
    final isVideo = _entries[_currentIndex].isVideo;

    // Transparent scaffold so the rubber-band dismiss can fade the bg down to
    // fully transparent (the library tab shows through). A black Container
    // sits below the image and its alpha is keyed to the drag progress.
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: AnimatedSlide(
          duration: AppDuration.normal,
          curve: AppCurves.standard,
          offset: _uiVisible ? Offset.zero : const Offset(0, -1),
          child: Opacity(
            opacity: _uiVisible
                ? (1.0 - _infoProgress * 0.6).clamp(0.0, 1.0)
                : 0.0,
            child: _DetailAppBar(
              title: _titleFor(_entries[_currentIndex]),
              onInfo: () => _openInfo(context),
              onMore: () => _action(l.selectionMore),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background tap surface — toggles UI
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleUi,
            ),
          ),

          PageView.builder(
            controller: _ctrl,
            onPageChanged: _onPageChanged,
            // While the current page is zoom-locked (2+ fingers or scale > 1)
            // the PageView is frozen so a horizontal pinch motion never gets
            // hijacked as a swipe to the next asset.
            physics: _zoomLocked
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            itemCount: _entries.length,
            itemBuilder: (ctx, i) {
              final entry = _entries[i];
              return _AssetPage(
                entry: entry,
                isActive: i == _currentIndex,
                onTap: _toggleUi,
                onInfoProgressChanged: i == _currentIndex
                    ? (p) {
                        if (_infoProgress == p) return;
                        setState(() => _infoProgress = p);
                      }
                    : null,
                onZoomLockedChanged: i == _currentIndex
                    ? (locked) {
                        if (_zoomLocked == locked) return;
                        setState(() => _zoomLocked = locked);
                      }
                    : null,
              );
            },
          ),

          // Bottom: filmstrip + action bar. Fades out while the inline info
          // sheet rises so they don't share the bottom region.
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: IgnorePointer(
              ignoring: !_uiVisible || _infoProgress > 0.5,
              child: AnimatedSlide(
                duration: AppDuration.normal,
                curve: AppCurves.standard,
                offset: _uiVisible ? Offset.zero : const Offset(0, 1),
                child: Opacity(
                  opacity: _uiVisible
                      ? (1.0 - _infoProgress).clamp(0.0, 1.0)
                      : 0.0,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_entries.length > 1)
                          AssetFilmstrip(
                            entries: _entries,
                            currentIndex: _currentIndex,
                            onSelect: _jumpToIndex,
                            onScrub: _scrubToIndex,
                          ),
                        _DetailActionBar(
                          isVideo: isVideo,
                          onCompress: _compress,
                          onCrop: _crop,
                          onStrip: _stripMetadata,
                          onSurgical: _surgical,
                          onMore: () => _action(l.selectionMore),
                          // Dedicated video routes — the unified editor is
                          // still available via /video-edit/{id} for power
                          // users, but each common operation now lands on
                          // its own focused screen.
                          onTrim: _trim,
                          onCropVideo: _cropVideo,
                          onRemoveAudio: _removeAudio,
                          onCompressVideo: _videoEdit,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _titleFor(LibraryEntry entry) {
    final created = entry.created;
    if (created == null) return '';
    final locale = Localizations.localeOf(context).languageCode;
    return DateFormat.yMMMd(locale).format(created);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AssetPage — one page in the PageView. Loads a 1080-px thumbnail (fast +
// memory-friendly) and shows it inside InteractiveViewer for pinch/pan.
// Wrapped in Hero so the open/close animation snaps back to the grid tile.
// ─────────────────────────────────────────────────────────────────────────────

class _AssetPage extends StatefulWidget {
  const _AssetPage({
    required this.entry,
    required this.isActive,
    required this.onTap,
    this.onInfoProgressChanged,
    this.onZoomLockedChanged,
  });

  final LibraryEntry entry;
  final bool isActive;
  final VoidCallback onTap;

  /// Reports the inline-info-sheet open progress (0..1) so the parent can
  /// fade out the bottom action bar that would otherwise sit over the sheet.
  final ValueChanged<double>? onInfoProgressChanged;

  /// Reports when the page enters / leaves zoom mode (2+ fingers or
  /// scale > 1). Parents wire this to the PageView's physics so horizontal
  /// pinch motions can't be hijacked as page swipes.
  final ValueChanged<bool>? onZoomLockedChanged;

  @override
  State<_AssetPage> createState() => _AssetPageState();
}

enum _DragMode { idle, dismissDown, infoUp }

class _AssetPageState extends State<_AssetPage>
    with TickerProviderStateMixin {
  Uint8List? _lowResBytes;
  Uint8List? _hiResBytes;
  // Materialised lazily from the entry id; needed for the video player and the
  // inline metadata sheet. Null until it resolves.
  AssetEntity? _entity;
  final TransformationController _txCtrl = TransformationController();
  late final AnimationController _zoomAnim;
  late final AnimationController _dismissAnim;
  late final AnimationController _infoAnim;

  // Drag state — direction-locked the moment the user passes the first
  // sub-pixel of vertical motion, so dismiss-down and info-up never fight.
  double _dismissDy = 0;
  double _infoY = 0; // pulled-up height of the info sheet
  _DragMode _dragMode = _DragMode.idle;

  // Zoom lock — true while ≥2 fingers are or have been engaging the image
  // since the last full zoom-out. Cleared only when scale returns to 1.0
  // AND the user is back to ≤1 finger.
  final Set<int> _activePointers = {};
  bool _zoomLocked = false;

  static const double _minScale = 1.0;
  static const double _maxScale = 4.0;
  static const double _dismissThreshold = 120;
  static const double _dismissVelocityThreshold = 800;
  static const double _infoThreshold = 90;
  static const double _infoVelocityThreshold = 600;
  static const double _infoMaxHeight = 420;
  static const double _dirLockSlop = 2.0;

  @override
  void initState() {
    super.initState();
    _zoomAnim = AnimationController(vsync: this, duration: AppDuration.normal)
      ..addListener(_applyZoomAnim);
    _dismissAnim = AnimationController(
      vsync: this,
      duration: AppDuration.normal,
    );
    _infoAnim = AnimationController(
      vsync: this,
      duration: AppDuration.normal,
    );
    _txCtrl.addListener(_syncZoomLock);

    // Show the cached small thumb instantly (Hero landing), then materialise
    // the entity lazily and swap in the crisp 1080-px version.
    _lowResBytes = ThumbnailCache.get(widget.entry.id);
    _load();
  }

  Future<void> _load() async {
    final entity = await AssetEntityCache.load(
      widget.entry.id,
      cancelled: () => !mounted,
    );
    if (entity == null || !mounted) return;
    setState(() => _entity = entity);
    _scheduleHiRes();
  }

  /// Decode the crisp 1080-px image only for the ACTIVE page, and only after a
  /// short settle — so flinging the filmstrip past dozens of large photos
  /// doesn't decode full-res for every transient page. The cached low-res
  /// (360-px) carries the view in the meantime.
  void _scheduleHiRes() {
    if (_hiResBytes != null || _entity == null || !widget.isActive) return;
    final id = widget.entry.id;
    Future.delayed(const Duration(milliseconds: 130), () async {
      if (!mounted ||
          !widget.isActive ||
          _hiResBytes != null ||
          _entity == null ||
          widget.entry.id != id) {
        return;
      }
      final data =
          await _entity!.thumbnailDataWithSize(const ThumbnailSize.square(1080));
      if (mounted && widget.entry.id == id) {
        setState(() => _hiResBytes = data);
      }
    });
  }

  @override
  void didUpdateWidget(_AssetPage old) {
    super.didUpdateWidget(old);
    // Became the active page (e.g. the scrub settled here) → load full-res.
    if (widget.isActive && !old.isActive) _scheduleHiRes();
  }

  @override
  void dispose() {
    _zoomAnim.dispose();
    _dismissAnim.dispose();
    _infoAnim.dispose();
    _txCtrl.removeListener(_syncZoomLock);
    _txCtrl.dispose();
    super.dispose();
  }

  // ── Zoom lock + manual pointer-based drag ──────────────────────────────
  //
  // Why Listener instead of GestureDetector: the surrounding PageView ships
  // its own HorizontalDragGestureRecognizer in the gesture arena. As soon as
  // GestureDetector's verticalDrag *claims* a pointer (or PageView's claims
  // first), the InteractiveViewer scale recogniser can no longer engage with
  // that pointer — making direct two-finger pinches fail until the user
  // lifts and retries. By tracking pointer events through a Listener (which
  // observes events *without* participating in the arena) we keep the scale
  // recogniser free to win the moment a second finger lands, and we drive
  // the dismiss/info gestures from raw deltas instead of an arena recognizer.

  bool get _isZoomed => _txCtrl.value.getMaxScaleOnAxis() > 1.02;

  Offset? _firstPointerStart;
  Offset? _firstPointerLast;
  int? _firstPointerId;
  Duration? _firstPointerStartTime;

  void _setZoomLocked(bool locked) {
    if (_zoomLocked == locked) return;
    setState(() => _zoomLocked = locked);
    widget.onZoomLockedChanged?.call(locked);
  }

  void _onPointerDown(PointerDownEvent e) {
    if (!mounted) return;
    _activePointers.add(e.pointer);
    if (_activePointers.length == 1) {
      _firstPointerId = e.pointer;
      _firstPointerStart = e.position;
      _firstPointerLast = e.position;
      _firstPointerStartTime = e.timeStamp;
      _dismissAnim.stop();
      _dragMode = _DragMode.idle;
    }
    if (_activePointers.length >= 2 && !_zoomLocked) {
      // Engage zoom lock immediately so the parent PageView freezes its
      // physics before any horizontal pinch motion is interpreted as a
      // page swipe. Cancel any in-flight dismiss drag in the same beat.
      if (_dragMode != _DragMode.idle) {
        _dragMode = _DragMode.idle;
        _springBackDismiss();
        _animateInfoTo(0);
      }
      _setZoomLocked(true);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!mounted) return;
    if (_activePointers.length != 1) return;
    if (e.pointer != _firstPointerId) return;
    if (_zoomLocked || _isZoomed) return;

    final start = _firstPointerStart;
    if (start == null) return;
    _firstPointerLast = e.position;
    final delta = e.position - start;

    if (_dragMode == _DragMode.idle) {
      if (delta.dy.abs() < _dirLockSlop) return;
      _dragMode = delta.dy > 0 ? _DragMode.dismissDown : _DragMode.infoUp;
      _infoAnim.stop();
    }
    switch (_dragMode) {
      case _DragMode.dismissDown:
        setState(() => _dismissDy = delta.dy.clamp(0, 9999));
        break;
      case _DragMode.infoUp:
        setState(() {
          _infoY = (-delta.dy).clamp(0.0, _infoMaxHeight);
        });
        _notifyInfoProgress();
        break;
      case _DragMode.idle:
        break;
    }
  }

  void _onPointerUp(PointerEvent e) {
    if (!mounted) return;
    final wasFirst = e.pointer == _firstPointerId;
    _activePointers.remove(e.pointer);
    _syncZoomLock();
    if (wasFirst) {
      _resolveDragOnRelease(e);
      _firstPointerId = null;
      _firstPointerStart = null;
      _firstPointerLast = null;
      _firstPointerStartTime = null;
    }
  }

  /// Keep the PageView frozen whenever the image is zoomed (by pinch OR
  /// double-tap) or a pinch is in progress — otherwise a one-finger pan on a
  /// zoomed image is stolen by the PageView as a swipe to the next photo.
  /// Unlocks once back to 1× and down to ≤1 finger.
  void _syncZoomLock() {
    final shouldLock =
        _txCtrl.value.getMaxScaleOnAxis() > 1.02 || _activePointers.length >= 2;
    if (shouldLock == _zoomLocked) return;
    if (shouldLock) {
      _setZoomLocked(true);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_txCtrl.value.getMaxScaleOnAxis() <= 1.02 &&
            _activePointers.length < 2) {
          _setZoomLocked(false);
        }
      });
    }
  }

  void _resolveDragOnRelease(PointerEvent e) {
    if (_dragMode == _DragMode.idle) return;
    final last = _firstPointerLast ?? e.position;
    final start = _firstPointerStart ?? e.position;
    final delta = last - start;
    final dt = (e.timeStamp - (_firstPointerStartTime ?? e.timeStamp))
        .inMicroseconds;
    final velocityDy = dt > 0
        ? (delta.dy * 1000000) / dt // px/sec from total travel
        : 0.0;

    switch (_dragMode) {
      case _DragMode.dismissDown:
        if (_dismissDy > _dismissThreshold ||
            velocityDy > _dismissVelocityThreshold) {
          Navigator.of(context).maybePop();
        } else {
          _springBackDismiss();
        }
        break;
      case _DragMode.infoUp:
        if (_infoY > _infoThreshold ||
            velocityDy < -_infoVelocityThreshold) {
          _animateInfoTo(_infoMaxHeight);
        } else {
          _animateInfoTo(0);
        }
        break;
      case _DragMode.idle:
        break;
    }
    _dragMode = _DragMode.idle;
  }

  void _springBackDismiss() {
    if (_dismissDy == 0) return;
    final start = _dismissDy;
    _dismissAnim.value = 0;
    final tween = Tween<double>(begin: start, end: 0).animate(
      CurvedAnimation(
          parent: _dismissAnim, curve: const Cubic(0.3, 1.5, 0.4, 1)),
    );
    void listener() {
      if (!mounted) return;
      setState(() => _dismissDy = tween.value);
    }
    _dismissAnim.addListener(listener);
    _dismissAnim.forward().whenComplete(() {
      _dismissAnim.removeListener(listener);
      if (mounted) setState(() => _dismissDy = 0);
    });
  }

  void _animateInfoTo(double target) {
    final start = _infoY;
    if (start == target) return;
    _infoAnim.value = 0;
    final tween = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(parent: _infoAnim, curve: AppCurves.emphasized),
    );
    void listener() {
      if (!mounted) return;
      setState(() => _infoY = tween.value);
      _notifyInfoProgress();
    }
    _infoAnim.addListener(listener);
    _infoAnim.forward().whenComplete(() {
      _infoAnim.removeListener(listener);
    });
  }

  void _notifyInfoProgress() {
    final progress = (_infoY / _infoMaxHeight).clamp(0.0, 1.0);
    widget.onInfoProgressChanged?.call(progress);
  }

  Matrix4? _animFrom;
  Matrix4? _animTo;

  void _applyZoomAnim() {
    if (_animFrom == null || _animTo == null) return;
    _txCtrl.value =
        Matrix4Tween(begin: _animFrom, end: _animTo).evaluate(_zoomAnim);
  }

  void _onDoubleTap(TapDownDetails details) {
    final current = _txCtrl.value.getMaxScaleOnAxis();
    if (current > 1.05) {
      _animateTo(Matrix4.identity());
    } else {
      final position = details.localPosition;
      final zoom = Matrix4.identity()
        ..translateByDouble(-position.dx * 1.5, -position.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
      _animateTo(zoom);
    }
  }

  void _animateTo(Matrix4 target) {
    _animFrom = _txCtrl.value;
    _animTo = target;
    _zoomAnim
      ..value = 0
      ..forward();
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    // If the user released at (near-)min scale, snap the image back to its
    // centred identity. Prevents the "stuck pulled to a corner" state at 1×.
    final scale = _txCtrl.value.getMaxScaleOnAxis();
    if (scale <= 1.02) {
      _animateTo(Matrix4.identity());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.entry.isVideo;
    final bytesToShow = _hiResBytes ?? _lowResBytes;

    // Nothing to paint yet (no cached thumb and the entity is still
    // resolving), or a video whose entity hasn't loaded → show the loader.
    if (bytesToShow == null || (isVideo && _entity == null)) {
      return GestureDetector(
        onTap: widget.onTap,
        child: const Center(child: _LoadingBlock()),
      );
    }

    return AnimatedBuilder(
      animation: _txCtrl,
      builder: (ctx, _) {
        final scale = _txCtrl.value.getMaxScaleOnAxis();
        final isZoomed = scale > 1.02;

        // Rubber-band visuals — only the dismiss-down gesture moves the image
        // and fades the background. The info-up gesture leaves the image
        // alone and only animates the inline sheet below.
        final dragProgress =
            (_dismissDy / _dismissThreshold).clamp(0.0, 1.0);
        final dragScale = 1.0 - dragProgress * 0.15;
        final bgDim = 1.0 - dragProgress;
        final infoProgress = (_infoY / _infoMaxHeight).clamp(0.0, 1.0);

        final imageContent = Center(
          child: Hero(
            tag: 'asset-${widget.entry.id}',
            createRectTween: (a, b) => MaterialRectArcTween(begin: a, end: b),
            child: isVideo
                ? AssetVideoPlayer(asset: _entity!)
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_lowResBytes != null)
                        Image.memory(
                          _lowResBytes!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.low,
                        ),
                      AnimatedSwitcher(
                        duration: AppDuration.normal,
                        switchInCurve: AppCurves.decelerate,
                        child: _hiResBytes == null
                            ? const SizedBox.shrink(key: ValueKey('hi-empty'))
                            : Image.memory(
                                _hiResBytes!,
                                key: const ValueKey('hi-loaded'),
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.high,
                              ),
                      ),
                    ],
                  ),
          ),
        );

        // InteractiveViewer is the canonical zoom/pan host. We mount it the
        // same way in both modes — only the surrounding gesture handlers
        // differ.
        final viewer = InteractiveViewer(
          transformationController: _txCtrl,
          minScale: _minScale,
          maxScale: _maxScale,
          panEnabled: isZoomed,
          scaleEnabled: !isVideo,
          // boundaryMargin zero clamps panning to the image's edges — the
          // image can't be pushed off-screen no matter how hard the user
          // pans. EdgeInsets.all(infinity) would let them keep flicking
          // past the edge forever, which feels broken on a phone.
          boundaryMargin: EdgeInsets.zero,
          clipBehavior: Clip.none,
          onInteractionEnd: _onInteractionEnd,
          child: imageContent,
        );

        // The GestureDetector only handles tap + double-tap. Vertical drag
        // is tracked manually via the outer Listener's onPointerMove so
        // it never competes with the InteractiveViewer scale recognizer
        // (or the parent PageView's horizontal drag) in the gesture arena.
        final gestureLayer = GestureDetector(
          onTap: () {
            if (_infoY > 0) {
              _animateInfoTo(0);
            } else {
              widget.onTap();
            }
          },
          onDoubleTapDown: _onDoubleTap,
          onDoubleTap: () {},
          child: viewer,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            // Background — fades from black to transparent so the route
            // beneath shows through during dismiss.
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: bgDim)),
            ),
            // Image + transforms. Listener tracks every pointer event (it
            // does NOT participate in the gesture arena) so the scale
            // recognizer inside InteractiveViewer is free to win the moment
            // a second finger lands.
            Transform.translate(
              offset: Offset(0, _dismissDy),
              child: Transform.scale(
                scale: dragScale,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerUp,
                  child: gestureLayer,
                ),
              ),
            ),
            // Inline info sheet — slides up from the bottom as the user pulls
            // (or animates to full once threshold is crossed). It sits inside
            // the same Stack so the sheet drag stays continuous with the
            // upward swipe that summoned it. Only once the entity is resolved.
            if (_entity != null)
              _InlineInfoSheet(
              asset: _entity!,
              infoY: _infoY,
              maxHeight: _infoMaxHeight,
              infoProgress: infoProgress,
              onDragUpdate: (dy) {
                if (_zoomLocked) return;
                _infoAnim.stop();
                setState(() {
                  _infoY = (_infoY - dy).clamp(0.0, _infoMaxHeight);
                });
                _notifyInfoProgress();
              },
              onDragEnd: (velocity) {
                if (_infoY > _infoThreshold ||
                    velocity < -_infoVelocityThreshold) {
                  _animateInfoTo(_infoMaxHeight);
                } else {
                  _animateInfoTo(0);
                }
              },
              onClose: () => _animateInfoTo(0),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InlineInfoSheet — a metadata sheet that lives inside the asset page and
// is dragged up by the user (gradually) rather than appearing modally.
// Renders its own scrim that fades in with `infoProgress`, taps the scrim to
// close.
// ─────────────────────────────────────────────────────────────────────────────

class _InlineInfoSheet extends StatelessWidget {
  const _InlineInfoSheet({
    required this.asset,
    required this.infoY,
    required this.maxHeight,
    required this.infoProgress,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onClose,
  });

  final AssetEntity asset;
  final double infoY;
  final double maxHeight;
  final double infoProgress;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    return Stack(
      children: [
        // Scrim above the sheet — fades in with progress, taps close.
        if (infoProgress > 0.01)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: IgnorePointer(
                ignoring: infoProgress < 0.1,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45 * infoProgress),
                ),
              ),
            ),
          ),
        // The sheet itself.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: maxHeight,
          child: Transform.translate(
            offset: Offset(0, maxHeight - infoY),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => onDragUpdate(d.delta.dy),
              onVerticalDragEnd: (d) =>
                  onDragEnd(d.velocity.pixelsPerSecond.dy),
              child: Container(
                decoration: BoxDecoration(
                  color: hc.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.xl),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Drag handle
                    Padding(
                      padding: const EdgeInsets.only(
                          top: AppSpacing.s2, bottom: AppSpacing.s1),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: hc.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Expanded(
                      child: AssetMetadataSheet(asset: asset),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();
  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 80,
        height: 80,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _DetailAppBar — translucent over the photo. Back + date title + info / more.
// ─────────────────────────────────────────────────────────────────────────────

class _DetailAppBar extends StatelessWidget {
  const _DetailAppBar({
    required this.title,
    required this.onInfo,
    required this.onMore,
  });
  final String title;
  final VoidCallback onInfo;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: onInfo,
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: onMore,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DetailActionBar — bottom row of operations relevant to the asset type.
// Translucent black with edge fade-in.
// ─────────────────────────────────────────────────────────────────────────────

class _DetailActionBar extends StatelessWidget {
  const _DetailActionBar({
    required this.isVideo,
    required this.onCompress,
    required this.onCrop,
    required this.onStrip,
    required this.onSurgical,
    required this.onMore,
    this.onTrim,
    this.onCropVideo,
    this.onRemoveAudio,
    this.onCompressVideo,
  });

  final bool isVideo;
  // Image-mode callbacks. Used as fallbacks when the corresponding video
  // callback isn't supplied.
  final VoidCallback onCompress;
  final VoidCallback onCrop;
  final VoidCallback onStrip;
  final VoidCallback onSurgical;
  final VoidCallback onMore;
  // Video-mode callbacks — each maps to a dedicated screen.
  final VoidCallback? onTrim;
  final VoidCallback? onCropVideo;
  final VoidCallback? onRemoveAudio;
  final VoidCallback? onCompressVideo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final actions = isVideo
        ? [
            (Icons.content_cut_rounded, l.toolTrim, onTrim ?? onCompress),
            (Icons.crop_rounded, l.toolCropVideo, onCropVideo ?? onCrop),
            (Icons.compress_rounded, l.toolCompressVideo,
                onCompressVideo ?? onCompress),
            (Icons.volume_off_rounded, l.toolRemoveAudio,
                onRemoveAudio ?? onStrip),
            (Icons.more_horiz_rounded, l.selectionMore, onMore),
          ]
        : [
            (Icons.compress_rounded, l.toolCompress, onCompress),
            (Icons.crop_rounded, l.toolCrop, onCrop),
            (Icons.auto_fix_high_rounded, l.toolStripMetadata, onStrip),
            (Icons.healing_rounded, l.toolSurgicalReplace, onSurgical),
            (Icons.more_horiz_rounded, l.selectionMore, onMore),
          ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.s2),
      child: Row(
        children: [
          for (final (icon, label, cb) in actions)
            Expanded(
              child: _DetailActionButton(
                icon: icon,
                label: label,
                onTap: cb,
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailActionButton extends StatefulWidget {
  const _DetailActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_DetailActionButton> createState() => _DetailActionButtonState();
}

class _DetailActionButtonState extends State<_DetailActionButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: AppDuration.micro,
        scale: _pressed ? 0.92 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, color: Colors.white, size: 24),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
