import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NativeVideoProbe — reads a video's codec / fps / frame count via the platform
// (iOS: AVFoundation). photo_manager doesn't expose these. Offline only (the
// native side disables iCloud fetches). Returns null when there's no native
// impl (Android/desktop today) or the asset isn't a local video. Never throws.
// ─────────────────────────────────────────────────────────────────────────────

class VideoProbeInfo {
  const VideoProbeInfo({required this.codec, required this.fps, required this.frames});
  final String codec;
  final double fps;
  final int frames;
}

abstract final class NativeVideoProbe {
  static const MethodChannel channel = MethodChannel('hayn/video');

  static Future<VideoProbeInfo?> probe(String assetId) async {
    try {
      final res = await channel.invokeMapMethod<String, dynamic>(
        'probe',
        <String, dynamic>{'id': assetId},
      );
      if (res == null) return null;
      final codec = (res['codec'] as String?)?.trim() ?? '';
      final fps = (res['fps'] as num?)?.toDouble() ?? 0;
      final frames = (res['frames'] as num?)?.toInt() ?? 0;
      if (codec.isEmpty && fps <= 0 && frames <= 0) return null;
      return VideoProbeInfo(codec: codec, fps: fps, frames: frames);
    } catch (_) {
      return null;
    }
  }
}
