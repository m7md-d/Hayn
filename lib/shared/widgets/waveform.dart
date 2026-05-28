import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme/app_theme_extension.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HaynWaveform — synthetic but deterministic audio waveform. A fixed `seed`
// produces the same bars every render so a single asset always looks the
// same. `cursorFraction` (0..1) dims bars beyond the playback head.
//
// Once real audio analysis lands, swap the bar generation for actual
// peak data. The widget signature stays the same.
// ─────────────────────────────────────────────────────────────────────────────

class HaynWaveform extends StatelessWidget {
  const HaynWaveform({
    required this.seed,
    this.cursorFraction = 0,
    this.barCount = 64,
    this.height = 96,
    this.activeColor,
    this.inactiveColor,
    super.key,
  });

  final int seed;
  final double cursorFraction;
  final int barCount;
  final double height;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _WaveformPainter(
          seed: seed,
          cursorFraction: cursorFraction,
          barCount: barCount,
          activeColor: activeColor ?? hc.accent,
          inactiveColor: inactiveColor ?? hc.surfaceSunken,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.seed,
    required this.cursorFraction,
    required this.barCount,
    required this.activeColor,
    required this.inactiveColor,
  });

  final int seed;
  final double cursorFraction;
  final int barCount;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final spacing = 2.0;
    final barW = (size.width - (barCount - 1) * spacing) / barCount;
    final cursorX = size.width * cursorFraction;

    for (var i = 0; i < barCount; i++) {
      final amp = 0.25 +
          math.pow(math.sin(i * 0.6) * 0.5 + 0.5, 1.6) * 0.5 +
          rng.nextDouble() * 0.15;
      final barH = size.height * amp.clamp(0.15, 1.0);
      final x = i * (barW + spacing);
      final color = (x + barW / 2) <= cursorX ? activeColor : inactiveColor;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, (size.height - barH) / 2, barW, barH),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(rect, Paint()..color = color);
    }

    // Cursor line
    if (cursorFraction > 0) {
      canvas.drawLine(
        Offset(cursorX, 0),
        Offset(cursorX, size.height),
        Paint()
          ..color = activeColor
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.cursorFraction != cursorFraction ||
      old.seed != seed ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor;
}
