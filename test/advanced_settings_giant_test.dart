import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/app/l10n/app_localizations.dart';
import 'package:hayn/app/theme/app_theme.dart';
import 'package:hayn/core/capabilities/format_capabilities.dart';
import 'package:hayn/features/image_ops/domain/image_format_policy.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';
import 'package:hayn/shared/widgets/advanced_settings_card.dart';

// RUN-01 (user decision 2026-10-02): a giant image's format picker lists
// Auto, JPEG and HEIC only, with no warning or explanation for the rest.
const _android = FormatCapabilities(
  supportsHeic: false,
  supportsHeif: true,
  supportsAvifHardware: false,
  supportsWebp: true,
);

void main() {
  Future<void> openPicker(WidgetTester tester, {required bool giant}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [formatCapabilitiesProvider.overrideWithValue(_android)],
        child: MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('en'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: HaynAdvancedSettingsCard(
              format: DefaultFormat.auto,
              quality: 80,
              keepMetadata: true,
              onFormatChanged: (_) {},
              onQualityChanged: (_) {},
              onKeepMetaChanged: (_) {},
              offered: (f) => ImageFormatPolicy.offers(
                f,
                giant: giant,
                hasAlpha: false,
                caps: _android,
              ),
              autoResolved: giant ? DefaultFormat.heic : null,
            ),
          ),
        ),
      ),
    );
    // The format chip opens the picker; it first asks for the AV1 hardware.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('hayn/avif'),
          (_) async => false,
        );
    await tester.tap(find.textContaining('Auto ·'));
    await tester.pumpAndSettle();
  }

  testWidgets('a giant image is offered JPEG and HEIF only', (tester) async {
    await openPicker(tester, giant: true);
    expect(find.text('JPEG'), findsOneWidget);
    expect(find.text('HEIF'), findsOneWidget);
    for (final hidden in ['WebP', 'AVIF', 'PNG']) {
      expect(find.text(hidden), findsNothing, reason: hidden);
    }
  });

  testWidgets('a normal image is offered every format', (tester) async {
    await openPicker(tester, giant: false);
    for (final shown in ['JPEG', 'HEIF', 'WebP', 'AVIF', 'PNG']) {
      expect(find.text(shown), findsOneWidget, reason: shown);
    }
  });
}
