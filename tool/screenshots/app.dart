// Entry point for tool/screenshots/generate.sh: the real app, installed in a
// throwaway simulator whose library holds only tool/screenshots/photos/. The
// script can't tap the app, so the app steps itself through the README shots
// and hands over at each one, once per appearance: when the screen has
// settled in the simulator's current appearance it writes
// <Documents>/screenshots/<shot>-<light|dark>.ready; the script captures,
// switches the appearance and answers with the matching .done file.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hayn/app/app.dart';
import 'package:hayn/app/providers/locale_provider.dart';
import 'package:hayn/app/router/app_router.dart';
import 'package:hayn/features/library/presentation/providers/library_provider.dart';
import 'package:hayn/features/library/presentation/providers/thumbnail_cache.dart';
import 'package:hayn/features/onboarding/providers/onboarding_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart' show AssetType;

/// Grid cells visible on the first screen — the thumbnails a shot must have.
const _visibleCells = 18;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer(overrides: [
    onboardingCompletedProvider
        .overrideWith(() => OnboardingNotifier(initial: true)),
    localeProvider.overrideWith(_EnglishLocale.new),
  ]);
  runApp(UncontrolledProviderScope(container: container, child: const HaynApp()));

  final documents = await getApplicationDocumentsDirectory();
  final handoff = Directory('${documents.path}/screenshots')
    ..createSync(recursive: true);
  final library = container.read(libraryProvider.notifier);

  await _libraryLoaded(container);
  await _shot(handoff, 'library');

  final onScreen = container.read(libraryProvider).entries.take(_visibleCells);
  for (final entry in onScreen.where((e) => e.type == AssetType.image).take(4)) {
    library.toggleSelection(entry.id, entry.type);
  }
  await _shot(handoff, 'selection');
  library.clearSelection();

  container.read(appRouterProvider).go('/settings');
  await _shot(handoff, 'settings');

  File('${handoff.path}/finished').writeAsStringSync('');
}

class _EnglishLocale extends LocaleNotifier {
  @override
  Locale? build() => const Locale('en');
}

/// Waits for the library to finish loading and for the first screen's
/// thumbnails to be decoded, so no shot catches a placeholder. The library
/// loads twice — straight from Photos, then from its own index once that is
/// built, possibly in a different order — so it must also hold still.
Future<void> _libraryLoaded(ProviderContainer container) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  List<String>? lastOrder;
  var stableChecks = 0;
  while (DateTime.now().isBefore(deadline)) {
    final state = container.read(libraryProvider);
    final order = [for (final e in state.entries) e.id];
    final ready = !state.isLoading &&
        order.isNotEmpty &&
        order.take(_visibleCells).every((id) => ThumbnailCache.get(id) != null);
    stableChecks = ready && listEquals(order, lastOrder) ? stableChecks + 1 : 0;
    if (stableChecks >= 8) return; // two seconds unchanged
    lastOrder = order;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError('The library did not settle in the simulator.');
}

/// Hands the screen over in light, then dark. The script flips the
/// simulator's appearance between the two; each capture waits until the app
/// has actually taken it on and finished animating to it.
Future<void> _shot(Directory handoff, String name) async {
  for (final mode in [Brightness.light, Brightness.dark]) {
    await _appearance(mode);
    await _settled();
    await _handOver(handoff, '$name-${mode.name}');
  }
}

Future<void> _appearance(Brightness mode) async {
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final deadline = DateTime.now().add(const Duration(minutes: 1));
  while (dispatcher.platformBrightness != mode) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('The simulator never switched to ${mode.name}.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Waits until nothing is animating and no frame is pending — the running
/// app's pumpAndSettle. Fixed delays don't hold up: a simulator only runs
/// debug builds, whose speed varies from frame to frame.
Future<void> _settled() async {
  final binding = WidgetsBinding.instance;
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  var quietChecks = 0;
  while (quietChecks < 4 && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final busy = binding.hasScheduledFrame || binding.transientCallbackCount > 0;
    quietChecks = busy ? 0 : quietChecks + 1;
  }
}

Future<void> _handOver(Directory handoff, String tag) async {
  final ready = File('${handoff.path}/$tag.ready')..writeAsStringSync('');
  final done = File('${handoff.path}/$tag.done');
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (!done.existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('No capture for "$tag" — is generate.sh running?');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  done.deleteSync();
  if (ready.existsSync()) ready.deleteSync();
}
