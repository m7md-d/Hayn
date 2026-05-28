import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// onboardingCompletedProvider — true once the user finishes (or skips) the
// first-run flow. Persisted via SharedPreferences.
//
// `main()` reads the stored value first and overrides this provider so the
// initial frame has the correct state (no /onboarding flash on warm starts).
// ─────────────────────────────────────────────────────────────────────────────

const _kKey = 'onboarding_completed';

class OnboardingNotifier extends Notifier<bool> {
  OnboardingNotifier({this.initial = false});
  final bool initial;

  @override
  bool build() => initial;

  Future<void> complete() async {
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKey, true);
  }

  /// Dev/QA helper — wipe the flag so onboarding shows on next launch.
  Future<void> reset() async {
    state = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}

final onboardingCompletedProvider =
    NotifierProvider<OnboardingNotifier, bool>(OnboardingNotifier.new);

/// Read the persisted flag without instantiating Riverpod. Call this in
/// `main()` to seed the provider override.
Future<bool> loadOnboardingCompleted() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kKey) ?? false;
}
