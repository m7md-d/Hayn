import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/capabilities/format_capabilities.dart';
import 'features/image_ops/data/native_image_encoder.dart';
import 'features/onboarding/providers/onboarding_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-load onboarding flag so the first frame already knows whether to
  // show the welcome flow or jump straight to the app.
  final onboardingDone = await loadOnboardingCompleted();
  // Whether HEIC can be 10-bit here, for the bit-depth picker (IMG-23).
  if (NativeImageEncoder.android) {
    FormatCapabilities.androidHeicTenBit =
        await NativeImageEncoder.heicTenBit();
  }

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
