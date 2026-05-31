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
// Zoom model (matches iOS Photos): the crop FRAME lives in plain screen
// coordinates and never scales — only the IMAGE pans/zooms beneath it. Zooming
// in therefore lets you select a smaller part of the image with precision while
// the frame keeps the same on-screen size. The pan is constrained so the image
// always fully covers the frame (you can never crop empty space).
//
// Gesture model (a single onScale recognizer, so there's no recognizer fight):
//   • 1 finger on a resize handle → reshape the frame.
//   • 1 finger inside the frame   → move the frame as a whole.
//   • 1 finger outside the frame  → pan the image beneath it.
//   • 2 fingers                   → zoom + pan the image (focal pinned).
// On every change the screen-space frame is un-projected through the image
// transform into a normalised image-space rect (fractions 0..1) and pushed to
// [onChange] so the parent can persist it / pass it to the encoder.
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
  static const double _maxZoom = 8;

  @override
  State<CropCanvas> createState() => _CropCanvasState();
}

class _CropCanvasState extends State<CropCanvas> {
  Rect _imgRect = Rect.zero; // image area in base (unzoomed) viewport coords
  Rect _cropRect = Rect.zero; // crop FRAME in screen coords (never scaled)
  Size _lastViewport = Size.zero;
  _CropHandle _active = _CropHandle.none;
  Offset _grabOffset = Offset.zero; // finger → frame.topLeft, for body drags
  bool _initialised = false;

  // Zoom/pan of the IMAGE only. The image is shown through a translate∘scale
  // transform; the frame is drawn outside it. base→screen is s = b*_zoom + _pan,
  // so screen→base is b = (s - _pan) / _zoom.
  double _zoom = 1.0;
  Offset _pan = Offset.zero;
  double _gestureStartZoom = 1.0;
  Offset _gestureBaseFocal = Offset.zero;

  Offset _toBase(Offset screen) => (screen - _pan) / _zoom;

  void _resetZoom() {
    _zoom = 1.0;
    _pan = Offset.zero;
  }

  // The image's on-screen rect under the current zoom/pan.
  Rect _displayImgRect() => Rect.fromLTRB(
        _imgRect.left * _zoom + _pan.dx,
        _imgRect.top * _zoom + _pan.dy,
        _imgRect.right * _zoom + _pan.dx,
        _imgRect.bottom * _zoom + _pan.dy,
      );

  // The frame may sit anywhere on the visible image — i.e. the displayed image
  // clipped to the viewport.
  Rect _frameBounds() {
    final view = Offset.zero & _lastViewport;
    final b = _displayImgRect().intersect(view);
    if (b.width <= 0 || b.height <= 0) return view;
    return b;
  }

  // Constrain the pan so the displayed image always fully covers the frame
  // (no empty space can fall inside the crop). When the frame is larger than
  // the image on an axis, centre it instead.
  Offset _clampPan(Offset p, double z) {
    final maxX = _cropRect.left - _imgRect.left * z;
    final minX = _cropRect.right - _imgRect.right * z;
    final maxY = _cropRect.top - _imgRect.top * z;
    final minY = _cropRect.bottom - _imgRect.bottom * z;
    final dx = minX <= maxX ? p.dx.clamp(minX, maxX) : (minX + maxX) / 2;
    final dy = minY <= maxY ? p.dy.clamp(minY, maxY) : (minY + maxY) / 2;
    return Offset(dx, dy);
  }

