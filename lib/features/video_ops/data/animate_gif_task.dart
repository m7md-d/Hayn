import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/isolates/media_task.dart';
import '../../../core/isolates/task_progress.dart';
import '../../image_ops/data/gallery_saver.dart';
import 'ffmpeg_runner.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnimateGifFromVideoTask — turn a trimmed slice of a video into a looping GIF.
//
// GIF is the ONE animated format the lightweight LGPL ffmpeg build can encode
// (its native gif encoder); animated WebP/AVIF go through DarkLib instead (they
// need libwebp/AV1 encoders not in the `_min` build). Quality matters: a naive
// GIF bands badly because GIF is limited to 256 colours, so we use the
// palettegen→paletteuse two-filter pipeline (a per-clip optimised palette +
// dithering) — the recipe that meets `06-TESTING.md`'s "GIF without obvious
// banding" bar. Saved as a new gallery asset; original untouched; cancellable.
// ─────────────────────────────────────────────────────────────────────────────

class AnimateGifFromVideoTask extends MediaTask {
  AnimateGifFromVideoTask({
    required this.assetId,
    required this.startSeconds,
    required this.endSeconds,
    required this.fps,
    required this.height,
  }) : id = 'gif-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

  final String assetId;
  final double startSeconds;
  final double endSeconds;
  final int fps;

  /// Output height in pixels; width auto-scaled to keep aspect (Lanczos).
  final int height;

  @override
  final String id;

  @override
  TaskType get type => TaskType.gifify;

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

    final dir = await getTemporaryDirectory();
    final out = p.join(dir.path, 'gif_${DateTime.now().microsecondsSinceEpoch}.gif');
    _outPath = out;

    final dur = (endSeconds - startSeconds).clamp(0.1, 60.0);
    final f = fps.clamp(1, 50);
    final h = height.clamp(120, 1080);
    // One filtergraph: thin to `fps`, scale to height (even via -2), then split —
    // one branch builds an optimised palette (stats_mode=diff favours moving
    // areas), the other maps to it with light dithering to kill banding.
    final filter = 'fps=$f,scale=-2:$h:flags=lanczos,'
        'split[s0][s1];[s0]palettegen=stats_mode=diff[p];'
        '[s1][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle';

    yield const TaskProgress(progress: 0.3, phase: 'process');
    // Pre-input -ss (fast seek) + -t duration → only the chosen slice is read.
    _run = await FfmpegRunner.run([
      '-y',
      '-ss', '${startSeconds < 0 ? 0 : startSeconds}',
      '-t', '$dur',
      '-i', input.path,
      '-vf', filter,
      '-loop', '0', // 0 = loop forever
      out,
    ]);
    if (_cancelled) {
      await _run?.cancel();
      await cleanup();
      return;
    }

    final ok = await _run!.success;
    if (_cancelled) {
      await cleanup();
      return;
    }
    final file = File(out);
    if (!ok || !await file.exists() || await file.length() == 0) {
      await cleanup();
      yield const TaskProgress(progress: 1, phase: 'error');
      return;
    }

    yield const TaskProgress(progress: 0.9, phase: 'save');
    final base = (await entity.titleAsync).isNotEmpty
        ? p.basenameWithoutExtension(await entity.titleAsync)
        : 'animation';
    // A GIF is image data — saved through the image saver so the gallery treats
    // it as an (animated) photo.
    final saved = await GallerySaver.saveImage(
      await file.readAsBytes(),
      filename: '$base.gif',
      creationDate: DateTime.now(),
    );
    if (saved != null) outputAssetIds.add(saved.id);
    await cleanup();
    yield TaskProgress(progress: 1, phase: saved == null ? 'error' : 'done');
  }

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
