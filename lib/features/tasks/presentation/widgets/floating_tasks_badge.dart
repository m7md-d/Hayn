import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../core/isolates/task_runner.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FloatingTasksBadge — a draggable bubble that surfaces task activity on top
// of the current screen. The user can drag it freely; on release it snaps to
// the nearest vertical edge of the screen. When dragged past the edge it
// "hides" (only a thin sliver remains, tap to bring back).
//
// Three colour states reflect the queue:
//   yellow → at least one task is pending/running
//   red    → at least one task failed (and nothing is currently running)
//   green  → every task is completed (auto-dismiss once the user taps it)
//
// The badge knows how to dismiss its green state — once the user opens the
// tasks list while green, the bubble disappears until the next task starts.
//
// The state (position, hidden, green-acked) is held in a per-session provider
// so the badge keeps its place as the user moves between tabs.
// ─────────────────────────────────────────────────────────────────────────────

class FloatingBadgeState {
  const FloatingBadgeState({
    required this.position,
    required this.hidden,
    required this.greenAcked,
  });

  /// Top-left of the badge in screen coordinates. Null = use default
  /// (bottom-end corner, computed on first build).
  final Offset? position;

  /// True if the user has parked the badge past a screen edge.
  final bool hidden;

  /// True if the user has already viewed the all-done state; the green
  /// version should not reappear until a new task starts.
  final bool greenAcked;

  FloatingBadgeState copyWith({
    Offset? position,
    bool? hidden,
    bool? greenAcked,
  }) =>
      FloatingBadgeState(
        position: position ?? this.position,
        hidden: hidden ?? this.hidden,
        greenAcked: greenAcked ?? this.greenAcked,
      );

  static const initial = FloatingBadgeState(
    position: null,
    hidden: false,
    // Default false so that the first time the queue completes, the user
    // sees the green confirmation. Each new task re-arms this via the
    // listener inside FloatingTasksBadge.
    greenAcked: false,
  );
}

class FloatingBadgeController extends Notifier<FloatingBadgeState> {
  @override
  FloatingBadgeState build() => FloatingBadgeState.initial;

  void setPosition(Offset offset) =>
      state = state.copyWith(position: offset);
  void setHidden(bool hidden) => state = state.copyWith(hidden: hidden);
  void ackGreen() => state = state.copyWith(greenAcked: true);
  void unackGreen() => state = state.copyWith(greenAcked: false);
}

final floatingBadgeProvider =
    NotifierProvider<FloatingBadgeController, FloatingBadgeState>(
  FloatingBadgeController.new,
);

enum _BadgeKind { hidden, running, failed, done }

class FloatingTasksBadge extends ConsumerStatefulWidget {
  const FloatingTasksBadge({super.key});

  static const double size = 56;
  static const double edgePadding = 12;

  @override
  ConsumerState<FloatingTasksBadge> createState() => _FloatingTasksBadgeState();
}