  // Screen-space rect → base (unzoomed) viewport coords.
  Rect _screenToBaseRect(Rect r) => Rect.fromLTRB(
        (r.left - _pan.dx) / _zoom,
        (r.top - _pan.dy) / _zoom,
        (r.right - _pan.dx) / _zoom,
        (r.bottom - _pan.dy) / _zoom,
      );

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
    final bounds = _frameBounds();
    final cx = _cropRect.center.dx;
    final cy = _cropRect.center.dy;
    var w = _cropRect.width;
    var h = _cropRect.height;
    if (w / h > ratio) {
      w = h * ratio;
    } else {
      h = w / ratio;
    }
    final maxW = bounds.width;
    final maxH = bounds.height;
    if (w > maxW) {
      w = maxW;
      h = w / ratio;
    }
    if (h > maxH) {
      h = maxH;
      w = h * ratio;
    }
    _cropRect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
    _cropRect = _clampFrame(_cropRect);
  }

  /// Clamp the frame into the visible-image bounds. The SIZE is clamped first so
  /// the position-clamp limits can never invert (lower > upper), which is what
  /// `double.clamp` throws on.
  Rect _clampFrame(Rect r) {
    final b = _frameBounds();
    final w = r.width.clamp(0.0, b.width);
    final h = r.height.clamp(0.0, b.height);
    final left = r.left.clamp(b.left, b.right - w);
    final top = r.top.clamp(b.top, b.bottom - h);
    return Rect.fromLTWH(left, top, w, h);
  }

  /// Convert a base-space rect into a normalised rect (0..1) of the underlying
  /// source image. Rotation + flip are inverted so the rect describes pixels of
  /// the ORIGINAL image, not the transformed view.
  Rect _toImageFraction(Rect baseRect) {
    if (_imgRect.width == 0 || _imgRect.height == 0) return Rect.zero;
    var left = (baseRect.left - _imgRect.left) / _imgRect.width;
    var top = (baseRect.top - _imgRect.top) / _imgRect.height;
    var right = (baseRect.right - _imgRect.left) / _imgRect.width;
    var bottom = (baseRect.bottom - _imgRect.top) / _imgRect.height;

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
    // Guard against tiny float drift at the edges.
    return Rect.fromLTRB(
      r.left.clamp(0.0, 1.0),
      r.top.clamp(0.0, 1.0),
      r.right.clamp(0.0, 1.0),
      r.bottom.clamp(0.0, 1.0),
    );
  }

  void _notify() {
    widget.onChange(_toImageFraction(_screenToBaseRect(_cropRect)));
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
      final handle = _hitTest(d.localFocalPoint);
      _active = handle;
      if (handle == _CropHandle.body) {
        // Grab the frame so a drag moves it as a whole (keeping its size).
        _grabOffset = d.localFocalPoint - _cropRect.topLeft;
      } else if (handle != _CropHandle.none) {
        HapticFeedback.selectionClick();
      }
      // handle == none → a drag outside the frame pans the image.
    } else {
      _active = _CropHandle.none;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // Two fingers (or any pinch) → zoom + pan the IMAGE only. The frame is
    // fixed on screen; keep the focal point pinned and the image covering it.
    if (d.pointerCount >= 2 || d.scale != 1.0) {
      final z = (_gestureStartZoom * d.scale).clamp(1.0, CropCanvas._maxZoom);
      final p = d.localFocalPoint - _gestureBaseFocal * z;
      setState(() {
        _zoom = z;
        _pan = _clampPan(p, z);
      });
      _notify();
      return;
    }
    // One finger outside the frame → pan the image under it.
    if (_active == _CropHandle.none) {
      setState(() => _pan = _clampPan(_pan + d.focalPointDelta, _zoom));
      _notify();
      return;
    }
    // One finger on a handle → reshape the frame; inside it → move the frame.
    // All in plain screen coordinates (the frame never scales).
    final p = d.localFocalPoint;
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
        final tl = p - _grabOffset;
        r = Rect.fromLTWH(tl.dx, tl.dy, r.width, r.height);
        break;
      case _CropHandle.none:
        return;
    }

    // Resize handles snap to min size + aspect ratio (locked corner edges scale
    // along the diagonal so the user "feels" the constraint immediately); a
    // body move just slides the frame, keeping its size.
    if (_active != _CropHandle.body) {
      r = _snapMinSize(r);
      final ratio = widget.aspectRatio;
      if (ratio != null) {
        r = _snapToRatio(r, ratio, _active);
      }
    }
    r = _clampFrame(r);

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
          // Viewport changed (e.g. device rotation): a stale zoom can't be
          // trusted against the new geometry — reset it and re-clamp.
          _resetZoom();
          _cropRect = _clampFrame(_cropRect);
        }
      }
      // For rotation 90/270 we render the image into a SizedBox that's
      // sized to the IMAGE's natural aspect (i.e. the displayRect with
      // width/height swapped). After the Transform rotates it 90°, the
      // rotated box visually matches the displayRect — no letterboxing.
      final rotated = widget.rotationQuarters.isOdd;
      final preW = rotated ? _imgRect.height : _imgRect.width;
      final preH = rotated ? _imgRect.width : _imgRect.height;
      // One gesture detector over the whole canvas. Only the IMAGE lives inside
      // the zoom/pan transform; the crop frame is painted outside it so it
      // keeps its on-screen size regardless of zoom.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        child: ClipRect(
          child: Stack(
            children: [
              // ── Image with zoom/pan, then rotation + flip ──────────────
              Transform(
                transform: Matrix4.identity()
                  ..translateByDouble(_pan.dx, _pan.dy, 0, 1)
                  ..scaleByDouble(_zoom, _zoom, 1, 1),
                child: Stack(
                  children: [
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
                  ],
                ),
              ),
              // ── Crop frame (screen coords, never scaled). ─────────────────
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
