import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/isolates/media_task.dart';
import '../../../core/isolates/task_progress.dart';
import '../../image_ops/data/gallery_saver.dart';
import 'ffmpeg_runner.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ExtractFramesTask — pull still frames out of a video and save them to the
// gallery as PNG (lossless: the frame is decoded straight from the stream, no
// re-encode, so no generational loss — CLAUDE.md §2; the user can compress the
// stills afterwards with the image tools).
//
// Three modes mirror the UI:
//   • interval — one frame every N seconds   (-vf fps=1/N)
//   • fps      — N frames per second          (-vf fps=N)
//   • single   — one frame at a timestamp     (-ss T -frames:v 1)
//
// FFmpeg writes frame_%04d.png to a temp dir; we save each in order, then clean
// up. Capped at [_maxFrames] so a long clip at high fps can't flood the gallery
// or fill the disk (the UI shows the same cap in its estimate).
// ─────────────────────────────────────────────────────────────────────────────

enum FrameMode { interval, fps, single }

class ExtractFramesTask extends MediaTask {
  ExtractFramesTask({
    required this.assetId,
    required this.mode,
    this.intervalSeconds = 5,
    this.fps = 1,
    this.atSeconds = 0,
  }) : id = 'frames-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

  final String assetId;
  final FrameMode mode;
  final double intervalSeconds;
  final double fps;
  final double atSeconds;

  /// Matches the UI's `.clamp(1, 64)` estimate — a hard ceiling on saved assets.
  static const int _maxFrames = 64;

  @override
  final String id;

  @override
  TaskType get type => TaskType.extractFrames;

  @override
  String? get sourceAssetId => assetId;

  bool _cancelled = false;
  Directory? _workDir;

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

    final tmp = await getTemporaryDirectory();
    final work = Directory(
      p.join(tmp.path, 'frames_${DateTime.now().microsecondsSinceEpoch}'),
    );
    await work.create(recursive: true);
    _workDir = work;
    final pattern = p.join(work.path, 'frame_%04d.png');

    final args = switch (mode) {
      FrameMode.interval => [
          '-y', '-i', input.path,
          '-vf', 'fps=1/${intervalSeconds <= 0 ? 1 : intervalSeconds}',
          '-frames:v', '$_maxFrames',
          pattern,
        ],
      FrameMode.fps => [
          '-y', '-i', input.path,
          '-vf', 'fps=${fps <= 0 ? 1 : fps}',
          '-frames:v', '$_maxFrames',
          pattern,
        ],
      // Seek BEFORE -i for a fast keyframe-accurate seek, one frame out.
      FrameMode.single => [
          '-y', '-ss', '${atSeconds < 0 ? 0 : atSeconds}',
          '-i', input.path,
          '-frames:v', '1',
          pattern,
        ],
    };

    yield const TaskProgress(progress: 0.3, phase: 'process');
    final ran = await _ffmpeg(args);
    if (_cancelled) {
      await cleanup();
      return;
    }
    if (!ran) {
      await cleanup();
      yield const TaskProgress(progress: 1, phase: 'error');
      return;
    }

    // Save each produced frame, in filename order, as a new gallery image.
    final frames = work
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final base = p.basenameWithoutExtension(await _name(entity));

    var saved = 0;
    for (var i = 0; i < frames.length; i++) {
      if (_cancelled) break;
      yield TaskProgress(
        progress: 0.4 + 0.6 * (i / frames.length),
        phase: '$saved/${frames.length}',
      );
      try {
        final bytes = await frames[i].readAsBytes();
        final asset = await GallerySaver.saveImage(
          bytes,
          filename: '${base}_frame${(i + 1).toString().padLeft(3, '0')}.png',
          creationDate: DateTime.now(),
        );
        if (asset != null) {
          saved++;
          outputAssetIds.add(asset.id);
        }
      } catch (_) {
        // Skip a bad frame; keep saving the rest.
      }
    }

    await cleanup();
    yield TaskProgress(progress: 1, phase: saved == 0 ? 'error' : 'done');
  }

  /// Run FFmpeg via the shared façade (see [FfmpegRunner]); cancellable.
  Future<bool> _ffmpeg(List<String> args) async {
    final run = await FfmpegRunner.run(args);
    _activeRun = run;
    if (_cancelled) {
      await run.cancel();
      return false;
    }
    return run.success;
  }

  FfmpegRun? _activeRun;

  Future<String> _name(AssetEntity e) async =>
      (await e.titleAsync).isNotEmpty ? await e.titleAsync : 'video';

  @override
  Future<void> cancel() async {
    _cancelled = true;
    await _activeRun?.cancel();
  }

  @override
  Future<void> cleanup() async {
    final dir = _workDir;
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // best-effort temp cleanup
    }
  }
}
