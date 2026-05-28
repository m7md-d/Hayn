import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import '../../../../app/theme/app_theme_extension.dart';
import '../../../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AssetVideoPlayer — in-app playback for a single video AssetEntity.
//
// Layout: video filled to the available width with its aspect ratio. Tap
// toggles play/pause; a mute button sits in the corner. A thin progress bar
// at the bottom shows playhead position; tapping anywhere on it seeks.
//
// Controller is created lazily once the underlying File resolves from
// photo_manager. Releases on dispose.
// ─────────────────────────────────────────────────────────────────────────────

class AssetVideoPlayer extends StatefulWidget {
  const AssetVideoPlayer({required this.asset, super.key});
  final AssetEntity asset;

  @override
  State<AssetVideoPlayer> createState() => _AssetVideoPlayerState();
}

class _AssetVideoPlayerState extends State<AssetVideoPlayer> {
  VideoPlayerController? _ctrl;
  bool _initialising = true;
  bool _ready = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final file = await widget.asset.file;
    if (file == null || !await file.exists()) {
      if (mounted) setState(() => _initialising = false);
      return;
    }
    final ctrl = VideoPlayerController.file(File(file.path));
    try {
      await ctrl.initialize();
      ctrl.setLooping(false);
      ctrl.addListener(_onTick);
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _ctrl = ctrl;
        _ready = true;
        _initialising = false;
      });
    } catch (_) {
      await ctrl.dispose();
      if (mounted) setState(() => _initialising = false);
    }
  }

  void _onTick() {
    if (mounted) setState(() {}); // refresh progress bar
  }

  void _togglePlay() {
    final c = _ctrl;
    if (c == null) return;
    HapticFeedback.lightImpact();
    if (c.value.isPlaying) {
      c.pause();
    } else {
      // Restart from start if we're at the end.
      if (c.value.position >= c.value.duration) {
        c.seekTo(Duration.zero);
      }
      c.play();
    }
  }

  void _toggleMute() {
    final c = _ctrl;
    if (c == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
    });
  }

  void _seekFraction(double f) {
    final c = _ctrl;
    if (c == null) return;
    final d = c.value.duration;
    c.seekTo(Duration(milliseconds: (d.inMilliseconds * f.clamp(0, 1)).round()));
  }

  @override
  void dispose() {
    final c = _ctrl;
    if (c != null) {
      c.removeListener(_onTick);
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initialising) {
      return const _PlayerLoading();
    }
    final c = _ctrl;
    if (!_ready || c == null) {
      return const _PlayerError();
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Video frame (centred and scaled to fit).
          AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: VideoPlayer(c),
          ),

          // Play overlay (only when paused).
          AnimatedOpacity(
            opacity: c.value.isPlaying ? 0 : 1,
            duration: AppDuration.fast,
            child: _PlayOverlay(),
          ),

          // Mute toggle in top-end corner.
          PositionedDirectional(
            top: 16,
            end: 16,
            child: SafeArea(
              child: _MuteButton(muted: _muted, onTap: _toggleMute),
            ),
          ),

          // Bottom progress bar — thin tappable bar.
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _VideoProgressBar(
              controller: c,
              onSeek: _seekFraction,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerLoading extends StatelessWidget {
  const _PlayerLoading();
  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 80, height: 80,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
      );
}

class _PlayerError extends StatelessWidget {
  const _PlayerError();
  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: hc.dangerColor),
          const SizedBox(width: AppSpacing.s2),
          const Text('Playback unavailable',
              style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

class _PlayOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80, height: 80,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 44,
      ),
    );
  }
}

class _MuteButton extends StatelessWidget {
  const _MuteButton({required this.muted, required this.onTap});
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

class _VideoProgressBar extends StatelessWidget {
  const _VideoProgressBar({
    required this.controller,
    required this.onSeek,
  });
  final VideoPlayerController controller;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final fraction = value.duration.inMilliseconds == 0
        ? 0.0
        : value.position.inMilliseconds / value.duration.inMilliseconds;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        onSeek(d.localPosition.dx / box.size.width);
      },
      onTapDown: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        onSeek(d.localPosition.dx / box.size.width);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Row(
          children: [
            Text(_format(value.position),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
            const SizedBox(width: 8),
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: fraction.clamp(0.0, 1.0),
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_format(value.duration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
          ],
        ),
      ),
    );
  }

  static String _format(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
