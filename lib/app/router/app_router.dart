import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../shell/app_shell.dart';
import '../shell/swipeable_tabs.dart';
import '../../features/about/presentation/about_screen.dart';
import '../../features/animated/presentation/animate_from_photos_screen.dart';
import '../../features/animated/presentation/animate_from_video_screen.dart';
import '../../features/animated/presentation/extract_frames_screen.dart';
import '../../features/audio/presentation/separate_audio_result_screen.dart';
import '../../features/audio/presentation/separate_audio_screen.dart';
import '../../features/image_ops/presentation/compress_screen.dart';
import '../../features/image_ops/presentation/crop_screen.dart';
import '../../features/library/presentation/asset_detail_screen.dart';
import '../../features/surgical/presentation/surgical_arena_screen.dart';
import '../../features/surgical/presentation/surgical_batch_screen.dart';
import '../../features/video_ops/presentation/crop_video_screen.dart';
import '../../features/video_ops/presentation/remove_audio_screen.dart';
import '../../features/video_ops/presentation/trim_video_screen.dart';
import '../../features/video_ops/presentation/video_editor_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/onboarding/providers/onboarding_provider.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/tasks/presentation/task_detail_screen.dart';
import '../../features/tasks/presentation/tasks_screen.dart';
import '../../features/tools/presentation/tools_screen.dart';
import '../../features/trash/presentation/trash_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// App router. Exposed as a provider so we can react to onboarding completion
// and redirect first-run users to /onboarding.
//
// Top-level routes (modal-style, full screen):
//   /onboarding    — first-run flow
//   /about         — About screen (push from Settings)
//   /donate        — Donate screen (push from Settings)
//
// /  + /tools + /tasks + /settings live under the StatefulShellRoute that
// owns the bottom NavigationBar.
// ─────────────────────────────────────────────────────────────────────────────

final appRouterProvider = Provider<GoRouter>((ref) {
  final listenable = _OnboardingListenable(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: listenable,
    redirect: (context, state) {
      final completed = ref.read(onboardingCompletedProvider);
      final atOnboarding = state.matchedLocation == '/onboarding';

      if (!completed && !atOnboarding) return '/onboarding';
      if (completed && atOnboarding) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/about',
        builder: (_, __) => const AboutScreen(),
      ),
      GoRoute(
        path: '/asset/:id',
        // Transparent overlay route so the library shows through whenever the
        // viewer's own background fades (e.g. mid-drag dismiss). Without this,
        // the library is hidden behind an opaque page and the image would
        // appear floating over solid black even when its bg is transparent.
        pageBuilder: (ctx, state) => CustomTransitionPage(
          opaque: false,
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          child: AssetDetailScreen(assetId: state.pathParameters['id']!),
          transitionsBuilder: (context, anim, sec, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      ),
      GoRoute(
        path: '/compress',
        pageBuilder: (ctx, state) {
          final ids = (state.extra as List?)?.cast<String>() ?? const <String>[];
          return MaterialPage(
            fullscreenDialog: true,
            child: CompressScreen(assetIds: ids),
          );
        },
      ),
      GoRoute(
        path: '/crop/:id',
        pageBuilder: (ctx, state) => MaterialPage(
          fullscreenDialog: true,
          child: CropScreen(assetId: state.pathParameters['id']!),
        ),
      ),
      // /surgical/batch must come BEFORE /surgical/:id so the literal
      // "batch" path doesn't get captured as an id parameter.
      GoRoute(
        path: '/surgical/batch',
        pageBuilder: (ctx, state) {
          final ids =
              (state.extra as List?)?.cast<String>() ?? const <String>[];
          return MaterialPage(
            fullscreenDialog: true,
            child: SurgicalBatchScreen(assetIds: ids),
          );
        },
      ),
      GoRoute(
        path: '/surgical/:id',
        pageBuilder: (ctx, state) => MaterialPage(
          fullscreenDialog: true,
          child: SurgicalArenaScreen(
            assetId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/video-edit/:id',
        pageBuilder: (ctx, state) => MaterialPage(
          fullscreenDialog: true,
          child: VideoEditorScreen(
            assetId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/trim/:id',
        pageBuilder: (ctx, state) => MaterialPage(
          fullscreenDialog: true,
          child: TrimVideoScreen(assetId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/crop-video/:id',
        pageBuilder: (ctx, state) => MaterialPage(
          fullscreenDialog: true,
          child: CropVideoScreen(assetId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/remove-audio/:id',
        pageBuilder: (ctx, state) => MaterialPage(
          fullscreenDialog: true,
          child: RemoveAudioScreen(assetId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/audio-separate/:id',
        pageBuilder: (ctx, state) => MaterialPage(
          fullscreenDialog: true,
          child: SeparateAudioScreen(assetId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/audio-result/:id',
        pageBuilder: (ctx, state) => MaterialPage(
          fullscreenDialog: true,
          child: SeparateAudioResultScreen(
              assetId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/animate/video/:id',
        pageBuilder: (ctx, state) => MaterialPage(
          fullscreenDialog: true,
          child: AnimateFromVideoScreen(assetId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/animate/photos',
        pageBuilder: (ctx, state) {
          final ids =
              (state.extra as List?)?.cast<String>() ?? const <String>[];
          return MaterialPage(
            fullscreenDialog: true,
            child: AnimateFromPhotosScreen(assetIds: ids),
          );
        },
      ),
      GoRoute(
        path: '/extract-frames/:id',
        pageBuilder: (ctx, state) => MaterialPage(
          fullscreenDialog: true,
          child: ExtractFramesScreen(assetId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/task/:id',
        builder: (_, state) =>
            TaskDetailScreen(taskId: state.pathParameters['id']!),
      ),
      // Tasks list is no longer a bottom-nav branch; it's reachable only via
      // the floating tasks badge as a full-screen push.
      GoRoute(
        path: '/tasks',
        builder: (_, __) => const TasksScreen(),
      ),
      GoRoute(
        path: '/trash',
        builder: (_, __) => const TrashScreen(),
      ),
      StatefulShellRoute(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        navigatorContainerBuilder: (ctx, navigationShell, children) =>
            SwipeableTabs(
          currentIndex: navigationShell.currentIndex,
          onPageChanged: (i) {
            if (navigationShell.currentIndex != i) navigationShell.goBranch(i);
          },
          children: children,
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, __) => const LibraryScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/tools', builder: (_, __) => const ToolsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/settings',
                builder: (_, __) => const SettingsScreen()),
          ]),
        ],
      ),
    ],
  );
});

// Bridges a Riverpod provider to GoRouter's refreshListenable contract.
class _OnboardingListenable extends ChangeNotifier {
  _OnboardingListenable(Ref ref) {
    ref.listen<bool>(onboardingCompletedProvider, (_, __) => notifyListeners());
  }
}
