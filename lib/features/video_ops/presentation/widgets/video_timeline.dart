import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VideoTimeline — the trim scrubber. A long bar with two draggable handles
// for start/end. Keyframe ticks hint whether a cut at the chosen point is
// lossless or requires a smart-cut re-encode.
//
// Times are passed in seconds; the parent owns the state and decides what to
// do with the updated range.
// ─────────────────────────────────────────────────────────────────────────────

class VideoTimeline extends StatelessWidget {
  const VideoTimeline({
    required this.duration,
    required this.start,
    required this.end,
    required this.onChanged,
    this.keyframeSecs = const [],
    super.key,
  });

  /// Total clip duration (sec).
  final double duration;

  /// Selected start time (sec).
  final double start;

  /// Selected end time (sec).
  final double end;

  /// Receives the new (start, end).
  final void Function(double start, double end) onChanged;

  /// Keyframe positions in seconds (visualised as ticks).
  final List<double> keyframeSecs;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth;
        final startX = (start / duration).clamp(0.0, 1.0) * w;
        final endX = (end / duration).clamp(0.0, 1.0) * w;
        return SizedBox(
          height: 64,
          child: Stack(
            children: [
              Positioned(top: 24, left: 0, right: 0, child: _Track()),
              for (final k in keyframeSecs)
                Positioned(
                  top: 14,
                  left: (k / duration).clamp(0.0, 1.0) * w - 1,
                  child: _Keyframe(),
                ),
              Positioned(
                top: 24,
                left: startX,
                width: (endX - startX).clamp(0.0, w),
                child: _SelectionFill(),
              ),
              Positioned(
                top: 12, bottom: 12, left: startX - 12,
                child: _Handle(
                  isStart: true,
                  onDragUpdate: (dx) {
                    final newStart =
                        ((startX + dx) / w * duration).clamp(0.0, end - 0.5);
                    onChanged(newStart, end);
                  },
                ),
              ),
              Positioned(
                top: 12, bottom: 12, left: endX - 12,
                child: _Handle(
                  isStart: false,
                  onDragUpdate: (dx) {
                    final newEnd =
                        ((endX + dx) / w * duration).clamp(start + 0.5, duration);
                    onChanged(start, newEnd);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Track extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      height: 16,
      decoration: BoxDecoration(
        color: hc.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    );
  }
}

class _Keyframe extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(width: 2, height: 8, color: hc.text3);
  }
}

class _SelectionFill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      height: 16,
      decoration: BoxDecoration(
        color: hc.accentSoft,
        border: Border.symmetric(
          horizontal: BorderSide(color: hc.accent, width: 1.5),
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.isStart, required this.onDragUpdate});
  final bool isStart;
  final ValueChanged<double> onDragUpdate;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => HapticFeedback.selectionClick(),
      onHorizontalDragUpdate: (details) => onDragUpdate(details.delta.dx),
      child: Container(
        width: 24, height: 40,
        decoration: BoxDecoration(
          color: hc.accent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: const [
            BoxShadow(color: Color(0x44000000), blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        alignment: Alignment.center,
        child: Container(
          width: 3, height: 18,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
