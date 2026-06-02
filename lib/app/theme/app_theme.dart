import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_theme_extension.dart';
import 'design_tokens.dart';

/// Bundled font family (assets/fonts, declared in pubspec). The app is
/// offline-only (CLAUDE.md §2), so fonts ship in-app — never fetched at runtime.
const String kFontFamily = 'IBMPlexSansArabic';

// ─────────────────────────────────────────────────────────────────────────────
// App-wide ThemeData factories. Two themes only (light/dark), built from the
// same Studio Deep token set. Every widget reads from the theme — no hex,
// spacing, or radius hard-coded anywhere downstream.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final ext = isDark ? HaynColors.dark : HaynColors.light;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final secondary = isDark ? AppColors.text2Dark : AppColors.text2Light;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: ext.accent,
      onPrimary: ext.onAccent,
      secondary: ext.accent,
      onSecondary: ext.onAccent,
      error: ext.dangerColor,
      onError: Colors.white,
      surface: ext.surface,
      onSurface: textColor,
      surfaceContainerHighest: ext.surface2,
      outline: ext.border,
      outlineVariant: ext.border,
      scrim: ext.scrim,
    );

    final textTheme = _textTheme(textColor, secondary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: [ext],
      scaffoldBackgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      canvasColor: ext.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      textTheme: textTheme,
      primaryTextTheme: textTheme,

      // ── AppBar — large-title Apple style, hairline on scroll ────────────
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
        foregroundColor: textColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: ext.border,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleSpacing: AppSpacing.md,
        toolbarHeight: 52,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: ext.accent, size: 24),
        actionsIconTheme: IconThemeData(color: ext.accent, size: 24),
      ),

      // ── Cards ───────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: ext.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),

      // ── Dividers (hairlines) ────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: ext.border,
        thickness: AppHairline.thickness,
        space: AppHairline.thickness,
      ),

      // ── Buttons ─────────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ext.accent,
          foregroundColor: ext.onAccent,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ext.accent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s2,
          ),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textColor,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: ext.border),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textColor,
          padding: const EdgeInsets.all(AppSpacing.s2),
          minimumSize: const Size(AppTouch.minimum, AppTouch.minimum),
        ),
      ),

      // ── List tiles ──────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.s1,
        ),
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(color: secondary),
        iconColor: secondary,
        minVerticalPadding: AppSpacing.s2,
      ),

      // ── Bottom nav (NavigationBar) ──────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ext.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: ext.accentSoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateTextStyle.resolveWith((states) {
          final on = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: kFontFamily,
            fontSize: 10,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? ext.accent : ext.text3,
            height: 1.2,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final on = states.contains(WidgetState.selected);
          return IconThemeData(
            color: on ? ext.accent : ext.text3,
            size: 22,
          );
        }),
      ),

      // ── Bottom sheet ────────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: ext.surface,
        modalBackgroundColor: ext.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: ext.border,
        dragHandleSize: const Size(40, 5),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),

      // ── Dialogs ─────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: ext.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: secondary),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.s2,
        ),
      ),

      // ── Snack bar ───────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.surface2Dark : AppColors.textLight,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isDark ? AppColors.textDark : Colors.white,
        ),
        actionTextColor: ext.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        insetPadding: const EdgeInsets.all(AppSpacing.md),
      ),

      // ── Segmented button (used sparingly; we have our own pill control) ─
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: ext.surface,
          selectedForegroundColor: textColor,
          foregroundColor: secondary,
          backgroundColor: ext.surfaceSunken,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // ── Sliders ─────────────────────────────────────────────────────────
      sliderTheme: SliderThemeData(
        activeTrackColor: ext.accent,
        inactiveTrackColor: ext.surfaceSunken,
        thumbColor: ext.surface,
        trackHeight: 4,
        overlayShape: const RoundElevatedSliderThumbShape(),
      ),

      // ── Switches ────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return ext.accent;
          return ext.surfaceSunken;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),

      // ── Progress indicators ─────────────────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: ext.accent,
        linearTrackColor: ext.surfaceSunken,
        circularTrackColor: Colors.transparent,
      ),

      // ── FAB ─────────────────────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: ext.accent,
        foregroundColor: ext.onAccent,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 4,
        highlightElevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),

      // ── Chips ───────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: ext.surfaceSunken,
        selectedColor: ext.accentSoft,
        side: BorderSide.none,
        labelStyle: textTheme.labelLarge?.copyWith(color: textColor),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(color: ext.accent),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
      ),

      // ── Inputs ──────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ext.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.s3,
        ),
        hintStyle: textTheme.bodyLarge?.copyWith(color: ext.text3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: ext.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: ext.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: ext.accent, width: 1.5),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Type system — iOS-style scale rendered through IBM Plex Sans Arabic
  // (single family for both scripts; bundling for production happens later).
  //
  // Material slot ↔ iOS slot mapping:
  //   displayLarge   34/41 w700  ← iOS display
  //   displayMedium  28/34 w700  ← iOS title-1
  //   displaySmall   22/28 w600  ← iOS title-2
  //   headlineLarge  20/25 w600  ← iOS title-3
  //   titleLarge     17/22 w600  ← AppBar title, card title
  //   titleMedium    15/20 w600
  //   titleSmall     13/18 w600
  //   bodyLarge      17/24 w400  ← iOS body
  //   bodyMedium     15/22 w400  ← iOS subhead
  //   bodySmall      13/18 w400  ← iOS footnote
  //   labelLarge     15/20 w500  ← button text
  //   labelMedium    13/18 w500
  //   labelSmall     12/16 w500  ← iOS caption / badge
  // ───────────────────────────────────────────────────────────────────────────
  static TextTheme _textTheme(Color text, Color secondary) {
    TextStyle style(double size, double height, FontWeight weight, {Color? color}) {
      return TextStyle(
        fontFamily: kFontFamily,
        fontSize: size,
        height: height / size,
        fontWeight: weight,
        letterSpacing: 0,
        color: color ?? text,
      );
    }

    return TextTheme(
      displayLarge: style(34, 41, FontWeight.w700),
      displayMedium: style(28, 34, FontWeight.w700),
      displaySmall: style(22, 28, FontWeight.w600),
      headlineLarge: style(20, 25, FontWeight.w600),
      headlineMedium: style(18, 24, FontWeight.w600),
      headlineSmall: style(17, 22, FontWeight.w600),
      titleLarge: style(17, 22, FontWeight.w600),
      titleMedium: style(15, 20, FontWeight.w600),
      titleSmall: style(13, 18, FontWeight.w600),
      bodyLarge: style(17, 24, FontWeight.w400),
      bodyMedium: style(15, 22, FontWeight.w400),
      bodySmall: style(13, 18, FontWeight.w400, color: secondary),
      labelLarge: style(15, 20, FontWeight.w500),
      labelMedium: style(13, 18, FontWeight.w500),
      labelSmall: style(12, 16, FontWeight.w500, color: secondary),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom slider thumb — small elevated dot, iOS-flavored.
// ─────────────────────────────────────────────────────────────────────────────
class RoundElevatedSliderThumbShape extends SliderComponentShape {
  const RoundElevatedSliderThumbShape({this.radius = 10});
  final double radius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final paintShadow = Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(center.translate(0, 1), radius, paintShadow);

    final paintFill = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius, paintFill);

    final paintRing = Paint()
      ..color = sliderTheme.activeTrackColor!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius - 1, paintRing);
  }
}
