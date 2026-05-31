import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/theme/app_theme_extension.dart';
import 'aspect_ratio_chips.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CropCanvas — the interactive heart of the Crop screen.
//
// Layout: the image is drawn at its natural aspect ratio inside the available
// area (BoxFit.contain math). Rotation + flip are applied via Transform so
// the on-screen layout stays predictable.
//
// The crop rectangle is held in screen coordinates so that hit-testing the
// handles is straightforward. On every change the screen-space rect is
// converted to a normalised image-space rect (fractions 0..1) and pushed
// to [onChange] so the parent can persist it / pass it to the encoder.
//
// Gesture model:
//   • Pan starts → hit-test handles within [_handleHitRadius]; if no handle
//     is hit and the point is inside the rect, drag the whole rect.
//   • Pan updates → mutate the rect according to the active handle. Aspect
//     ratio is preserved when an [aspectRatio] is supplied (corner handles
//     scale along the diagonal; edge handles snap to the locked ratio).
//   • Pan ends → clear active handle, leave rect at rest.
// ─────────────────────────────────────────────────────────────────────────────

enum _CropHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  topMid,
  bottomMid,
  leftMid,
  rightMid,
  body,
  none,
}

class CropCanvas extends StatefulWidget {
  const CropCanvas({
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.rotationQuarters,
    required this.flipH,
    required this.flipV,
    required this.aspectRatio,
    required this.onChange,
    super.key,
  });

  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final int rotationQuarters; // 0/1/2/3 = 0°/90°/180°/270°
  final bool flipH;
  final bool flipV;

  /// Locked aspect ratio (width / height) or null for free.
  final double? aspectRatio;

  /// Fractional rect (0..1) of the IMAGE that the crop covers.
  final ValueChanged<Rect> onChange;

  static const double _handleHitRadius = 28;
  static const double _minRectSide = 60;

  @override
  State<CropCanvas> createState() => _CropCanvasState();
}

class _CropCanvasState extends State<CropCanvas> {
  Rect _imgRect = Rect.zero; // image area in viewport coords
  Rect _cropRect = Rect.zero; // crop area in viewport coords
  Size _lastViewport = Size.zero;
  _CropHandle _active = _CropHandle.none;
  Offset _grabOffset = Offset.zero; // for body drag
  bool _initialised = false;

  // Pinch-zoom of the canvas. The image + overlay are drawn in "base" viewport
  // coordinates and shown through a translate∘scale transform, so screen↔base
  // is a simple invertible map: base = (screen - _pan) / _zoom. A single
  // onScale gesture drives everything — 1 finger resizes a handle (or pans when
  // zoomed), 2 fingers zoom/pan — so there's no recognizer fight (which is what
  // made the old InteractiveViewer approach feel heavy).
  double _zoom = 1.0;
  Offset _pan = Offset.zero;
  double _gestureStartZoom = 1.0;
  Offset _gestureBaseFocal = Offset.zero;

  Offset _toBase(Offset screen) => (screen - _pan) / _zoom;

  void _resetZoom() {
    _zoom = 1.0;
    _pan = Offset.zero;
  }

  void _recomputeImageRect(Size viewport) {
    final rotated = widget.rotationQuarters.isOdd;
    final iw = (rotated ? widget.imageHeight : widget.imageWidth).toDouble();
    final ih = (rotated ? widget.imageWidth : widget.imageHeight).toDouble();
    final imageAspect = iw / ih;
    final viewAspect = viewport.width / viewport.height;
    double w, h;
    if (imageAspect > viewAspect) {
      w = viewport.width;
      h = viewport.width / imageAspect;
    } else {
      w = viewport.height * imageAspect;
      h = viewport.height;
    }
    final x = (viewport.width - w) / 2;
    final y = (viewport.height - h) / 2;
    _imgRect = Rect.fromLTWH(x, y, w, h);
  }

