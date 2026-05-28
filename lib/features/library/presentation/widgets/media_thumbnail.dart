import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/badges.dart';
import '../providers/asset_size_cache.dart';
import '../providers/thumbnail_cache.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MediaThumbnail — single tile inside the library grid.
//
// Visual layers (back→front):
//   1. surface-sunken bg (skeleton)
//   2. Image.memory thumbnail (fade-in on load)
//   3. dim overlay (when selecting && !this.selected)
//   4. selection ring (accent border, animated)
//   5. corner checkmark (animated scale + fade)
//   6. video duration badge (bottom-end)
// ─────────────────────────────────────────────────────────────────────────────

class MediaThumbnail extends StatefulWidget {
  const MediaThumbnail({
    required this.asset,
    required this.isSelected,
    required this.isSelecting,
    required this.onTap,
    required this.onLongPress,
    this.showSize = true,
    super.key,
  });

  final AssetEntity asset;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool showSize;

  @override
  State<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<MediaThumbnail> {
  Uint8List? _thumb;
  bool _loaded = false;
  int? _sizeBytes;

  @override
  void initState() {
    super.initState();
    final cached = ThumbnailCache.get(widget.asset.id);
    if (cached != null) {
      _thumb = cached;
      _loaded = true;
    } else {
      _loadThumb();
    }
    _sizeBytes = AssetSizeCache.get(widget.asset.id);
    if (_sizeBytes == null) _loadSize();
  }

  @override
  void didUpdateWidget(MediaThumbnail old) {
    super.didUpdateWidget(old);
    if (old.asset.id != widget.asset.id) {
      final cached = ThumbnailCache.get(widget.asset.id);
      final size = AssetSizeCache.get(widget.asset.id);
      setState(() {
        _thumb = cached;
        _loaded = cached != null;
        _sizeBytes = size;
      });
      if (cached == null) _loadThumb();
      if (size == null) _loadSize();
    }
  }

  Future<void> _loadThumb() async {
    final data = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize.square(360),
    );
    if (data != null) ThumbnailCache.put(widget.asset.id, data);
    if (mounted) {
      setState(() {
        _thumb = data;
        _loaded = true;
      });
    }
  }

  Future<void> _loadSize() async {
    final size = await AssetSizeCache.load(widget.asset);
    if (mounted && size != null) setState(() => _sizeBytes = size);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()}KB';
    if (bytes < 1024 * 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return mb < 10
          ? '${mb.toStringAsFixed(1)}MB'
          : '${mb.round()}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final selected = widget.isSelected;
    final selecting = widget.isSelecting;

    // RepaintBoundary isolates each tile's repaint: when one thumbnail's
    // fade-in animation runs, neighbouring tiles in the grid don't repaint.
    // Big win in scroll smoothness for a library of hundreds of items.
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        onLongPress: () {
          HapticFeedback.mediumImpact();
          widget.onLongPress();
        },
        child: AnimatedScale(
          scale: selected ? 0.94 : 1.0,
          duration: AppDuration.fast,
          curve: AppCurves.standard,
          child: Hero(
            tag: 'asset-${widget.asset.id}',
            createRectTween: (begin, end) =>
                MaterialRectArcTween(begin: begin, end: end),
            child: Stack(
            fit: StackFit.expand,
            children: [
              // 1) Sunken background (visible while loading)
              Container(color: hc.surfaceSunken),

              // 2) Thumbnail image
              if (_thumb != null)
                AnimatedOpacity(
                  opacity: _loaded ? 1.0 : 0.0,
                  duration: AppDuration.normal,
                  curve: AppCurves.decelerate,
                  child: Image.memory(
                    _thumb!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                ),

              // 3) Dim overlay during selection (for non-selected items)
              AnimatedOpacity(
                opacity: selecting && !selected ? 1.0 : 0.0,
                duration: AppDuration.fast,
                child: Container(color: Colors.black.withValues(alpha: 0.18)),
              ),

              // 4) Selection ring (drawn outside, so it's visible on edges)
              AnimatedOpacity(
                opacity: selected ? 1.0 : 0.0,
                duration: AppDuration.fast,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: hc.accent, width: 3),
                  ),
                ),
              ),

              // 5) Corner checkmark — scales in/out. PositionedDirectional
              // MUST be the direct child of the Stack so the top/start
              // anchor actually applies; AnimatedScale wraps the inner
              // bubble so the in/out animation scales around its centre.
              PositionedDirectional(
                top: 5,
                start: 5,
                child: AnimatedScale(
                  scale: selecting ? 1.0 : 0.0,
                  duration: AppDuration.fast,
                  curve: AppCurves.spring,
                  child: AnimatedContainer(
                    duration: AppDuration.micro,
                    curve: AppCurves.standard,
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? hc.accent
                          : Colors.white.withValues(alpha: 0.85),
                      border: Border.all(
                        color: selected ? Colors.transparent : hc.text2,
                        width: 1.2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            size: 11, color: Colors.white)
                        : null,
                  ),
                ),
              ),

              // 6) File size badge (bottom-start)
              if (widget.showSize && _sizeBytes != null && !selecting)
                PositionedDirectional(
                  bottom: 5,
                  start: 5,
                  child: AnimatedOpacity(
                    duration: AppDuration.fast,
                    opacity: selecting ? 0 : 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatBytes(_sizeBytes!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),

              // 7) Video duration badge (bottom-end)
              if (widget.asset.type == AssetType.video)
                PositionedDirectional(
                  bottom: 5,
                  end: 5,
                  child: HaynVideoDurationBadge(
                    duration: widget.asset.videoDuration.inSeconds,
                  ),
                ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
