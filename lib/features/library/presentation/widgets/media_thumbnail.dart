import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/badges.dart';
import 'id_thumbnail.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MediaThumbnail — single tile inside the library grid.
//
// Driven entirely by an asset id + a few lightweight facts (type, size,
// duration) from the index spine — it never holds an AssetEntity. The image
// itself is painted by IdThumbnail, which materialises the entity lazily only
// while the tile is on screen. That's what lets the grid render a 10k-row
// childCount without loading 10k entities.
//
// Visual layers (back→front):
//   1. surface-sunken bg (placeholder)
//   2. IdThumbnail (lazy image)
//   3. dim overlay (when selecting && !this.selected)
//   4. selection ring (accent border, animated)
//   5. corner checkmark (animated scale + fade)
//   6. file size badge (bottom-start)
//   7. video duration badge (bottom-end)
// ─────────────────────────────────────────────────────────────────────────────

class MediaThumbnail extends StatelessWidget {
  const MediaThumbnail({
    required this.id,
    required this.type,
    required this.isSelected,
    required this.isSelecting,
    required this.onTap,
    required this.onLongPress,
    this.sizeBytes,
    this.durationSeconds = 0,
    this.showSize = true,
    this.disabled = false,
    super.key,
  });

  final String id;
  final AssetType type;
  final int? sizeBytes;
  final int durationSeconds;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool showSize;

  /// Locked out during selection because a different type is already selected
  /// (selections are single-type). Dimmed + non-interactive.
  final bool disabled;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()}KB';
    if (bytes < 1024 * 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return mb < 10 ? '${mb.toStringAsFixed(1)}MB' : '${mb.round()}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final selected = isSelected;
    final selecting = isSelecting;

    // RepaintBoundary isolates each tile's repaint: when one thumbnail's
    // fade-in animation runs, neighbouring tiles in the grid don't repaint.
    return RepaintBoundary(
      child: Opacity(
        opacity: disabled ? 0.35 : 1.0,
        child: GestureDetector(
        onTap: disabled
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        onLongPress: disabled
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onLongPress();
              },
        child: AnimatedScale(
          scale: selected ? 0.94 : 1.0,
          duration: AppDuration.fast,
          curve: AppCurves.standard,
          child: Hero(
            tag: 'asset-$id',
            // Straight tween (not the Material arc) so the tile scales directly
            // up into the viewer — matches the detail Hero for a clean flight.
            createRectTween: (begin, end) => RectTween(begin: begin, end: end),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1) Sunken background (visible while loading)
                Container(color: hc.surfaceSunken),

                // 2) Thumbnail image (lazy, by id)
                IdThumbnail(id: id, placeholderColor: hc.surfaceSunken),

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

                // 5) Corner checkmark — scales in/out.
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

                // 6) File size badge (bottom-start) — stays visible during
                // selection too (the checkmark sits top-start, so no clash);
                // users want to see sizes while picking what to process.
                if (showSize && sizeBytes != null)
                  PositionedDirectional(
                    bottom: 5,
                    start: 5,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatBytes(sizeBytes!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),

                // 7) Video duration badge (bottom-end)
                if (type == AssetType.video)
                  PositionedDirectional(
                    bottom: 5,
                    end: 5,
                    child: HaynVideoDurationBadge(duration: durationSeconds),
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
