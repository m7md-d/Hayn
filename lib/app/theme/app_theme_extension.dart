import 'package:flutter/material.dart';
import 'design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HaynColors — theme-aware tokens not covered by Material's ColorScheme.
// Resolved through Theme.of(context).extension<HaynColors>()!
// Convenience: context.hc.<token>
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class HaynColors extends ThemeExtension<HaynColors> {
  const HaynColors({
    required this.surface,
    required this.surface2,
    required this.surfaceSunken,
    required this.border,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.onAccent,
    required this.successColor,
    required this.successSoft,
    required this.warningColor,
    required this.warningSoft,
    required this.dangerColor,
    required this.dangerSoft,
    required this.scrim,
  });

  // ── Surfaces ──────────────────────────────────────────────────────────────
  final Color surface;
  final Color surface2;
  final Color surfaceSunken;
  final Color border;

  // ── Text (secondary / tertiary) ───────────────────────────────────────────
  // Primary text comes from ColorScheme.onSurface to stay Material-idiomatic.
  final Color text2;
  final Color text3;

  // ── Accent (Deep Blue) ────────────────────────────────────────────────────
  final Color accent;
  final Color accentHover;
  final Color accentSoft;
  final Color onAccent;

  // ── Semantic ──────────────────────────────────────────────────────────────
  final Color successColor;
  final Color successSoft;
  final Color warningColor;
  final Color warningSoft;
  final Color dangerColor;
  final Color dangerSoft;

  // ── Misc ──────────────────────────────────────────────────────────────────
  final Color scrim;

  // ── Light theme ───────────────────────────────────────────────────────────
  static const light = HaynColors(
    surface: AppColors.surfaceLight,
    surface2: AppColors.surface2Light,
    surfaceSunken: AppColors.surfaceSunkenLight,
    border: AppColors.borderLight,
    text2: AppColors.text2Light,
    text3: AppColors.text3Light,
    accent: AppColors.accentLight,
    accentHover: AppColors.accentHoverLight,
    accentSoft: Color(0x1F1D4ED8), // accent @ 12 %
    onAccent: AppColors.onAccent,
    successColor: AppColors.successLight,
    successSoft: Color(0x1F2E9E5B),
    warningColor: AppColors.warningLight,
    warningSoft: Color(0x1FC77D1A),
    dangerColor: AppColors.dangerLight,
    dangerSoft: Color(0x1FD6453D),
    scrim: AppColors.scrimLight,
  );

  // ── Dark theme ────────────────────────────────────────────────────────────
  static const dark = HaynColors(
    surface: AppColors.surfaceDark,
    surface2: AppColors.surface2Dark,
    surfaceSunken: AppColors.surfaceSunkenDark,
    border: AppColors.borderDark,
    text2: AppColors.text2Dark,
    text3: AppColors.text3Dark,
    accent: AppColors.accentDark,
    accentHover: AppColors.accentHoverDark,
    accentSoft: Color(0x2E4F86F7), // accent @ 18 %
    onAccent: AppColors.onAccent,
    successColor: AppColors.successDark,
    successSoft: Color(0x2E3FBE71),
    warningColor: AppColors.warningDark,
    warningSoft: Color(0x2EE6A23C),
    dangerColor: AppColors.dangerDark,
    dangerSoft: Color(0x2EF26B63),
    scrim: AppColors.scrimDark,
  );

  @override
  HaynColors copyWith({
    Color? surface,
    Color? surface2,
    Color? surfaceSunken,
    Color? border,
    Color? text2,
    Color? text3,
    Color? accent,
    Color? accentHover,
    Color? accentSoft,
    Color? onAccent,
    Color? successColor,
    Color? successSoft,
    Color? warningColor,
    Color? warningSoft,
    Color? dangerColor,
    Color? dangerSoft,
    Color? scrim,
  }) {
    return HaynColors(
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      border: border ?? this.border,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccent: onAccent ?? this.onAccent,
      successColor: successColor ?? this.successColor,
      successSoft: successSoft ?? this.successSoft,
      warningColor: warningColor ?? this.warningColor,
      warningSoft: warningSoft ?? this.warningSoft,
      dangerColor: dangerColor ?? this.dangerColor,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  HaynColors lerp(HaynColors? other, double t) {
    if (other is! HaynColors) return this;
    return HaynColors(
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      border: Color.lerp(border, other.border, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      successColor: Color.lerp(successColor, other.successColor, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warningColor: Color.lerp(warningColor, other.warningColor, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      dangerColor: Color.lerp(dangerColor, other.dangerColor, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

// Usage: context.hc.accent
extension HaynColorsX on BuildContext {
  HaynColors get hc => Theme.of(this).extension<HaynColors>()!;
}
