import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Theme reveal — Curtain Drop with a gentle wave that travels at a constant
// speed top → bottom. The line moves linearly so it never appears to "slow
// down" near the end; instead, the wave amplitude tapers off so the line
// lands flat. Duration is deliberately long enough to feel like a transition
// rather than a flash, but the snappiness of motion stays unchanged.
// ─────────────────────────────────────────────────────────────────────────────

abstract class ThemeRevealProfile {
  const ThemeRevealProfile();

  Duration get duration;
  Curve get curve;
  Path revealedPath(double t, Size size, math.Random seed);
}

class _CurtainDropProfile extends ThemeRevealProfile {
  const _CurtainDropProfile();

  /// Off-screen lead-in distance — the curtain starts this many logical pixels
  /// above the top edge and slides into view at constant speed.
  static const double _leadIn = 120;

  @override
  Duration get duration => const Duration(milliseconds: 1200);

  // Constant speed throughout — no easing — so the line never appears to
  // "slow down" near the end.
  @override
  Curve get curve => Curves.linear;

  @override
  Path revealedPath(double t, Size size, math.Random rng) {
    // The line travels from -_leadIn (above screen) to size.height (off
    // bottom). At t=0 the wavy edge isn't even visible yet, giving the
    // animation a sense of arrival.
    final levelY = -_leadIn + (size.height + _leadIn) * t;
    final phase = rng.nextDouble() * math.pi * 2;

    final path = Path();
    const segs = 64;
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);

    // Wave envelope: starts and ends flat; peaks gently mid-animation.
    // Spatial wavelength is long and temporal phase shift is small so the
    // wave undulates slowly — no choppy/rapid jitter.
    final amp = math.sin(t * math.pi) * 14;
    for (var i = segs; i >= 0; i--) {
      final x = (i / segs) * size.width;
      final wave = math.sin(x * 0.012 + phase + t * math.pi * 0.6) * amp;
      path.lineTo(x, levelY + wave);
    }
    path.close();
    return path;
  }
}

const _curtain = _CurtainDropProfile();

ThemeRevealProfile pickRevealProfile([math.Random? rng]) => _curtain;

// ─────────────────────────────────────────────────────────────────────────────
// SnapshotMaskPainter — paints the snapshot only OUTSIDE the revealed path.
// Uses BlendMode.dstOut so the GPU does the masking in a single pass.
// ─────────────────────────────────────────────────────────────────────────────
class SnapshotMaskPainter extends CustomPainter {
  SnapshotMaskPainter({
    required this.snapshot,
    required this.revealedPath,
  });

  final ui.Image snapshot;
  final Path revealedPath;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
        0, 0, snapshot.width.toDouble(), snapshot.height.toDouble());
    final dst = Offset.zero & size;

    canvas.saveLayer(dst, Paint());
    canvas.drawImageRect(snapshot, src, dst, Paint());
    canvas.drawPath(revealedPath, Paint()..blendMode = BlendMode.dstOut);
    canvas.restore();
  }

  @override
  bool shouldRepaint(SnapshotMaskPainter old) =>
      old.snapshot != snapshot || old.revealedPath != revealedPath;
}
