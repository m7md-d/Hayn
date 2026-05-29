import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';
import '../providers/thumbnail_cache.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AssetFilmstrip — horizontal strip of tiny thumbnails for adjacent assets.
// Keeps the active asset centered as the user swipes / taps. Tap on a tile
// jumps to that index.
// ─────────────────────────────────────────────────────────────────────────────

class AssetFilmstrip extends StatefulWidget {
  const AssetFilmstrip({
    required this.assets,
    required this.currentIndex,
    required this.onSelect,
    required this.onScrub,
    super.key,
  });

  final List<AssetEntity> assets;
  final int currentIndex;

  /// Tap on a tile → jump (animated) to it.
  final ValueChanged<int> onSelect;

  /// The tile under the centre line changed while dragging/flinging the strip
  /// → the main image should follow it immediately (no animation).
  final ValueChanged<int> onScrub;

  static const tileSize = 40.0;
  static const tileGap = 4.0;

  @override
  State<AssetFilmstrip> createState() => _AssetFilmstripState();
}

class _AssetFilmstripState extends State<AssetFilmstrip> {
  final _ctrl = ScrollController();

  // The padding centres tile 0 at offset 0, so offset = index * stride lands
  // tile `index` exactly on the screen centre. No viewport math needed.
  static const _stride = AssetFilmstrip.tileSize + AssetFilmstrip.tileGap;

  // True only while the user is driving the strip (drag + the fling after it),
  // so we don't re-centre underneath their finger or echo our own jumps back.
  bool _userDriving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _centerOnCurrent(animate: false));
  }

  @override
  void didUpdateWidget(AssetFilmstrip old) {
    super.didUpdateWidget(old);
    // Re-centre only when the index changed from elsewhere (a main-image
    // swipe) — never while the user is scrubbing the strip itself.
    if (old.currentIndex != widget.currentIndex && !_userDriving) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnCurrent());
    }
  }

  void _centerOnCurrent({bool animate = true}) {
    if (!_ctrl.hasClients) return;
    final target =
        (widget.currentIndex * _stride).clamp(0.0, _ctrl.position.maxScrollExtent);
    if (animate) {
      _ctrl.animateTo(target,
          duration: AppDuration.normal, curve: AppCurves.standard);
    } else {
      _ctrl.jumpTo(target);
    }
  }

  int _centeredIndex() =>
      (_ctrl.offset / _stride).round().clamp(0, widget.assets.length - 1);

  bool _onNotification(ScrollNotification n) {
    if (n is ScrollStartNotification) {
      // dragDetails != null ⇒ a real finger drag (not our programmatic centre).
      _userDriving = n.dragDetails != null;
    } else if (n is ScrollUpdateNotification && _userDriving) {
      final c = _centeredIndex();
      if (c != widget.currentIndex) widget.onScrub(c);
    } else if (n is ScrollEndNotification && _userDriving) {
      _userDriving = false;
      final c = _centeredIndex();
      if (c != widget.currentIndex) widget.onScrub(c);
      // Settle exactly onto the centred tile.
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnCurrent());
    }
    return false;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AssetFilmstrip.tileSize + 16,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: ListView.separated(
          controller: _ctrl,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width / 2 -
                AssetFilmstrip.tileSize / 2,
            vertical: 8,
          ),
          itemCount: widget.assets.length,
          separatorBuilder: (_, __) =>
              const SizedBox(width: AssetFilmstrip.tileGap),
          itemBuilder: (ctx, i) {
            return _FilmTile(
              asset: widget.assets[i],
              active: i == widget.currentIndex,
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onSelect(i);
              },
            );
          },
        ),
      ),
    );
  }
}

class _FilmTile extends StatefulWidget {
  const _FilmTile({
    required this.asset,
    required this.active,
    required this.onTap,
  });
  final AssetEntity asset;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_FilmTile> createState() => _FilmTileState();
}

class _FilmTileState extends State<_FilmTile> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    final cached = ThumbnailCache.get(widget.asset.id);
    if (cached != null) {
      _thumb = cached;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final data = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize.square(120),
    );
    if (data != null) ThumbnailCache.put(widget.asset.id, data);
    if (mounted) setState(() => _thumb = data);
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        width: AssetFilmstrip.tileSize,
        height: AssetFilmstrip.tileSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xs + 2),
          border: Border.all(
            color: widget.active ? hc.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: AnimatedOpacity(
            duration: AppDuration.fast,
            opacity: widget.active ? 1.0 : 0.55,
            child: _thumb == null
                ? Container(color: Colors.white12)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(_thumb!,
                          fit: BoxFit.cover, gaplessPlayback: true),
                      if (widget.asset.type == AssetType.video)
                        const Center(
                          child: Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 16),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
