import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme_extension.dart';
import '../theme/design_tokens.dart';
import '../theme/motion.dart';
import '../../features/library/presentation/providers/library_provider.dart';
import '../../features/library/presentation/widgets/selection_toolbar.dart';
import '../../features/tasks/presentation/widgets/floating_tasks_badge.dart';
import '../../shared/widgets/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppShell — outer scaffold + animated bottom navigation. The bottom row
// switches between the standard NavigationBar and the Library
// SelectionToolbar.
//
// Custom transitions:
//   • Tab content slides in from the appropriate side (RTL-aware) on swap.
//   • The bottom NavigationBar's indicator slides smoothly between tabs.
// ─────────────────────────────────────────────────────────────────────────────

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  void _switchTo(int newIndex) {
    if (newIndex == widget.navigationShell.currentIndex) {
      // tapping the active tab again — pop to root of branch.
      widget.navigationShell.goBranch(newIndex, initialLocation: true);
      return;
    }
    HapticFeedback.selectionClick();
    widget.navigationShell.goBranch(newIndex);
    // The PageView (SwipeableTabs) animates itself to match.
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final libraryState = ref.watch(libraryProvider);
    final isSelecting =
        libraryState.isSelecting && widget.navigationShell.currentIndex == 0;

    // Floating tasks badge surfaces on Library (0) and Tools (1). It is the
    // ONLY entry point into the queue now that Tasks is no longer a tab.
    // Hidden on Settings (2) so a focused screen stays distraction-free.
    final currentTab = widget.navigationShell.currentIndex;
    final showBadge = currentTab == 0 || currentTab == 1;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          widget.navigationShell,
          if (showBadge) const Positioned.fill(child: FloatingTasksBadge()),
        ],
      ),
      bottomNavigationBar: AnimatedSwitcher(
        duration: AppDuration.normal,
        switchInCurve: AppCurves.decelerate,
        switchOutCurve: AppCurves.accelerate,
        transitionBuilder: slideUpFadeTransition,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.bottomCenter,
          children: [...previous, if (current != null) current],
        ),
        child: isSelecting
            ? SelectionToolbar(
                key: const ValueKey('selection-bar'),
                selectedAssets: libraryState.selectedAssets,
                onCompress: () {
                  HapticFeedback.lightImpact();
                  context.push(
                    '/compress',
                    extra: libraryState.selectedIds.toList(),
                  );
                },
                onStripMetadata: () async {
                  HapticFeedback.lightImpact();
                  final ok = await showHaynDestructiveConfirm(
                    context: context,
                    title: l.toolStripMetadata,
                    message: l.toolStripDesc,
                    confirmLabel: l.commonContinue,
                    cancelLabel: l.commonCancel,
                    icon: Icons.auto_fix_high_rounded,
                    reassurance: l.settingsPrivacy,
                  );
                  if (ok && context.mounted) {
                    HaynSnack.success(context, l.taskStatusCompleted);
                    ref.read(libraryProvider.notifier).clearSelection();
                  }
                },
                onSurgical: () {
                  HapticFeedback.lightImpact();
                  final ids = libraryState.selectedIds.toList();
                  if (ids.isEmpty) return;
                  // Single → per-item arena. Batch → dedicated queue screen.
                  if (ids.length == 1) {
                    context.push('/surgical/${ids.first}');
                  } else {
                    context.push('/surgical/batch', extra: ids);
                  }
                },
                onMore: () {},
              )
            : _HaynNavBar(
                key: const ValueKey('nav-bar'),
                currentIndex: widget.navigationShell.currentIndex,
                onSelect: _switchTo,
                destinations: [
                  _NavDest(
                    icon: Icons.photo_library_outlined,
                    activeIcon: Icons.photo_library_rounded,
                    label: l.tabLibrary,
                  ),
                  _NavDest(
                    icon: Icons.construction_outlined,
                    activeIcon: Icons.construction_rounded,
                    label: l.tabTools,
                  ),
                  _NavDest(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings_rounded,
                    label: l.tabSettings,
                  ),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HaynNavBar — custom navigation bar with a sliding indicator pill that
// glides between tabs (Material's NavigationBar fades in/out, which feels
// abrupt). Same look-and-feel otherwise: icon + label + accent-soft pill.
// ─────────────────────────────────────────────────────────────────────────────

class _NavDest {
  const _NavDest({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _HaynNavBar extends StatelessWidget {
  const _HaynNavBar({
    required this.currentIndex,
    required this.onSelect,
    required this.destinations,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<_NavDest> destinations;

  // Indicator wraps the whole tab content (icon + label) so the active tab
  // looks like a single rounded chip, not a circle behind just the icon.
  static const _indicatorWidth = 64.0;
  static const _indicatorHeight = 50.0;
  static const _navHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        border: Border(
          top: BorderSide(color: hc.border, width: AppHairline.thickness),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _navHeight,
          child: LayoutBuilder(builder: (ctx, c) {
            final tabWidth = c.maxWidth / destinations.length;
            final indicatorStart =
                currentIndex * tabWidth + (tabWidth - _indicatorWidth) / 2;
            const indicatorTop = (_navHeight - _indicatorHeight) / 2;
            return Stack(
              children: [
                // Sliding indicator pill — large enough to wrap icon + label.
                AnimatedPositionedDirectional(
                  duration: AppDuration.normal,
                  curve: AppCurves.emphasized,
                  start: indicatorStart,
                  top: indicatorTop,
                  width: _indicatorWidth,
                  height: _indicatorHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: hc.accentSoft,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
                // Tab buttons
                Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Expanded(
                        child: _NavTab(
                          dest: destinations[i],
                          selected: i == currentIndex,
                          onTap: () => onSelect(i),
                          theme: theme,
                          hc: hc,
                        ),
                      ),
                  ],
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.dest,
    required this.selected,
    required this.onTap,
    required this.theme,
    required this.hc,
  });

  final _NavDest dest;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;
  final HaynColors hc;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: AppDuration.fast,
            switchInCurve: AppCurves.decelerate,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1).animate(anim),
                child: child,
              ),
            ),
            child: Icon(
              selected ? dest.activeIcon : dest.icon,
              key: ValueKey(selected),
              size: 22,
              color: selected ? hc.accent : hc.text3,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: AppDuration.fast,
            curve: AppCurves.standard,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? hc.accent : hc.text3,
              height: 1.2,
            ),
            child: Text(dest.label),
          ),
        ],
      ),
    );
  }
}
