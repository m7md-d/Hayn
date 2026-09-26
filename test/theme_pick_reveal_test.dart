import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/app/providers/theme_provider.dart';
import 'package:hayn/app/widgets/smooth_switch.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A theme pick must show the new selection before the reveal freezes the
// screen, without delaying the switch: the choice paints in the current look
// for exactly one frame, and the new theme starts on the very next one.
void main() {
  late WidgetRef ref;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      child: Consumer(builder: (context, r, _) {
        ref = r;
        // Same wiring as HaynApp.
        final preferred = r.watch(themeProvider);
        return MaterialApp(
          themeMode: r.watch(appliedThemeProvider) ?? preferred,
          theme: ThemeData(brightness: Brightness.light),
          darkTheme: ThemeData(brightness: Brightness.dark),
          builder: (_, child) => SmoothSwitch(child: child!),
          home: Builder(
            builder: (c) => Text(
              '${ref.watch(themeProvider).name} on ${Theme.of(c).brightness.name}',
            ),
          ),
        );
      }),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() => SharedPreferences.setMockInitialValues({'theme_mode': 'light'}));

  testWidgets('the selection paints in the current look for one frame only',
      (tester) async {
    await pumpApp(tester);
    expect(find.text('light on light'), findsOneWidget);

    unawaited(ref.read(themeProvider.notifier).setTheme(ThemeMode.dark));
    await tester.pump();
    // This frame is the one frozen for the reveal: new choice, old look.
    expect(find.text('dark on light'), findsOneWidget);
    // Already released — the new theme is applied from the next frame on.
    expect(ref.read(appliedThemeProvider), isNull);

    await tester.pumpAndSettle();
    expect(find.text('dark on dark'), findsOneWidget);
  });

  testWidgets('picks within one frame keep the on-screen look',
      (tester) async {
    await pumpApp(tester);

    unawaited(ref.read(themeProvider.notifier).setTheme(ThemeMode.dark));
    unawaited(ref.read(themeProvider.notifier).setTheme(ThemeMode.system));
    expect(ref.read(appliedThemeProvider), ThemeMode.light);

    await tester.pump();
    expect(find.text('system on light'), findsOneWidget);
    expect(ref.read(appliedThemeProvider), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('re-picking the current mode does not pin the theme',
      (tester) async {
    await pumpApp(tester);
    await ref.read(themeProvider.notifier).setTheme(ThemeMode.light);
    expect(ref.read(appliedThemeProvider), isNull);
  });
}
