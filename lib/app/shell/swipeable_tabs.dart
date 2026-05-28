import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SwipeableTabs — PageView container for the four root branches. All four
// stay mounted, so state survives across tab switches. The PageController
// follows `currentIndex` (external taps trigger animateToPage); user swipes
// trigger `onPageChanged`. RTL-aware via PageView.reverse.
// ─────────────────────────────────────────────────────────────────────────────

class SwipeableTabs extends StatefulWidget {
  const SwipeableTabs({
    required this.children,
    required this.currentIndex,
    required this.onPageChanged,
    super.key,
  });

  final List<Widget> children;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  @override
  State<SwipeableTabs> createState() => _SwipeableTabsState();
}

class _SwipeableTabsState extends State<SwipeableTabs> {
  late final PageController _ctrl =
      PageController(initialPage: widget.currentIndex);

  @override
  void didUpdateWidget(SwipeableTabs old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      // External change (tab tap or deep link) — settle PageView to match.
      // Skip if it's already there (user-driven swipe just settled).
      final settled = _ctrl.hasClients ? _ctrl.page?.round() : null;
      if (settled != widget.currentIndex) {
        _ctrl.animateToPage(
          widget.currentIndex,
          duration: AppDuration.normal,
          curve: AppCurves.standard,
        );
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // PageView consults Directionality on its own (axisDirection flips for
    // RTL). Combining that with `reverse: true` would double-flip back to
    // LTR — exactly the bug we hit. So we force the Directionality we want
    // and leave reverse at its default.
    final locale = Localizations.maybeLocaleOf(context);
    final isRTL = locale?.languageCode == 'ar' ||
        Directionality.of(context) == TextDirection.rtl;

    return Directionality(
      textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: PageView(
        controller: _ctrl,
        physics: const PageScrollPhysics()
            .applyTo(const ClampingScrollPhysics()),
        onPageChanged: (i) {
          if (i != widget.currentIndex) widget.onPageChanged(i);
        },
        children: [
          for (final child in widget.children) _KeepAlive(child: child),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _KeepAlive — wraps each tab branch so PageView doesn't dispose offscreen
// pages and lose their state.
// ─────────────────────────────────────────────────────────────────────────────

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
