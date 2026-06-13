import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/isolates/media_task.dart';
import '../../../core/isolates/task_progress.dart';
import '../../image_ops/data/gallery_saver.dart';
import 'ffmpeg_runner.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RemoveAudioTask — strip the audio track from a video, 100% LOSSLESS.
//
// `-map 0:v -map 0:s? -c copy -an` copies the video (and any subtitle) streams
// VERBATIM and simply omits audio — no decode, no re-encode, so the picture is
// bit-identical and there's no codec/patent concern (CLAUDE.md §2/§6). The
// original is never touched; the muted copy is saved as a NEW gallery asset.
// Runs through the shared TaskRunner so it shows in the Tasks badge with
// progress + cancellation.
// ─────────────────────────────────────────────────────────────────────────────

class RemoveAudioTask extends MediaTask {
  RemoveAudioTask({required this.assetId})
      : id = 'rmaudio-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

  final String assetId;

  @override
  final String id;

  @override
  TaskType get type => TaskType.stripAudio;

  @override
  String? get sourceAssetId => assetId;

  FfmpegRun? _run;
  bool _cancelled = false;
  String? _outPath;

  @override
  Stream<TaskProgress> run() async* {
    yield const TaskProgress(progress: 0, phase: 'prepare');

    final entity = await AssetEntity.fromId(assetId);
    final input = await entity?.file;
    if (_cancelled) return;
    if (entity == null || input == null) {
      yield const TaskProgress(progress: 1, phase: 'error');
      return;
    }

    // Output beside the app's temp dir; ".mp4" keeps the MP4/MOV container the
    // copied H.264/HEVC stream already lives in.
    final dir = await getTemporaryDirectory();
    final out = p.join(
      dir.path,
      'noaudio_${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    _outPath = out;

    final totalMs = await FfmpegRunner.durationMs(input.path);
    if (_cancelled) return;

    // -y overwrite, -map 0:v (+ optional subtitles), -c copy, -an drop audio,
    // +faststart so the moov atom is at the front (streams/plays immediately).
    // No per-frame progress: a stream copy is near-instant, so a coarse
    // prepare→process→save bar is plenty (and avoids coupling the event stream
    // to FFmpeg's statistics callback for no real UX gain).
    _run = await FfmpegRunner.run([
      '-y',
      '-i', input.path,
      '-map', '0:v',
      '-map', '0:s?',
      '-c', 'copy',
      '-an',
      '-movflags', '+faststart',
      out,
    ]);
    if (_cancelled) {
      await _run?.cancel();
      return;
    }
    yield TaskProgress(
      progress: 0.5,
      phase: 'process',
      estimatedRemaining:
          totalMs == null ? null : Duration(milliseconds: totalMs ~/ 4),
    );

    final ok = await _run!.success;
    if (_cancelled) return;
    final file = File(out);
    if (!ok || !await file.exists() || await file.length() == 0) {
      yield const TaskProgress(progress: 1, phase: 'error');
      return;
    }

    yield const TaskProgress(progress: 0.9, phase: 'save');
    final saved = await GallerySaver.saveVideo(
      file,
      filename: '${p.basenameWithoutExtension(await _sourceName(entity))}_muted.mp4',
      creationDate: DateTime.now(),
    );
    if (saved != null) outputAssetIds.add(saved.id);
    await cleanup();
    yield TaskProgress(progress: 1, phase: saved == null ? 'error' : 'done');
  }

  Future<String> _sourceName(AssetEntity e) async =>
      (await e.titleAsync).isNotEmpty ? await e.titleAsync : 'video';

  @override
  Future<void> cancel() async {
    _cancelled = true;
    await _run?.cancel();
  }

  @override
  Future<void> cleanup() async {
    final path = _outPath;
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // best-effort temp cleanup
    }
  }
}
