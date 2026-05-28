import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'features/onboarding/providers/onboarding_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-load onboarding flag so the first frame already knows whether to
  // show the welcome flow or jump straight to the app.
  final onboardingDone = await loadOnboardingCompleted();

  runApp(
    ProviderScope(
      overrides: [
        onboardingCompletedProvider.overrideWith(
          () => OnboardingNotifier(initial: onboardingDone),
        ),
      ],
      child: const HaynApp(),
    ),
  );
}
