import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeKey = 'theme_mode';

class ThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadFromPrefs();
    return ThemeMode.system;
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_kThemeKey);
    if (value != null) {
      state = _fromString(value);
    }
  }

  /// A user pick. The choice is live at once (pickers show the new selection),
  /// and the app keeps its current look for the one frame that paints it;
  /// SmoothSwitch freezes that frame for the reveal and releases
  /// [appliedThemeProvider].
  Future<void> setTheme(ThemeMode mode) async {
    if (mode == state) return;
    ref.read(appliedThemeProvider.notifier).hold(state);
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeKey, _toString(mode));
  }

  static ThemeMode _fromString(String v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _toString(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(
  ThemeNotifier.new,
);

/// The mode MaterialApp renders when it differs from [themeProvider]: the
/// previous look, pinned between a user pick and its reveal. null = follow
/// the user's choice.
class AppliedThemeNotifier extends Notifier<ThemeMode?> {
  @override
  ThemeMode? build() => null;

  /// Pin [current] unless a pick is already pending — rapid picks keep the
  /// look that is actually on screen.
  void hold(ThemeMode current) => state ??= current;

  void release() => state = null;
}

final appliedThemeProvider =
    NotifierProvider<AppliedThemeNotifier, ThemeMode?>(
  AppliedThemeNotifier.new,
);
