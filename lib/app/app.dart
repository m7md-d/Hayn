import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/settings/providers/preferences_providers.dart';
import '../features/trash/data/trash_repository.dart';
import 'l10n/app_localizations.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/design_tokens.dart';
import 'widgets/smooth_switch.dart';

class HaynApp extends ConsumerStatefulWidget {
  const HaynApp({super.key});

  @override
  ConsumerState<HaynApp> createState() => _HaynAppState();
}

class _HaynAppState extends ConsumerState<HaynApp> {
  @override
  void initState() {
    super.initState();
    // Trash retention sweep, once at launch — drop backups past the window.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref
          .read(trashRepositoryProvider)
          .purgeExpired(ref.read(trashRetentionProvider)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Hayn',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Stretch Material's built-in theme tween so colour swaps feel smooth
      // instead of snapping. SmoothSwitch handles the locale/theme dim.
      themeAnimationDuration: AppDuration.normal,
      themeAnimationCurve: AppCurves.standard,
      locale: locale ?? const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) => SmoothSwitch(child: child!),
    );
  }
}
