import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HaynComparisonViewer — zoom-capable before/after comparison.
//
// Layout: a single InteractiveViewer hosts the "before" widget. The "after"
// widget is rendered as a separate layer with the same transform matrix
// applied via Transform, and is clipped horizontally based on a draggable
// split fraction. The drag handle lives in *viewport* coordinates so the
// split line always cuts the visible area regardless of the current pan/zoom.
//
// Zoom lock state machine — engaged the moment a 2nd finger touches the
// viewer OR scale crosses above 1.02. While engaged, [onZoomStateChanged]
// fires with `true`; parents typically use this to disable their ListView
// scroll so the user can pinch/pan freely without fighting the page. The
// lock releases only when scale returns to 1 AND ≤1 finger remains on
// the screen, mirroring the rule that "two fingers means you're zooming,
// nothing else."
//
// Double-tap also engages zoom — toggles between 1× and 2.5×.
// ─────────────────────────────────────────────────────────────────────────────

class HaynComparisonViewer extends StatefulWidget {
  const HaynComparisonViewer({
    required this.before,
    required this.after,
    required this.beforeLabel,
    required this.afterLabel,
    this.initialFraction = 0.5,
    this.maxScale = 4.0,
    this.onZoomStateChanged,
    super.key,
  });

  final Widget before;
  final Widget after;
  final String beforeLabel;
  final String afterLabel;
  final double initialFraction;
  final double maxScale;

  /// Fires whenever the viewer enters or leaves "zoom mode" (2+ fingers or
  /// scale > 1). Parents wire this to ListView/PageView physics so the
  /// surrounding scroll surface can't hijack the pinch.
  final ValueChanged<bool>? onZoomStateChanged;

  @override
  State<HaynComparisonViewer> createState() => _HaynComparisonViewerState();
}

