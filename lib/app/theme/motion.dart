import 'package:flutter/material.dart';
import 'design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Motion library — every transition in the app passes through here.
// Goals:
//   • One vocabulary (fade, shared-axis, slide-up) → consistent feel
//   • Respect MediaQuery.disableAnimations / accessibleNavigation
//   • All durations & curves come from design tokens
// ─────────────────────────────────────────────────────────────────────────────

/// Are reduced-motion / a11y animations preferences set?
bool prefersReducedMotion(BuildContext context) {
  final mq = MediaQuery.maybeOf(context);
  if (mq == null) return false;
  return mq.disableAnimations || mq.accessibleNavigation;
}

// ─────────────────────────────────────────────────────────────────────────────
// Page transitions — modal-style helpers around Navigator.push.
// ─────────────────────────────────────────────────────────────────────────────

/// Fade-through: previous content fades out, new content fades in.
/// Use for tab switches and lateral navigation within the same hierarchy.
Route<T> fadeThroughRoute<T>(WidgetBuilder builder, {Duration? duration}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration ?? AppDuration.screen,
    reverseTransitionDuration: duration ?? AppDuration.screen,
    pageBuilder: (ctx, _, __) => builder(ctx),
    transitionsBuilder: (ctx, animation, secondary, child) {
      if (prefersReducedMotion(ctx)) return child;
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: AppCurves.standard,
        ),
        child: child,
      );
    },
  );
}

/// Shared-axis X: pages slide horizontally with subtle fade.
/// Use for hierarchical navigation (Library → Asset Detail).
Route<T> sharedAxisRoute<T>(
  WidgetBuilder builder, {
  Duration? duration,
  bool reverse = false,
}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration ?? AppDuration.screen,
    reverseTransitionDuration: duration ?? AppDuration.screen,
    pageBuilder: (ctx, _, __) => builder(ctx),
    transitionsBuilder: (ctx, animation, secondary, child) {
      if (prefersReducedMotion(ctx)) return child;
      final dir = Directionality.of(ctx);
      final sign = (reverse ? -1 : 1) * (dir == TextDirection.rtl ? -1 : 1);

      final slideIn = Tween<Offset>(
        begin: Offset(sign * 0.08, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: AppCurves.standard));

      final slideOut = Tween<Offset>(
        begin: Offset.zero,
        end: Offset(-sign * 0.06, 0),
      ).animate(CurvedAnimation(parent: secondary, curve: AppCurves.standard));

      return SlideTransition(
        position: slideOut,
        child: SlideTransition(
          position: slideIn,
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: AppCurves.standard,
            ),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Slide-up modal — full-screen sheet that comes from the bottom.
/// Use for compose/editor screens (Compress, Surgical, Video Editor).
Route<T> slideUpRoute<T>(WidgetBuilder builder, {Duration? duration}) {
  return PageRouteBuilder<T>(
    fullscreenDialog: true,
    transitionDuration: duration ?? AppDuration.sheet,
    reverseTransitionDuration: duration ?? AppDuration.screen,
    pageBuilder: (ctx, _, __) => builder(ctx),
    transitionsBuilder: (ctx, animation, _, child) {
      if (prefersReducedMotion(ctx)) return child;
      final slide = Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: AppCurves.emphasized,
        reverseCurve: AppCurves.accelerate,
      ));
      return SlideTransition(position: slide, child: child);
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero specs — for thumbnail ↔ detail flights.
// ─────────────────────────────────────────────────────────────────────────────

/// Standardized Hero flight: gentle scale + fade through.
class HaynHeroController {
  static CreateRectTween rectTween() =>
      (begin, end) => MaterialRectArcTween(begin: begin, end: end);

  static Widget flightShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: AppCurves.standard),
      child: toContext.widget,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Staggered reveal — for lists/grids that just appeared.
// Wrap each item with HaynStagger(index: i, child: ...) inside a list.
// ─────────────────────────────────────────────────────────────────────────────

class HaynStagger extends StatelessWidget {
  const HaynStagger({
    required this.index,
    required this.child,
    this.delayPerItem = const Duration(milliseconds: 22),
    this.maxIndex = 12,
    super.key,
  });

  final int index;
  final Widget child;
  final Duration delayPerItem;
  final int maxIndex;

  @override
  Widget build(BuildContext context) {
    if (prefersReducedMotion(context)) return child;
    // Only the first screenful staggers in. Past maxIndex we return the child
    // untouched — no AnimationController per tile — so flinging through a huge
    // grid never spins up (and tears down) thousands of tickers mid-scroll.
    // The entrance flourish is for the initial reveal, not for deep scrolling.
    if (index > maxIndex) return child;
    final delay = delayPerItem * index;

    return _DelayedFadeSlide(
      delay: delay,
      duration: AppDuration.normal,
      child: child,
    );
  }
}

class _DelayedFadeSlide extends StatefulWidget {
  const _DelayedFadeSlide({
    required this.delay,
    required this.duration,
    required this.child,
  });
  final Duration delay;
  final Duration duration;
  final Widget child;

  @override
  State<_DelayedFadeSlide> createState() => _DelayedFadeSlideState();
}

class _DelayedFadeSlideState extends State<_DelayedFadeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _ctrl, curve: AppCurves.decelerate);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AnimatedSwitcher transitions — used inside widgets that swap content
// (e.g., empty state ↔ grid, selection bar ↔ nav bar).
// ─────────────────────────────────────────────────────────────────────────────

/// Fades + slight scale. Good for inline content swaps.
Widget fadeScaleTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween<double>(begin: 0.98, end: 1).animate(
        CurvedAnimation(parent: animation, curve: AppCurves.decelerate),
      ),
      child: child,
    ),
  );
}

/// Slide up + fade. For bottom-anchored content swaps.
Widget slideUpFadeTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.15),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(parent: animation, curve: AppCurves.decelerate),
      ),
      child: child,
    ),
  );
}
