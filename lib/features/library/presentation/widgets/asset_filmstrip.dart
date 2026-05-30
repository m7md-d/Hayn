import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';
import '../providers/library_provider.dart';
import 'id_thumbnail.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AssetFilmstrip — horizontal strip of tiny thumbnails for the whole sibling
// spine. Keeps the active asset centred; the tile under the fixed centre frame
// is the selection. Driven by the lightweight spine (ids), so tiles paint
// lazily via IdThumbnail and the strip can span the entire library.
//
// Scrubbing: the main image follows LIVE as you drag/fling (throttled), and on
// release the strip snaps to the centred tile with an instant jump so a fresh
// fling is never fought by a settle animation.
// ─────────────────────────────────────────────────────────────────────────────

class AssetFilmstrip extends StatefulWidget {
  const AssetFilmstrip({
    required this.entries,
    required this.currentIndex,
    required this.onSelect,
    required this.onScrub,
    super.key,
  });

  final List<LibraryEntry> entries;
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

  // Throttle live scrub commits so a fast fling doesn't jump the heavy main
  // PageView every single frame.
  int _lastScrubIndex = -1;
  DateTime _lastScrubAt = DateTime.fromMillisecondsSinceEpoch(0);

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
    final target = (widget.currentIndex * _stride)
        .clamp(0.0, _ctrl.position.maxScrollExtent);
    if (animate) {
      _ctrl.animateTo(target,
          duration: AppDuration.normal, curve: AppCurves.standard);
    } else {
      _ctrl.jumpTo(target);
    }
  }

  int _centeredIndex() =>
      (_ctrl.offset / _stride).round().clamp(0, widget.entries.length - 1);

  bool _onNotification(ScrollNotification n) {
    if (n is ScrollStartNotification) {
      // dragDetails != null ⇒ a real finger drag (not our programmatic centre).
      if (n.dragDetails != null) _userDriving = true;
    } else if (n is ScrollUpdateNotification && _userDriving) {
      // Live follow, throttled: update the main image as the centre tile
      // changes, but no more than ~every 60 ms so the PageView keeps up.
      final c = _centeredIndex();
      final now = DateTime.now();
      if (c != _lastScrubIndex &&
          now.difference(_lastScrubAt).inMilliseconds >= 60) {
        _lastScrubIndex = c;
        _lastScrubAt = now;
        if (c != widget.currentIndex) widget.onScrub(c);
      }
    } else if (n is ScrollEndNotification && _userDriving) {
      _userDriving = false;
      final c = _centeredIndex();
      _lastScrubIndex = c;
      if (c != widget.currentIndex) widget.onScrub(c);
      // Instant snap to the exact tile centre — no animation to fight a fresh
      // fling the user may start immediately after.
      if (_ctrl.hasClients) {
        _ctrl.jumpTo((c * _stride).clamp(0.0, _ctrl.position.maxScrollExtent));
      }
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
    final hc = context.hc;
    return SizedBox(
      height: AssetFilmstrip.tileSize + 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          NotificationListener<ScrollNotification>(
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
              itemCount: widget.entries.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AssetFilmstrip.tileGap),
              itemBuilder: (ctx, i) => _FilmTile(
                entry: widget.entries[i],
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onSelect(i);
                },
              ),
            ),
          ),
          // Fixed centre frame: the tile sitting under it is the selection,
          // so it's obvious which one you'll land on as you scrub.
          IgnorePointer(
            child: Container(
              width: AssetFilmstrip.tileSize + 8,
              height: AssetFilmstrip.tileSize + 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.xs + 4),
                border: Border.all(color: hc.accent, width: 2.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilmTile extends StatelessWidget {
  const _FilmTile({required this.entry, required this.onTap});
  final LibraryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Uniform tiles — the fixed centre frame indicates the selection, so tiles
    // don't need per-item borders/opacity (which also keeps scrubbing cheap).
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: AssetFilmstrip.tileSize,
        height: AssetFilmstrip.tileSize,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: Stack(
            fit: StackFit.expand,
            children: [
              IdThumbnail(id: entry.id, placeholderColor: Colors.white12),
              if (entry.isVideo)
                const Center(
                  child: Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