  void _resetCropToImage() {
    _cropRect = _imgRect;
    _applyAspectRatioToRect();
    _notify();
  }

  void _applyAspectRatioToRect() {
    final ratio = widget.aspectRatio;
    if (ratio == null) return;
    final cx = _cropRect.center.dx;
    final cy = _cropRect.center.dy;
    var w = _cropRect.width;
    var h = _cropRect.height;
    if (w / h > ratio) {
      w = h * ratio;
    } else {
      h = w / ratio;
    }
    final maxW = _imgRect.width;
    final maxH = _imgRect.height;
    if (w > maxW) {
      w = maxW;
      h = w / ratio;
    }
    if (h > maxH) {
      h = maxH;
      w = h * ratio;
    }
    _cropRect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
    _cropRect = _clampToImage(_cropRect);
  }

  Rect _clampToImage(Rect r) {
    final left = r.left.clamp(_imgRect.left, _imgRect.right - r.width);
    final top = r.top.clamp(_imgRect.top, _imgRect.bottom - r.height);
    return Rect.fromLTWH(left, top, r.width, r.height);
  }

  /// Convert a screen-space rect into a normalised rect (0..1) of the
  /// underlying source image. Rotation + flip are inverted so the rect
  /// describes pixels of the ORIGINAL image, not the transformed view.
  Rect _toImageFraction(Rect viewportRect) {
    if (_imgRect.width == 0 || _imgRect.height == 0) return Rect.zero;
    var left = (viewportRect.left - _imgRect.left) / _imgRect.width;
    var top = (viewportRect.top - _imgRect.top) / _imgRect.height;
    var right = (viewportRect.right - _imgRect.left) / _imgRect.width;
    var bottom = (viewportRect.bottom - _imgRect.top) / _imgRect.height;

    if (widget.flipH) {
      final newLeft = 1 - right;
      right = 1 - left;
      left = newLeft;
    }
    if (widget.flipV) {
      final newTop = 1 - bottom;
      bottom = 1 - top;
      top = newTop;
    }

    // Rotate the rect back into the source image's coordinate frame.
    Rect r = Rect.fromLTRB(left, top, right, bottom);
    for (var i = 0; i < (4 - widget.rotationQuarters) % 4; i++) {
      r = Rect.fromLTRB(r.top, 1 - r.right, r.bottom, 1 - r.left);
    }
    return r;
  }

  void _notify() {
    widget.onChange(_toImageFraction(_cropRect));
  }

