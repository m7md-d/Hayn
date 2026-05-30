import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_extension.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/widgets.dart';
import '../../library/presentation/providers/asset_entity_cache.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SeparateAudioScreen — configuration step for the heavy AI separation task.
// Shows clip waveform + strength slider (with Auto badge) + live ETA + tip
// banner + offline reassurance.
//
// "Start separation" routes to /audio-result/:id where the user previews
// before saving. Real engine wiring happens in the implementation phase.
// ─────────────────────────────────────────────────────────────────────────────

class SeparateAudioScreen extends ConsumerStatefulWidget {
  const SeparateAudioScreen({required this.assetId, super.key});
  final String assetId;

  @override
  ConsumerState<SeparateAudioScreen> createState() =>
      _SeparateAudioScreenState();
}

class _SeparateAudioScreenState extends ConsumerState<SeparateAudioScreen> {
  AssetEntity? _asset;
  double _strength = 62; // default — corresponds to "Auto" behaviour
  bool _isAuto = true;

  @override
  void initState() {
    super.initState();
    _asset = AssetEntityCache.get(widget.assetId);
    if (_asset == null) {
      AssetEntityCache.load(widget.assetId).then((a) {
        if (mounted && a != null) setState(() => _asset = a);
      });
    }
  }

  String get _etaLabel {
    final clipSec = _asset?.videoDuration.inSeconds ?? 60;
    // Heuristic: 0.6× clip duration at strength 50, scales up to 2× at 100.
    final factor = 0.4 + (_strength / 100) * 1.6;
    final estSec = (clipSec * factor).round();
    final m = estSec ~/ 60;
    final s = (estSec % 60).toString().padLeft(2, '0');
    return '~$m:$s min';
  }

  void _start() {
    HapticFeedback.lightImpact();
    context.replace('/audio-result/${Uri.encodeComponent(widget.assetId)}');
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
      appBar: HaynModalAppBar(title: l.toolSeparateMusic),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.s2, AppSpacing.md, 120,
        ),
        children: [
          // ── Waveform ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: HaynWaveform(
              seed: asset.id.hashCode,
              barCount: 56,
              height: 80,
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Strength slider w/ Auto badge ──────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HaynValueSlider(
                  label: l.audioStrengthLabel,
                  valueLabel: _isAuto ? l.audioAutoBadge : '${_strength.round()}%',
                  value: _strength,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (v) => setState(() {
                    _strength = v;
                    _isAuto = false;
                  }),
                  helper: _strength < 40
                      ? l.audioStrengthLight
                      : _strength > 80
                          ? l.audioStrengthAggressive
                          : l.audioStrengthBalanced,
                  trailing: !_isAuto
                      ? TextButton(
                          onPressed: () => setState(() {
                            _strength = 62;
                            _isAuto = true;
                          }),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s2),
                            minimumSize: const Size(0, 28),
                          ),
                          child: Text(l.audioResetToAuto,
                              style: const TextStyle(fontSize: 11)),
                        )
                      : null,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // ── ETA card ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: hc.surface2,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: hc.border),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: hc.text2),
                const SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: Text(
                    l.audioEstimatedTime,
                    style: theme.textTheme.bodyMedium?.copyWith(color: hc.text2),
                  ),
                ),
                Text(
                  _etaLabel,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Tip banner ─────────────────────────────────────────────────
          HaynInlineBanner(
            tone: HaynBannerTone.info,
            icon: Icons.lightbulb_outline_rounded,
            message: l.audioTip,
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── Start button ───────────────────────────────────────────────
          HaynPrimaryButton(
            label: l.audioStartSeparation,
            icon: Icons.play_arrow_rounded,
            onPressed: _start,
            size: HaynButtonSize.large,
          ),

          const SizedBox(height: AppSpacing.s3),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off_rounded, size: 12, color: hc.text3),
              const SizedBox(width: 4),
              Text(
                l.settingsPrivacy,
                style: theme.textTheme.labelSmall?.copyWith(color: hc.text3),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
