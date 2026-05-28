import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/widgets.dart';
import '../../library/presentation/providers/library_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SeparateAudioResultScreen — A/B preview after separation completes.
// Two waveforms (Original / Vocals only), each with its own play head.
// Real audio playback ships when audioplayers is wired; for now the cursors
// are driven by a synthetic 12-second loop.
// ─────────────────────────────────────────────────────────────────────────────

class SeparateAudioResultScreen extends ConsumerStatefulWidget {
  const SeparateAudioResultScreen({required this.assetId, super.key});
  final String assetId;

  @override
  ConsumerState<SeparateAudioResultScreen> createState() =>
      _SeparateAudioResultScreenState();
}

class _SeparateAudioResultScreenState
    extends ConsumerState<SeparateAudioResultScreen>
    with TickerProviderStateMixin {
  AssetEntity? _asset;

  // Two tracks each have play state + a 12-second simulated cursor.
  bool _origPlaying = false;
  bool _vocalsPlaying = false;
  late final AnimationController _origCursor;
  late final AnimationController _vocalsCursor;

  @override
  void initState() {
    super.initState();
    final all = ref.read(libraryProvider).assets;
    _asset = all.firstWhere(
      (a) => a.id == widget.assetId,
      orElse: () => all.first,
    );
    _origCursor = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..addListener(() => setState(() {}));
    _vocalsCursor = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _origCursor.dispose();
    _vocalsCursor.dispose();
    super.dispose();
  }

  void _toggleOriginal() {
    HapticFeedback.lightImpact();
    setState(() {
      _origPlaying = !_origPlaying;
      if (_origPlaying) {
        _origCursor.forward();
        _vocalsPlaying = false;
        _vocalsCursor.stop();
      } else {
        _origCursor.stop();
      }
    });
  }

  void _toggleVocals() {
    HapticFeedback.lightImpact();
    setState(() {
      _vocalsPlaying = !_vocalsPlaying;
      if (_vocalsPlaying) {
        _vocalsCursor.forward();
        _origPlaying = false;
        _origCursor.stop();
      } else {
        _vocalsCursor.stop();
      }
    });
  }

  void _save() {
    HapticFeedback.lightImpact();
    final l = AppLocalizations.of(context);
    HaynSnack.success(context, l.commonSave);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    final asset = _asset;
    if (asset == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final seed = asset.id.hashCode;

    final l = AppLocalizations.of(context);
    return HaynScaffold(
      appBar: HaynModalAppBar(
        title: l.audioCompareResult,
        onDone: _save,
        doneLabel: l.commonSave,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, 120,
        ),
        children: [
          _TrackCard(
            label: l.audioOriginalLabel,
            description: l.audioOriginalDesc,
            newBadge: l.audioNewBadge,
            isPlaying: _origPlaying,
            seed: seed,
            cursorFraction: _origCursor.value,
            onTogglePlay: _toggleOriginal,
            isPrimary: false,
          ),

          const SizedBox(height: AppSpacing.md),

          _TrackCard(
            label: l.audioVocalsOnly,
            description: l.audioVocalsOnlyDesc,
            newBadge: l.audioNewBadge,
            isPlaying: _vocalsPlaying,
            seed: seed + 1,
            cursorFraction: _vocalsCursor.value,
            onTogglePlay: _toggleVocals,
            isPrimary: true,
          ),

          const SizedBox(height: AppSpacing.lg),

          HaynInlineBanner(
            tone: HaynBannerTone.success,
            icon: Icons.check_circle_rounded,
            message: l.audioCompareInstructions,
          ),

          const SizedBox(height: AppSpacing.md),

          HaynSecondaryButton(
            label: l.audioDiscardRedo,
            icon: Icons.refresh_rounded,
            onPressed: () => Navigator.of(context).pop(),
          ),

          const SizedBox(height: AppSpacing.s3),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off_rounded, size: 12, color: hc.text3),
              const SizedBox(width: 4),
              Text(
                l.audioGeneratedOnDevice,
                style: theme.textTheme.labelSmall?.copyWith(color: hc.text3),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.label,
    required this.description,
    required this.newBadge,
    required this.isPlaying,
    required this.seed,
    required this.cursorFraction,
    required this.onTogglePlay,
    required this.isPrimary,
  });

  final String label;
  final String description;
  final String newBadge;
  final bool isPlaying;
  final int seed;
  final double cursorFraction;
  final VoidCallback onTogglePlay;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: isPrimary ? Border.all(color: hc.accentSoft, width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onTogglePlay,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isPrimary ? hc.accent : hc.surface2,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 26,
                    color: isPrimary ? hc.onAccent : hc.accent,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(color: hc.text2),
                    ),
                  ],
                ),
              ),
              if (isPrimary)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s2, vertical: 3),
                  decoration: BoxDecoration(
                    color: hc.successSoft,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    newBadge,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hc.successColor,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          HaynWaveform(
            seed: seed,
            barCount: 56,
            height: 64,
            cursorFraction: cursorFraction,
          ),
        ],
      ),
    );
  }
}