  _CropHandle _hitTest(Offset p) {
    final tol = CropCanvas._handleHitRadius;
    bool near(Offset target) => (target - p).distance <= tol;
    if (near(_cropRect.topLeft)) return _CropHandle.topLeft;
    if (near(_cropRect.topRight)) return _CropHandle.topRight;
    if (near(_cropRect.bottomLeft)) return _CropHandle.bottomLeft;
    if (near(_cropRect.bottomRight)) return _CropHandle.bottomRight;
    if ((p.dx - _cropRect.center.dx).abs() < tol &&
        (p.dy - _cropRect.top).abs() < tol) {
      return _CropHandle.topMid;
    }
    if ((p.dx - _cropRect.center.dx).abs() < tol &&
        (p.dy - _cropRect.bottom).abs() < tol) {
      return _CropHandle.bottomMid;
    }
    if ((p.dx - _cropRect.left).abs() < tol &&
        (p.dy - _cropRect.center.dy).abs() < tol) {
      return _CropHandle.leftMid;
    }
    if ((p.dx - _cropRect.right).abs() < tol &&
        (p.dy - _cropRect.center.dy).abs() < tol) {
      return _CropHandle.rightMid;
    }
    if (_cropRect.contains(p)) return _CropHandle.body;
    return _CropHandle.none;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _gestureStartZoom = _zoom;
    _gestureBaseFocal = _toBase(d.localFocalPoint);
    if (d.pointerCount == 1) {
      final handle = _hitTest(_gestureBaseFocal);
      _active = handle;
      if (handle != _CropHandle.none) {
        _grabOffset = _gestureBaseFocal - _cropRect.topLeft;
        HapticFeedback.selectionClick();
      }
    } else {
      _active = _CropHandle.none;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // Two fingers (or an active pinch) → zoom + pan the canvas; keep the focal
    // point pinned under the fingers. The crop rect is untouched.
    if (d.pointerCount >= 2 || d.scale != 1.0) {
      final z = (_gestureStartZoom * d.scale).clamp(1.0, 6.0);
      setState(() {
        _zoom = z;
        // At 1× the image fills normally (no offset); above 1× keep the pinch
        // focal point pinned under the fingers.
        _pan = z <= 1.001
            ? Offset.zero
            : d.localFocalPoint - _gestureBaseFocal * z;
      });
      return;
    }
    // One finger: drag a handle, or pan the image when zoomed in.
    if (_active == _CropHandle.none) {
      if (_zoom > 1.01) {
        setState(() => _pan += d.focalPointDelta);
      }
      return;
    }
    final p = _toBase(d.localFocalPoint);
    var r = _cropRect;
    switch (_active) {
      case _CropHandle.topLeft:
        r = Rect.fromLTRB(p.dx, p.dy, r.right, r.bottom);
        break;
      case _CropHandle.topRight:
        r = Rect.fromLTRB(r.left, p.dy, p.dx, r.bottom);
        break;
      case _CropHandle.bottomLeft:
        r = Rect.fromLTRB(p.dx, r.top, r.right, p.dy);
        break;
      case _CropHandle.bottomRight:
        r = Rect.fromLTRB(r.left, r.top, p.dx, p.dy);
        break;
      case _CropHandle.topMid:
        r = Rect.fromLTRB(r.left, p.dy, r.right, r.bottom);
        break;
      case _CropHandle.bottomMid:
        r = Rect.fromLTRB(r.left, r.top, r.right, p.dy);
        break;
      case _CropHandle.leftMid:
        r = Rect.fromLTRB(p.dx, r.top, r.right, r.bottom);
        break;
      case _CropHandle.rightMid:
        r = Rect.fromLTRB(r.left, r.top, p.dx, r.bottom);
        break;
      case _CropHandle.body:
        final newTopLeft = p - _grabOffset;
        r = Rect.fromLTWH(
            newTopLeft.dx, newTopLeft.dy, r.width, r.height);
        break;
      case _CropHandle.none:
        return;
    }

    // Snap to min size, then to aspect ratio (locked corner edges scale
    // along the diagonal so the user "feels" the constraint immediately).
    r = _snapMinSize(r);
    final ratio = widget.aspectRatio;
    if (ratio != null && _active != _CropHandle.body) {
      r = _snapToRatio(r, ratio, _active);
    }
    r = _clampToImage(r);

    setState(() => _cropRect = r);
    _notify();
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _active = _CropHandle.none;
  }

  Rect _snapMinSize(Rect r) {
    var left = r.left, top = r.top, right = r.right, bottom = r.bottom;
    if (right - left < CropCanvas._minRectSide) {
      if (_active == _CropHandle.topLeft ||
          _active == _CropHandle.bottomLeft ||
          _active == _CropHandle.leftMid) {
        left = right - CropCanvas._minRectSide;
      } else {
        right = left + CropCanvas._minRectSide;
      }
    }
    if (bottom - top < CropCanvas._minRectSide) {
      if (_active == _CropHandle.topLeft ||
          _active == _CropHandle.topRight ||
          _active == _CropHandle.topMid) {
        top = bottom - CropCanvas._minRectSide;
      } else {
        bottom = top + CropCanvas._minRectSide;
      }
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect _snapToRatio(Rect r, double ratio, _CropHandle handle) {
    final w = r.width;
    final h = r.height;
    final isCorner = handle == _CropHandle.topLeft ||
        handle == _CropHandle.topRight ||
        handle == _CropHandle.bottomLeft ||
        handle == _CropHandle.bottomRight;

    double newW, newH;
    if (isCorner) {
      // Pick the dimension that's grown more; derive the other from ratio.
      if (w / h > ratio) {
        newH = h;
        newW = h * ratio;
      } else {
        newW = w;
        newH = w / ratio;
      }
    } else {
      // Edge handles: keep the axis the user is dragging, derive the other.
      if (handle == _CropHandle.leftMid || handle == _CropHandle.rightMid) {
        newW = w;
        newH = w / ratio;
      } else {
        newH = h;
        newW = h * ratio;
      }
    }

    double left = r.left, top = r.top, right = r.right, bottom = r.bottom;
    switch (handle) {
      case _CropHandle.topLeft:
        left = right - newW;
        top = bottom - newH;
        break;
      case _CropHandle.topRight:
        right = left + newW;
        top = bottom - newH;
        break;
      case _CropHandle.bottomLeft:
        left = right - newW;
        bottom = top + newH;
        break;
      case _CropHandle.bottomRight:
        right = left + newW;
        bottom = top + newH;
        break;
      case _CropHandle.topMid:
      case _CropHandle.bottomMid:
        final cx = (left + right) / 2;
        left = cx - newW / 2;
        right = cx + newW / 2;
        if (handle == _CropHandle.topMid) {
          top = bottom - newH;
        } else {
          bottom = top + newH;
        }
        break;
      case _CropHandle.leftMid:
      case _CropHandle.rightMid:
        final cy = (top + bottom) / 2;
        top = cy - newH / 2;
        bottom = cy + newH / 2;
        if (handle == _CropHandle.leftMid) {
          left = right - newW;
        } else {
          right = left + newW;
        }
        break;
      case _CropHandle.body:
      case _CropHandle.none:
        break;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  void didUpdateWidget(covariant CropCanvas old) {
    super.didUpdateWidget(old);
    final rotationChanged = old.rotationQuarters != widget.rotationQuarters;
    final ratioChanged = old.aspectRatio != widget.aspectRatio;
    if (rotationChanged) {
      // After rotation we recompute the image rect and reset the crop to
      // cover it — the previous crop is no longer meaningful in the new
      // orientation. Drop any zoom too so the fresh crop starts framed.
      _resetZoom();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _recomputeImageRect(_lastViewport);
        setState(_resetCropToImage);
      });
    } else if (ratioChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(_applyAspectRatioToRect);
        _notify();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final viewport = Size(c.maxWidth, c.maxHeight);
      if (viewport != _lastViewport || !_initialised) {
        _lastViewport = viewport;
        _recomputeImageRect(viewport);
        if (!_initialised) {
          _cropRect = _imgRect;
          _applyAspectRatioToRect();
          _initialised = true;
          // Defer the first onChange call so the parent isn't notified
          // during build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _notify();
          });
        } else {
          _cropRect = _clampToImage(_cropRect);
        }
      }
      // For rotation 90/270 we render the image into a SizedBox that's
      // sized to the IMAGE's natural aspect (i.e. the displayRect with
      // width/height swapped). After the Transform rotates it 90°, the
      // rotated box visually matches the displayRect — no letterboxing.
      final rotated = widget.rotationQuarters.isOdd;
      final preW = rotated ? _imgRect.height : _imgRect.width;
      final preH = rotated ? _imgRect.width : _imgRect.height;
      // One gesture detector OUTSIDE the zoom transform (so its coordinates are
      // plain screen space); the image + overlay live INSIDE the transform and
      // scale together. base = (screen - _pan) / _zoom.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: ClipRect(
          child: Transform(
            transform: Matrix4.identity()
              ..translateByDouble(_pan.dx, _pan.dy, 0, 1)
              ..scaleByDouble(_zoom, _zoom, 1, 1),
            child: Stack(
              children: [
                // ── Image with rotation + flip ─────────────────────────
                Positioned(
                  left: _imgRect.left,
                  top: _imgRect.top,
                  width: _imgRect.width,
                  height: _imgRect.height,
                  child: Center(
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..rotateZ(widget.rotationQuarters * math.pi / 2)
                        ..scaleByDouble(
                          widget.flipH ? -1.0 : 1.0,
                          widget.flipV ? -1.0 : 1.0,
                          1.0,
                          1.0,
                        ),
                      child: SizedBox(
                        width: preW,
                        height: preH,
                        child: Image.memory(
                          widget.imageBytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Crop overlay (painted in base coords; gestures handled
                // by the outer detector). ─────────────────────────────────
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CropOverlayPainter(
                        cropRect: _cropRect,
                        accent: context.hc.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CropOverlayPainter — paints the dimmed area outside the crop rectangle,
// the rule-of-thirds grid inside, the rect border, and the 8 handles.
// ─────────────────────────────────────────────────────────────────────────────

class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter({required this.cropRect, required this.accent});

  final Rect cropRect;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRect(cropRect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, hole),
      dim,
    );

    // Rule-of-thirds grid lines.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final y = cropRect.top + cropRect.height * (i / 3);
      canvas.drawLine(
          Offset(cropRect.left, y), Offset(cropRect.right, y), grid);
      final x = cropRect.left + cropRect.width * (i / 3);
      canvas.drawLine(
          Offset(x, cropRect.top), Offset(x, cropRect.bottom), grid);
    }

    // Border.
    final border = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawRect(cropRect, border);

    // Corner ticks (thicker L-shapes) and edge midpoint nubs.
    final tick = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const tickLen = 18.0;
    void drawCornerTick(Offset corner, double dx, double dy) {
      canvas.drawLine(corner, Offset(corner.dx + dx, corner.dy), tick);
      canvas.drawLine(corner, Offset(corner.dx, corner.dy + dy), tick);
    }

    drawCornerTick(cropRect.topLeft, tickLen, tickLen);
    drawCornerTick(cropRect.topRight, -tickLen, tickLen);
    drawCornerTick(cropRect.bottomLeft, tickLen, -tickLen);
    drawCornerTick(cropRect.bottomRight, -tickLen, -tickLen);

    // Edge midpoint nubs.
    final nub = Paint()..color = Colors.white;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(cropRect.center.dx, cropRect.top),
                width: 24,
                height: 4),
            const Radius.circular(2)),
        nub);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(cropRect.center.dx, cropRect.bottom),
                width: 24,
                height: 4),
            const Radius.circular(2)),
        nub);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(cropRect.left, cropRect.center.dy),
                width: 4,
                height: 24),
            const Radius.circular(2)),
        nub);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(cropRect.right, cropRect.center.dy),
                width: 4,
                height: 24),
            const Radius.circular(2)),
        nub);
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) =>
      old.cropRect != cropRect || old.accent != accent;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers — CropAspectRatio → numeric width / height ratio.
// ─────────────────────────────────────────────────────────────────────────────

double? aspectRatioValue(
  CropAspectRatio r, {
  required int imageWidth,
  required int imageHeight,
  required int rotationQuarters,
}) {
  final rotated = rotationQuarters.isOdd;
  final w = (rotated ? imageHeight : imageWidth).toDouble();
  final h = (rotated ? imageWidth : imageHeight).toDouble();
  return switch (r) {
    CropAspectRatio.free => null,
    CropAspectRatio.original => w / h,
    CropAspectRatio.square => 1.0,
    CropAspectRatio.fourThree => 4 / 3,
    CropAspectRatio.threeFour => 3 / 4,
    CropAspectRatio.sixteenNine => 16 / 9,
    CropAspectRatio.nineSixteen => 9 / 16,
  };
}
