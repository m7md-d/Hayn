import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Studio Deep — Design Tokens
// ─────────────────────────────────────────────────────────────────────────────
// Pure primitives. No widget reads a raw hex/spacing/curve — everything flows
// through these tokens (and HaynColors for theme-aware values).
//
// Palette: Deep Blue mono (no secondary brand color). The accent earns its
// presence; semantic colors do the rest. Surfaces stay neutral so user media
// is the only chromatic content on screen.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class AppColors {
  // ── Accent — Deep Blue ────────────────────────────────────────────────────
  static const accentLight = Color(0xFF1D4ED8);
  static const accentDark = Color(0xFF4F86F7);
  static const accentHoverLight = Color(0xFF1E40AF);
  static const accentHoverDark = Color(0xFF6190F9);
  static const onAccent = Color(0xFFFFFFFF);

  // ── Background (scaffold) ─────────────────────────────────────────────────
  static const bgLight = Color(0xFFF5F5F7);
  static const bgDark = Color(0xFF000000);

  // ── Surfaces ──────────────────────────────────────────────────────────────
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = Color(0xFF1C1C1E);
  static const surface2Light = Color(0xFFFAFAFB);
  static const surface2Dark = Color(0xFF2C2C2E);
  static const surfaceSunkenLight = Color(0xFFECECEE);
  static const surfaceSunkenDark = Color(0xFF0E0E10);

  // ── Borders / hairlines ───────────────────────────────────────────────────
  static const borderLight = Color(0xFFE2E2E5);
  static const borderDark = Color(0xFF38383A);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const textLight = Color(0xFF1C1C1E);
  static const textDark = Color(0xFFF5F5F7);
  static const text2Light = Color(0xFF6E6E73);
  static const text2Dark = Color(0xFFAEAEB2);
  static const text3Light = Color(0xFFA1A1A6);
  static const text3Dark = Color(0xFF6E6E73);

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const successLight = Color(0xFF2E9E5B);
  static const successDark = Color(0xFF3FBE71);
  static const warningLight = Color(0xFFC77D1A);
  static const warningDark = Color(0xFFE6A23C);
  static const dangerLight = Color(0xFFD6453D);
  static const dangerDark = Color(0xFFF26B63);

  // ── Scrim (dialog/sheet backdrop) ─────────────────────────────────────────
  static const scrimLight = Color(0x66000000); // 40 %
  static const scrimDark = Color(0x99000000);  // 60 %
}

// ─────────────────────────────────────────────────────────────────────────────
// Spacing — 4-pt grid
// ─────────────────────────────────────────────────────────────────────────────
abstract final class AppSpacing {
  // Special: image-grid gap (only place a non-4pt value is allowed).
  static const double gridGap = 2;

  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;
  static const double s16 = 64;

  // Semantic aliases — keep code expressive.
  static const double xs = s1;
  static const double sm = s2;
  static const double md = s4;
  static const double lg = s6;
  static const double xl = s8;
  static const double xxl = s12;
  static const double xxxl = s16;

  // Screen horizontal padding (mobile).
  static const double screen = s4;
}

// ─────────────────────────────────────────────────────────────────────────────
// Corner radii
// ─────────────────────────────────────────────────────────────────────────────
abstract final class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double full = 999;
}

// ─────────────────────────────────────────────────────────────────────────────
// Durations
// ─────────────────────────────────────────────────────────────────────────────
abstract final class AppDuration {
  static const instant = Duration.zero;
  static const micro = Duration(milliseconds: 120);
  static const fast = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 320);
  static const screen = Duration(milliseconds: 350);
  static const sheet = Duration(milliseconds: 400);
  static const hero = Duration(milliseconds: 380);
}

// ─────────────────────────────────────────────────────────────────────────────
// Motion curves — match Material 3 / iOS feel
// ─────────────────────────────────────────────────────────────────────────────
abstract final class AppCurves {
  /// Symmetric ease-in-out, for stateful changes within a component.
  /// Equivalent to Curves.fastOutSlowIn.
  static const standard = Cubic(0.4, 0.0, 0.2, 1.0);

  /// Asymmetric — fast at start, slow at end. For things entering the screen.
  static const decelerate = Cubic(0.0, 0.0, 0.2, 1.0);

  /// Asymmetric — slow at start, fast at end. For things leaving the screen.
  static const accelerate = Cubic(0.4, 0.0, 1.0, 1.0);

  /// Stronger ease-out for emphasized transitions (heroes, sheets).
  static const emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Soft spring-ish feel without using a SpringDescription. iOS-flavored.
  static const spring = Cubic(0.34, 1.56, 0.64, 1.0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Elevation (kept minimal — we prefer surface lift over shadows in dark mode)
// ─────────────────────────────────────────────────────────────────────────────
abstract final class AppElevation {
  static const none = 0.0;

  static List<BoxShadow> shadow1({required bool isDark}) => isDark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x0F000000), // 6 %
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ];

  static List<BoxShadow> shadow2({required bool isDark}) => [
        BoxShadow(
          color: isDark ? const Color(0x66000000) : const Color(0x14000000),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  /// For floating elements (FAB, sheets, dialogs).
  static List<BoxShadow> shadowFloat({required bool isDark}) => [
        BoxShadow(
          color: isDark ? const Color(0x80000000) : const Color(0x1F000000),
          blurRadius: 30,
          offset: const Offset(0, 8),
        ),
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Hairline — sub-pixel divider thickness
// ─────────────────────────────────────────────────────────────────────────────
abstract final class AppHairline {
  static const double thickness = 0.5;
}

// ─────────────────────────────────────────────────────────────────────────────
// Touch target — minimum 44pt (a11y rule)
// ─────────────────────────────────────────────────────────────────────────────
abstract final class AppTouch {
  static const double minimum = 44;
}