class _FloatingTasksBadgeState extends ConsumerState<FloatingTasksBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _snapCtrl;
  Offset? _snapFrom;
  Offset? _snapTo;
  Offset? _override; // overrides provider position during snap-back animation

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(vsync: this, duration: AppDuration.normal)
      ..addListener(_onSnapTick);
  }

  void _onSnapTick() {
    if (_snapFrom == null || _snapTo == null) return;
    final t = AppCurves.emphasized.transform(_snapCtrl.value);
    setState(() {
      _override = Offset.lerp(_snapFrom, _snapTo, t);
    });
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  _BadgeKind _classify(List<TaskState> tasks, bool greenAcked) {
    if (tasks.isEmpty) return _BadgeKind.hidden;
    final hasRunning = tasks
        .any((t) => t.status == TaskStatus.running || t.status == TaskStatus.pending);
    if (hasRunning) return _BadgeKind.running;
    final hasFailed = tasks
        .any((t) => t.status == TaskStatus.failed || t.status == TaskStatus.cancelled);
    if (hasFailed) return _BadgeKind.failed;
    final allDone = tasks.every((t) => t.status == TaskStatus.completed);
    if (allDone && !greenAcked) return _BadgeKind.done;
    return _BadgeKind.hidden;
  }

  int _activeCount(List<TaskState> tasks, _BadgeKind kind) {
    return switch (kind) {
      _BadgeKind.running => tasks
          .where((t) =>
              t.status == TaskStatus.running ||
              t.status == TaskStatus.pending)
          .length,
      _BadgeKind.failed =>
        tasks.where((t) => t.status == TaskStatus.failed).length,
      _BadgeKind.done =>
        tasks.where((t) => t.status == TaskStatus.completed).length,
      _BadgeKind.hidden => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Re-arm the green state whenever a new task is added — the user should
    // see the green confirmation once for each fresh batch they enqueue.
    ref.listen<List<TaskState>>(taskRunnerProvider, (prev, next) {
      final added = (prev?.length ?? 0) < next.length;
      if (added) {
        ref.read(floatingBadgeProvider.notifier).unackGreen();
      }
    });

    final tasks = ref.watch(taskRunnerProvider);
    final badge = ref.watch(floatingBadgeProvider);
    final kind = _classify(tasks, badge.greenAcked);

    if (kind == _BadgeKind.hidden) return const SizedBox.shrink();
    final count = _activeCount(tasks, kind);

    return LayoutBuilder(builder: (context, c) {
      final screen = c.biggest;
      final pos = _override ??
          badge.position ??
          Offset(
            screen.width - FloatingTasksBadge.size - FloatingTasksBadge.edgePadding,
            screen.height -
                FloatingTasksBadge.size -
                FloatingTasksBadge.edgePadding -
                120, // sit comfortably above the bottom nav
          );

      // Clamp into bounds (in case the screen rotated).
      final clamped = _clamp(pos, screen);
      final hiddenSliver = _hiddenSliver(clamped, screen);
      final effective = badge.hidden ? hiddenSliver : clamped;

      return Stack(
        children: [
          Positioned(
            left: effective.dx,
            top: effective.dy,
            child: _BadgeBody(
              kind: kind,
              count: count,
              hidden: badge.hidden,
              onTap: () => _onTap(kind),
              onDragStart: () {
                HapticFeedback.selectionClick();
                _snapCtrl.stop();
                _override = clamped;
                ref.read(floatingBadgeProvider.notifier).setHidden(false);
              },
              onDragUpdate: (d) {
                final next = _clamp(
                  (effective) + d.delta,
                  screen,
                );
                setState(() {
                  _override = next;
                });
                ref.read(floatingBadgeProvider.notifier).setPosition(next);
              },
              onDragEnd: (d) => _onDragEnd(effective, screen, d.velocity),
            ),
          ),
        ],
      );
    });
  }

  Offset _clamp(Offset p, Size screen) {
    final maxX = screen.width - FloatingTasksBadge.size;
    final maxY = screen.height - FloatingTasksBadge.size;
    return Offset(
      p.dx.clamp(-FloatingTasksBadge.size * 0.6, maxX + FloatingTasksBadge.size * 0.6),
      p.dy.clamp(0, maxY),
    );
  }

  Offset _hiddenSliver(Offset p, Size screen) {
    // Park the badge so only ~30% of it pokes back into the screen.
    final atRight = (p.dx + FloatingTasksBadge.size / 2) > screen.width / 2;
    final hiddenX = atRight
        ? screen.width - FloatingTasksBadge.size * 0.3
        : -FloatingTasksBadge.size * 0.7;
    return Offset(hiddenX, p.dy);
  }

  void _onDragEnd(Offset current, Size screen, Velocity velocity) {
    HapticFeedback.lightImpact();
    final centerX = current.dx + FloatingTasksBadge.size / 2;
    final near = (centerX < screen.width / 2);
    // If the user flicked past the edge, park as hidden sliver.
    final pastEdge = current.dx < -FloatingTasksBadge.size * 0.25 ||
        current.dx > screen.width - FloatingTasksBadge.size * 0.75;
    if (pastEdge) {
      ref.read(floatingBadgeProvider.notifier).setHidden(true);
      _snapFrom = current;
      _snapTo = _hiddenSliver(current, screen);
    } else {
      // Snap to the nearest vertical edge with padding.
      final targetX = near
          ? FloatingTasksBadge.edgePadding
          : screen.width -
              FloatingTasksBadge.size -
              FloatingTasksBadge.edgePadding;
      _snapFrom = current;
      _snapTo = Offset(targetX, current.dy);
      ref
          .read(floatingBadgeProvider.notifier)
          .setPosition(Offset(targetX, current.dy));
    }
    _snapCtrl
      ..value = 0
      ..forward().whenComplete(() {
        if (!mounted) return;
        setState(() => _override = null);
      });
  }

  void _onTap(_BadgeKind kind) {
    HapticFeedback.lightImpact();
    final badge = ref.read(floatingBadgeProvider);
    // If parked as a sliver, surface it back to a real position first.
    if (badge.hidden) {
      ref.read(floatingBadgeProvider.notifier).setHidden(false);
      return;
    }
    if (kind == _BadgeKind.done) {
      // User has now seen the all-done state — clear the green badge.
      ref.read(floatingBadgeProvider.notifier).ackGreen();
    }
    context.push('/tasks');
  }
}

class _BadgeBody extends StatelessWidget {
  const _BadgeBody({
    required this.kind,
    required this.count,
    required this.hidden,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final _BadgeKind kind;
  final int count;
  final bool hidden;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final ValueChanged<DragEndDetails> onDragEnd;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final (bg, fg, icon) = switch (kind) {
      _BadgeKind.running => (hc.warningColor, Colors.white, Icons.sync_rounded),
      _BadgeKind.failed => (hc.dangerColor, Colors.white, Icons.error_outline_rounded),
      _BadgeKind.done => (hc.successColor, Colors.white, Icons.check_rounded),
      _BadgeKind.hidden => (hc.surface, hc.text3, Icons.task_alt_rounded),
    };

    final label = count > 99 ? '99+' : '$count';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => onDragStart(),
      onPanUpdate: onDragUpdate,
      onPanEnd: onDragEnd,
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: hidden ? 0.7 : 1.0,
        duration: AppDuration.fast,
        child: Container(
          width: FloatingTasksBadge.size,
          height: FloatingTasksBadge.size,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: bg.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _RunningPulse(active: kind == _BadgeKind.running, color: bg),
              Icon(icon, color: fg, size: 22),
              if (kind != _BadgeKind.done)
                Positioned(
                  right: 4, top: 4,
                  child: _CountBubble(label: label, accent: bg, fg: fg),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBubble extends StatelessWidget {
  const _CountBubble({required this.label, required this.accent, required this.fg});
  final String label;
  final Color accent;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: fg,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: accent, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _RunningPulse extends StatefulWidget {
  const _RunningPulse({required this.active, required this.color});
  final bool active;
  final Color color;

  @override
  State<_RunningPulse> createState() => _RunningPulseState();
}

class _RunningPulseState extends State<_RunningPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.active) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant _RunningPulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.active && _pulse.isAnimating) _pulse.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    // RepaintBoundary isolates the continuously-pulsing circle so the rest
    // of the badge (icon, count) doesn't repaint every frame.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (ctx, _) {
          final t = _pulse.value;
          return Container(
            width: FloatingTasksBadge.size * (1 + t * 0.35),
            height: FloatingTasksBadge.size * (1 + t * 0.35),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: (1 - t) * 0.25),
            ),
          );
        },
      ),
    );
  }
}
