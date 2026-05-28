import 'package:flutter/material.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton — placeholder shapes that pulse opacity between two values.
// Surface-sunken background is the canvas; opacity drives the "breathing".
//
//   HaynShimmerGroup  → wrap a region; one shared ticker drives all skeletons.
//                       Optional but recommended for grids/lists.
//   HaynSkeleton      → line / rect / circle shapes.
//   HaynSkeletonGrid  → pre-built 3-col grid (matches MediaGrid layout).
// ─────────────────────────────────────────────────────────────────────────────

class HaynShimmerGroup extends StatefulWidget {
  const HaynShimmerGroup({
    required this.child,
    this.duration = const Duration(milliseconds: 1100),
    super.key,
  });

  final Widget child;
  final Duration duration;

  static Animation<double>? maybeOf(BuildContext context) {
    final inh = context
        .dependOnInheritedWidgetOfExactType<_ShimmerInherited>();
    return inh?.animation;
  }

  @override
  State<HaynShimmerGroup> createState() => _HaynShimmerGroupState();
}

class _HaynShimmerGroupState extends State<HaynShimmerGroup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..repeat(reverse: true);

  late final Animation<double> _anim = Tween<double>(begin: 0.4, end: 0.95)
      .animate(CurvedAnimation(parent: _ctrl, curve: AppCurves.standard));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ShimmerInherited(animation: _anim, child: widget.child);
  }
}

class _ShimmerInherited extends InheritedWidget {
  const _ShimmerInherited({required this.animation, required super.child});
  final Animation<double> animation;

  @override
  bool updateShouldNotify(covariant _ShimmerInherited oldWidget) =>
      animation != oldWidget.animation;
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton shapes
// ─────────────────────────────────────────────────────────────────────────────

class HaynSkeleton extends StatelessWidget {
  const HaynSkeleton.line({
    this.width,
    this.height = 12,
    super.key,
  })  : _shape = _Shape.line,
        radius = 6;

  const HaynSkeleton.rect({
    required this.width,
    required this.height,
    this.radius = AppRadius.md,
    super.key,
  }) : _shape = _Shape.rect;

  const HaynSkeleton.circle({
    required double size,
    super.key,
  })  : _shape = _Shape.circle,
        width = size,
        height = size,
        radius = 0;

  final double? width;
  final double height;
  final double radius;
  final _Shape _shape;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final shared = HaynShimmerGroup.maybeOf(context);
    final base = hc.surfaceSunken;

    final box = _shape == _Shape.circle
        ? Container(
            width: width,
            height: height,
            decoration: BoxDecoration(color: base, shape: BoxShape.circle),
          )
        : Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(radius),
            ),
          );

    if (shared != null) {
      return AnimatedBuilder(
        animation: shared,
        builder: (_, child) => Opacity(opacity: shared.value, child: child),
        child: box,
      );
    }
    return _SoloShimmer(child: box);
  }
}

enum _Shape { line, rect, circle }

class _SoloShimmer extends StatefulWidget {
  const _SoloShimmer({required this.child});
  final Widget child;
  @override
  State<_SoloShimmer> createState() => _SoloShimmerState();
}

class _SoloShimmerState extends State<_SoloShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  late final Animation<double> _anim = Tween<double>(begin: 0.4, end: 0.95)
      .animate(CurvedAnimation(parent: _ctrl, curve: AppCurves.standard));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Opacity(opacity: _anim.value, child: child),
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HaynSkeletonGrid — 3-column square grid for media-grid loading state.
// ─────────────────────────────────────────────────────────────────────────────

class HaynSkeletonGrid extends StatelessWidget {
  const HaynSkeletonGrid({
    this.crossAxisCount = 3,
    this.count = 24,
    this.spacing = AppSpacing.gridGap,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final int crossAxisCount;
  final int count;
  final double spacing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return HaynShimmerGroup(
      child: Padding(
        padding: padding,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
          ),
          itemCount: count,
          itemBuilder: (_, __) => const HaynSkeleton.rect(
            width: double.infinity,
            height: double.infinity,
            radius: 0,
          ),
        ),
      ),
    );
  }
}
