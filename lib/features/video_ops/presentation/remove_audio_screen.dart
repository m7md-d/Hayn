import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/widgets.dart';
import '../../library/presentation/providers/library_provider.dart';
import '../../library/presentation/widgets/asset_video_player.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RemoveAudioScreen — dedicated single-action screen for stripping audio
// from a video. The video stream is copied verbatim (lossless), so the only
// decision the user faces is: "yes, mute it".
//
//   ┌── AppBar ──────────────────────────────────┐
//   │ [Cancel]   Remove sound          [Done]   │
//   ├────────────────────────────────────────────┤
//   │                                            │
//   │           [Video preview]                  │
//   │                                            │
//   ├────────────────────────────────────────────┤
//   │   "Lossless — video stream is copied       │
//   │    untouched. Audio track is removed."     │
//   │                                            │
//   │   [Save without sound]                     │
//   │   Works offline · No quality loss          │
//   └────────────────────────────────────────────┘
// ─────────────────────────────────────────────────────────────────────────────

class RemoveAudioScreen extends ConsumerStatefulWidget {
  const RemoveAudioScreen({required this.assetId, super.key});
  final String assetId;

  @override
  ConsumerState<RemoveAudioScreen> createState() => _RemoveAudioScreenState();
}

class _RemoveAudioScreenState extends ConsumerState<RemoveAudioScreen> {
  AssetEntity? _asset;

  @override
  void initState() {
    super.initState();
    final all = ref.read(libraryProvider).assets;
    _asset = all.firstWhere(
      (a) => a.id == widget.assetId,
      orElse: () => all.first,
    );
  }

  Future<void> _apply() async {
    HapticFeedback.lightImpact();
    final l = AppLocalizations.of(context);
    HaynSnack.success(context, l.removeAudioQueued);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hc = context.hc;
    final theme = Theme.of(context);
    final asset = _asset;
    if (asset == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return HaynScaffold(
      appBar: HaynModalAppBar(
        title: l.toolRemoveAudio,
        onDone: _apply,
        doneLabel: l.commonDone,
      ),
      body: Column(
        children: [
          // ── Preview ─────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: asset.width / asset.height,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AssetVideoPlayer(asset: asset),
                          // Mute-indicator overlay so the user instantly
                          // sees what this screen is for.
                          PositionedDirectional(
                            top: AppSpacing.md,
                            end: AppSpacing.md,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.s3,
                                  vertical: 6),
                              decoration: BoxDecoration(
                                color: hc.dangerColor,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.full),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.volume_off_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    l.removeAudioBadge,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Reassurance banner + action ───────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HaynInlineBanner(
                    tone: HaynBannerTone.success,
                    icon: Icons.flash_on_rounded,
                    message: l.removeAudioExplain,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  HaynPrimaryButton(
                    label: l.removeAudioActionLabel,
                    icon: Icons.volume_off_rounded,
                    onPressed: _apply,
                    size: HaynButtonSize.large,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 12, color: hc.text3),
                      const SizedBox(width: 4),
                      Text(
                        l.settingsPrivacy,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: hc.text3),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
