import 'dart:async';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min/statistics.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FfmpegRunner — the single seam between the app and the FFmpeg engine
// (ffmpeg_kit_flutter_new_min, LGPL — CLAUDE.md §6). Every video/audio task
// drives FFmpeg through here so cancellation, progress and "did it actually
// succeed" are handled in ONE place, and the package import lives behind this
// façade (swapping the engine later touches only this file).
//
// Commands are built with explicit argument LISTS (`executeWithArgumentsAsync`),
// never an interpolated string — a filename with a space or quote can't break
// or inject into the command line that way.
// ─────────────────────────────────────────────────────────────────────────────

/// A running FFmpeg session that can be awaited for success and cancelled.
class FfmpegRun {
  FfmpegRun._(this._sessionId, this._done);

  final int? _sessionId;
  final Future<bool> _done;

  /// Completes true when FFmpeg returned success (exit 0), false on error OR
  /// cancellation — the caller treats both as "no output produced".
  Future<bool> get success => _done;

  /// Ask FFmpeg to stop this session; [success] then completes false.
  Future<void> cancel() async {
    final id = _sessionId;
    if (id != null) await FFmpegKit.cancel(id);
  }
}

abstract final class FfmpegRunner {
  /// Run FFmpeg with [args]. [onProgress] receives the processed media time in
  /// milliseconds (pair it with the clip duration for a 0–1 bar). The returned
  /// [FfmpegRun] exposes success + cancellation. Never throws — a failed launch
  /// resolves to `success == false`.
  static Future<FfmpegRun> run(
    List<String> args, {
    void Function(int timeMs)? onProgress,
  }) async {
    if (onProgress != null) {
      FFmpegKitConfig.enableStatisticsCallback((Statistics s) {
        onProgress(s.getTime());
      });
    }
    try {
      final completer = Completer<bool>();
      final session = await FFmpegKit.executeWithArgumentsAsync(
        args,
        (session) async {
          final rc = await session.getReturnCode();
          if (!completer.isCompleted) completer.complete(ReturnCode.isSuccess(rc));
        },
      );
      return FfmpegRun._(session.getSessionId(), completer.future);
    } catch (_) {
      return FfmpegRun._(null, Future<bool>.value(false));
    }
  }

  /// The clip's duration in milliseconds via ffprobe, or null if unknown
  /// (the progress bar then falls back to indeterminate).
  static Future<int?> durationMs(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      final secs = double.tryParse(info?.getDuration() ?? '');
      return secs == null ? null : (secs * 1000).round();
    } catch (_) {
      return null;
    }
  }
}
