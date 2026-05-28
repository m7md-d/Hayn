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
    super.key,
  });

  final List<AssetEntity> assets;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const tileSize = 40.0;
  static const tileGap = 4.0;

  @override
  State<AssetFilmstrip> createState() => _AssetFilmstripState();
}

class _AssetFilmstripState extends State<AssetFilmstrip> {
  final _ctrl = ScrollController();

  @override
  void didUpdateWidget(AssetFilmstrip old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnCurrent());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnCurrent());
  }

  void _centerOnCurrent() {
    if (!_ctrl.hasClients) return;
    // The horizontal SafeArea padding is set to (screen/2 - tile/2), which
    // means: offset = index * stride lands the centre of the current tile
    // exactly on the screen centre. No viewport math needed.
    const itemStride = AssetFilmstrip.tileSize + AssetFilmstrip.tileGap;
    final target = widget.currentIndex * itemStride;
    final clamped = target.clamp(0.0, _ctrl.position.maxScrollExtent);
    _ctrl.animateTo(
      clamped,
      duration: AppDuration.normal,
      curve: AppCurves.standard,
    );
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
      child: ListView.separated(
        controller: _ctrl,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal:
              MediaQuery.sizeOf(context).width / 2 - AssetFilmstrip.tileSize / 2,
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
