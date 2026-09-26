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

  // True while a tab-tap animateToPage is in flight. The sweep crosses every
  // page in between (Settings → Tools → Library) and PageView reports each
  // one; forwarding those would switch the branch mid-sweep and bounce the
  // nav bar through the middle tab. A drag interrupts the animation, which
  // completes its future and hands reporting back to the user.
  bool _jumping = false;
  int _jumpToken = 0;

  @override
  void didUpdateWidget(SwipeableTabs old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      // External change (tab tap or deep link) — settle PageView to match.
      // Skip if it's already there (user-driven swipe just settled).
      final settled = _ctrl.hasClients ? _ctrl.page?.round() : null;
      if (settled != widget.currentIndex) {
        final token = ++_jumpToken;
        _jumping = true;
        _ctrl
            .animateToPage(
              widget.currentIndex,
              duration: AppDuration.normal,
              curve: AppCurves.standard,
            )
            .whenComplete(() {
          // A newer jump may have superseded this one; it owns the flag.
          if (token == _jumpToken) _jumping = false;
        });
      }
    }
  }

  // After the pager comes to rest, make sure the shell agrees with the page on
  // screen. Covers a drag that interrupted a jump and settled on a page whose
  // report was muted during the sweep.
  bool _onScrollEnd(ScrollEndNotification n) {
    if (n.depth != 0 || _jumping || !_ctrl.hasClients) return false;
    final page = _ctrl.page?.round();
    if (page != null && page != widget.currentIndex) widget.onPageChanged(page);
    return false;
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
      child: NotificationListener<ScrollEndNotification>(
        onNotification: _onScrollEnd,
        child: PageView(
          controller: _ctrl,
          physics: const PageScrollPhysics()
              .applyTo(const ClampingScrollPhysics()),
          onPageChanged: (i) {
            if (!_jumping && i != widget.currentIndex) widget.onPageChanged(i);
          },
          children: [
            for (final child in widget.children) _KeepAlive(child: child),
          ],
        ),
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
