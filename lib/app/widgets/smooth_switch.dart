import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import 'theme_reveal_profiles.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SmoothSwitch — wraps the routed content and plays an animated reveal when
// the user changes theme or locale.
//
// Theme  → picks one of four ThemeRevealProfile clips (liquid bloom / water
//          fill / curtain drop / drop ripple) at random. Each lasts ~1000ms,
//          with wave perturbation that decays as the reveal completes.
//
// Locale → soft fade with a slight scale-up so the new layout "settles in"
//          rather than snapping. The duration is generous (~700ms) and
//          stays on-curve until the very end to avoid the brief-freeze feel.
//
// Uses RepaintBoundary.toImageSync (Flutter 3.10+) so the snapshot is
// captured in the same frame as the state change.
// ─────────────────────────────────────────────────────────────────────────────

class SmoothSwitch extends ConsumerStatefulWidget {
  const SmoothSwitch({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<SmoothSwitch> createState() => _SmoothSwitchState();
}

enum _RevealKind { theme, locale }

class _SmoothSwitchState extends ConsumerState<SmoothSwitch>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();
  late final AnimationController _ctrl;
  final _rng = math.Random();

  ui.Image? _snapshot;
  _RevealKind _kind = _RevealKind.theme;
  ThemeRevealProfile _profile = pickRevealProfile();
  // Eagerly initialised so locale reveals (which don't pick a fresh seed)
  // never hit a LateInitializationError when the overlay reads it.
  math.Random _profileSeed = math.Random();

  static const _localeDuration = Duration(milliseconds: 700);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _localeDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          if (mounted) {
            setState(() {
              _snapshot?.dispose();
              _snapshot = null;
            });
            _ctrl.value = 0;
          }
        }
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  void _captureAndReveal(_RevealKind kind) {
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    try {
      // Capture at the device's actual pixel ratio so the snapshot stays
      // sharp during the reveal — at 1× the image looked noticeably soft
      // on high-DPI screens. The cost is roughly (ratio²) extra pixels;
      // toImageSync handles it on the raster thread, so the UI thread
      // doesn't stall noticeably on modern phones.
      final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
      final image = boundary.toImageSync(pixelRatio: dpr);
      _snapshot?.dispose();
      _snapshot = image;
      _kind = kind;
      if (kind == _RevealKind.theme) {
        _profile = pickRevealProfile(_rng);
        _profileSeed = math.Random(_rng.nextInt(1 << 31));
        _ctrl.duration = _profile.duration;
      } else {
        _ctrl.duration = _localeDuration;
      }
      // Keep the controller at 0 while the new theme rebuilds. We start the
      // animation in a post-frame callback so the very first visible frame
      // lines up with controller.value == 0 — no "started from the middle".
      _ctrl.value = 0;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ctrl.forward(from: 0);
      });
    } catch (_) {
      // Boundary not ready — skip the ceremony.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ThemeMode>(themeProvider, (prev, next) {
      if (prev != next) _captureAndReveal(_RevealKind.theme);
    });
    ref.listen<Locale?>(localeProvider, (prev, next) {
      if (prev != next) _captureAndReveal(_RevealKind.locale);
    });

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(key: _boundaryKey, child: widget.child),
        if (_snapshot != null)
          _RevealOverlay(
            snapshot: _snapshot!,
            controller: _ctrl,
            kind: _kind,
            profile: _profile,
            seed: _profileSeed,
          ),
      ],
    );
  }
}

class _RevealOverlay extends StatelessWidget {
  const _RevealOverlay({
    required this.snapshot,
    required this.controller,
    required this.kind,
    required this.profile,
    required this.seed,
  });

  final ui.Image snapshot;
  final AnimationController controller;
  final _RevealKind kind;
  final ThemeRevealProfile profile;
  final math.Random seed;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (ctx, _) {
          final size = MediaQuery.sizeOf(ctx);
          switch (kind) {
            case _RevealKind.theme:
              final t = profile.curve.transform(controller.value);
              final revealed = profile.revealedPath(t, size, seed);
              return CustomPaint(
                size: size,
                painter: SnapshotMaskPainter(
                  snapshot: snapshot,
                  revealedPath: revealed,
                ),
              );
            case _RevealKind.locale:
              // Soft, slightly slower fade + gentle scale-up so the new
              // layout looks like it's settling into place rather than
              // popping in.
              final raw = controller.value;
              final t = const Cubic(0.4, 0, 0.2, 1).transform(raw);
              return Opacity(
                opacity: 1 - t,
                child: Transform.scale(
                  scale: 1 + t * 0.04,
                  filterQuality: FilterQuality.medium,
                  child: SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: snapshot.width.toDouble(),
                        height: snapshot.height.toDouble(),
                        child: RawImage(image: snapshot, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                ),
              );
          }
        },
      ),
    );
  }
}
