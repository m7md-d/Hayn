import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/widgets.dart';
import '../providers/onboarding_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OnboardingScreen — three swipeable pages (Welcome / Privacy / Permission).
// Persists completion via onboardingCompletedProvider; the router then routes
// out of /onboarding to / on its own.
// ─────────────────────────────────────────────────────────────────────────────

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  static const _pageCount = 3;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page < _pageCount - 1) {
      HapticFeedback.selectionClick();
      await _ctrl.nextPage(
        duration: AppDuration.normal,
        curve: AppCurves.standard,
      );
    } else {
      // Last page: just complete (handled by Grant / Skip buttons)
    }
  }

  Future<void> _complete() async {
    await ref.read(onboardingCompletedProvider.notifier).complete();
    // Router will redirect to / once the flag flips.
  }

  Future<void> _grantAccess() async {
    HapticFeedback.lightImpact();
    await PhotoManager.requestPermissionExtend();
    await _complete();
  }

  Future<void> _skip() async {
    HapticFeedback.selectionClick();
    await _complete();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _ctrl,
                onPageChanged: (i) {
                  HapticFeedback.selectionClick();
                  setState(() => _page = i);
                },
                children: [
                  _OnboardingPage(
                    icon: Icons.auto_awesome_rounded,
                    title: l.onboardingWelcomeTitle,
                    message: l.onboardingWelcomeMessage,
                  ),
                  _OnboardingPage(
                    icon: Icons.wifi_off_rounded,
                    title: l.onboardingPrivacyTitle,
                    message: l.onboardingPrivacyMessage,
                  ),
                  _OnboardingPage(
                    icon: Icons.photo_library_rounded,
                    title: l.onboardingPermissionTitle,
                    message: l.onboardingPermissionMessage,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            _Dots(active: _page, total: _pageCount),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: AnimatedSwitcher(
                duration: AppDuration.fast,
                child: _page < _pageCount - 1
                    ? HaynPrimaryButton(
                        key: const ValueKey('continue'),
                        label: l.onboardingContinue,
                        onPressed: _next,
                      )
                    : Column(
                        key: const ValueKey('final'),
                        children: [
                          HaynPrimaryButton(
                            label: l.onboardingPermissionGrant,
                            onPressed: _grantAccess,
                            icon: Icons.lock_open_rounded,
                          ),
                          const SizedBox(height: AppSpacing.s2),
                          HaynPlainButton(
                            label: l.onboardingSkip,
                            onPressed: _skip,
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          _AnimatedHero(icon: icon),
          const SizedBox(height: AppSpacing.xl),
          Text(
            title,
            style: theme.textTheme.displayMedium?.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: hc.text2,
              height: 1.5,
            ),
          ),
          const Spacer(),
          const Spacer(),
        ],
      ),
    );
  }
}

class _AnimatedHero extends StatefulWidget {
  const _AnimatedHero({required this.icon});
  final IconData icon;

  @override
  State<_AnimatedHero> createState() => _AnimatedHeroState();
}

class _AnimatedHeroState extends State<_AnimatedHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: AppDuration.slow,
  )..forward();

  late final Animation<double> _scale = Tween<double>(begin: 0.82, end: 1.0)
      .animate(CurvedAnimation(parent: _ctrl, curve: AppCurves.spring));

  late final Animation<double> _fade = CurvedAnimation(
    parent: _ctrl,
    curve: AppCurves.decelerate,
  );

  @override
  void didUpdateWidget(_AnimatedHero old) {
    super.didUpdateWidget(old);
    if (old.icon != widget.icon) {
      _ctrl
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return ScaleTransition(
      scale: _scale,
      child: FadeTransition(
        opacity: _fade,
        child: Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            color: hc.accentSoft,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(widget.icon, size: 60, color: hc.accent),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.active, required this.total});
  final int active;
  final int total;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final on = i == active;
        return AnimatedContainer(
          duration: AppDuration.fast,
          curve: AppCurves.standard,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: on ? 22 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: on ? hc.accent : hc.border,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
        );
      }),
    );
  }
}