class _HaynComparisonViewerState extends State<HaynComparisonViewer>
    with TickerProviderStateMixin {
  late final TransformationController _ctrl;
  late final AnimationController _zoomAnim;
  late double _fraction;

  final Set<int> _activePointers = {};
  bool _zoomLocked = false;

  Matrix4? _animFrom;
  Matrix4? _animTo;

  @override
  void initState() {
    super.initState();
    _ctrl = TransformationController();
    _ctrl.addListener(_onMatrixChanged);
    _zoomAnim = AnimationController(vsync: this, duration: AppDuration.normal)
      ..addListener(_applyZoomAnim);
    _fraction = widget.initialFraction;
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onMatrixChanged);
    _ctrl.dispose();
    _zoomAnim.dispose();
    super.dispose();
  }

  void _onMatrixChanged() => _maybeUnlock();

  void _setZoomLocked(bool locked) {
    if (_zoomLocked == locked) return;
    setState(() => _zoomLocked = locked);
    widget.onZoomStateChanged?.call(locked);
  }

  void _onPointerDown(PointerDownEvent e) {
    _activePointers.add(e.pointer);
    if (_activePointers.length >= 2 && !_zoomLocked) {
      _setZoomLocked(true);
    }
  }

  void _onPointerUp(PointerEvent e) {
    _activePointers.remove(e.pointer);
    _maybeUnlock();
  }

  void _maybeUnlock() {
    if (!_zoomLocked) return;
    if (_activePointers.length > 1) return;
    final scale = _ctrl.value.getMaxScaleOnAxis();
    if (scale > 1.02) return;
    // Defer to avoid setState during the matrix-change notification phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setZoomLocked(false);
    });
  }

  void _resetZoom() {
    HapticFeedback.selectionClick();
    _animateTo(Matrix4.identity());
  }

  void _animateTo(Matrix4 target) {
    _animFrom = _ctrl.value;
    _animTo = target;
    _zoomAnim
      ..value = 0
      ..forward();
  }

  void _applyZoomAnim() {
    if (_animFrom == null || _animTo == null) return;
    _ctrl.value =
        Matrix4Tween(begin: _animFrom, end: _animTo).evaluate(_zoomAnim);
  }

  void _onDoubleTap(TapDownDetails details) {
    final current = _ctrl.value.getMaxScaleOnAxis();
    if (current > 1.05) {
      _animateTo(Matrix4.identity());
    } else {
      final position = details.localPosition;
      final zoom = Matrix4.identity()
        ..translateByDouble(-position.dx * 1.5, -position.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
      _animateTo(zoom);
      // Double-tap zoom also engages the lock so the surrounding scroll
      // can't hijack the next pan.
      _setZoomLocked(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    return LayoutBuilder(
      builder: (ctx, c) {
        final viewportWidth = c.maxWidth;
        final splitX = viewportWidth * _fraction;

        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            child: Stack(
              children: [
                // ── Before layer: full InteractiveViewer for gestures.
                Positioned.fill(
                  child: GestureDetector(
                    onDoubleTapDown: _onDoubleTap,
                    // Empty onDoubleTap registers the recognizer (Flutter
                    // only fires onDoubleTapDown when an onDoubleTap is
                    // also wired).
                    onDoubleTap: () {},
                    child: InteractiveViewer(
                      transformationController: _ctrl,
                      minScale: 1.0,
                      maxScale: widget.maxScale,
                      boundaryMargin: EdgeInsets.zero,
                      clipBehavior: Clip.none,
                      child: Center(child: widget.before),
                    ),
                  ),
                ),

                // ── After layer: mirrors the same transform; clipped to
                // the right of the split. IgnorePointer so all gestures
                // land on the InteractiveViewer below.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipPath(
                      clipper: _RightClipper(fraction: _fraction),
                      child: AnimatedBuilder(
                        animation: _ctrl,
                        builder: (ctx, _) {
                          return Transform(
                            transform: _ctrl.value,
                            child: Center(child: widget.after),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // ── Labels pinned to the VISUAL sides (absolute, not
                // directional): the clipper always shows "before" on the left
                // and "after" on the right, so the tags must too — otherwise
                // RTL flips them onto the wrong halves.
                Positioned(
                  top: AppSpacing.s2,
                  left: AppSpacing.s2,
                  child:
                      _Tag(label: widget.beforeLabel, tone: _TagTone.dark),
                ),
                Positioned(
                  top: AppSpacing.s2,
                  right: AppSpacing.s2,
                  child:
                      _Tag(label: widget.afterLabel, tone: _TagTone.accent),
                ),

                // ── Zoom-reset chip in bottom-end, only when zoomed.
                PositionedDirectional(
                  bottom: AppSpacing.s2,
                  end: AppSpacing.s2,
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (ctx, _) {
                      final scale = _ctrl.value.getMaxScaleOnAxis();
                      final zoomed = scale > 1.02;
                      return AnimatedOpacity(
                        duration: AppDuration.fast,
                        opacity: zoomed ? 1.0 : 0.0,
                        child: _ZoomChip(onTap: _resetZoom),
                      );
                    },
                  ),
                ),

                // ── Split line.
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: splitX - 1,
                  child: IgnorePointer(
                    child: Container(width: 2, color: hc.accent),
                  ),
                ),

                // ── Drag strip in viewport space — a full-height, narrow
                // (44 px) grab zone centred on the split line, ALWAYS active
                // (even while zoomed). The user explicitly wants to slide the
                // split at any zoom level to compare the same detail before vs
                // after. Because the strip is narrow and sits over the
                // InteractiveViewer (which still receives every touch outside
                // it), panning the zoomed image works everywhere else; only a
                // touch that starts on the divider itself moves the split.
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: splitX - 22,
                  width: 44,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) =>
                        HapticFeedback.selectionClick(),
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _fraction =
                            ((splitX + details.delta.dx) / viewportWidth)
                                .clamp(0.05, 0.95);
                      });
                    },
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x55000000),
                              blurRadius: 10,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(Icons.swap_horiz_rounded,
                            size: 20, color: hc.accent),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RightClipper extends CustomClipper<Path> {
  const _RightClipper({required this.fraction});
  final double fraction;

  @override
  Path getClip(Size size) {
    final x = size.width * fraction;
    return Path()..addRect(Rect.fromLTRB(x, 0, size.width, size.height));
  }

  @override
  bool shouldReclip(_RightClipper old) => old.fraction != fraction;
}

enum _TagTone { dark, accent }

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.tone});
  final String label;
  final _TagTone tone;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final bg = tone == _TagTone.accent
        ? hc.accent
        : Colors.black.withValues(alpha: 0.55);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  const _ZoomChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.center_focus_strong_rounded,
                size: 12, color: Colors.white),
            SizedBox(width: 4),
            Text(
              '1×',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
