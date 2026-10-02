import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/darklib/darklib.dart';
import '../../../core/diagnostics/media_diagnostics.dart';
import '../../video_ops/data/ffmpeg_runner.dart';
import 'image_probe.dart';

// Android's HEIF decoder ignores the alpha plane of a transparent HEIC and
// returns its colour samples as opaque (IMG-15). Apple codes that plane as a
// monochrome HEVC image (Rext 4:0:0), which neither the HEIF decoder nor the
// phone's MediaCodec decoders accept (probes on a Galaxy S25 Edge,
// 2026-10-02). The FFmpeg the app already ships for video decodes it. DarkLib
// does the container work: the stream out of the HEIF, then the plane, with
// the alpha item's own orientation, into the platform's decode. FFmpeg only
// decodes; no codec is added.

abstract final class HeifAlpha {
  /// [decoded], the platform's decode of [source], with [source]'s HEIF alpha
  /// put back. [decoded] unchanged when [source] is not a HEIF with alpha, or
  /// when a step fails: the failure is recorded, and the output check then
  /// refuses the result (`alphaLost`) instead of saving hidden colours.
  static Future<Uint8List> restore(Uint8List source, Uint8List decoded) async {
    if (ImageProbe.sniff(source) != SniffedFormat.heic) return decoded;
    if ((await DarkLibCore.inspect(source))?.alpha != Presence.present) {
      return decoded;
    }
    final stream = await DarkLibCore.heifAlphaStream(source);
    if (stream == null) return decoded;
    final grey = await decodeGrey(stream);
    if (grey == null) {
      MediaDiagnostics.record(
        MediaBackend.ffmpeg,
        MediaOperation.bake,
        MediaDiagnosticCode.emptyOutput,
      );
      return decoded;
    }
    return await DarkLibCore.heifAttachAlpha(
          source: source,
          base: decoded,
          grey: grey,
        ) ??
        decoded;
  }

  /// Decodes the stream to `frames × width × height` bytes of 8-bit grey.
  /// Tests replace it; on a phone it is FFmpeg.
  @visibleForTesting
  static Future<Uint8List?> Function(AlphaStream stream) decodeGrey =
      _ffmpegGrey;

  static Future<Uint8List?> _ffmpegGrey(AlphaStream stream) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final input = File('${dir.path}/hayn-alpha-$stamp.hevc');
    final output = File('${dir.path}/hayn-alpha-$stamp.gray');
    try {
      await input.writeAsBytes(stream.hevc, flush: true);
      final run = await FfmpegRunner.run([
        '-hide_banner',
        '-nostdin',
        '-y',
        '-f', 'hevc', //
        '-i', input.path,
        // One output frame per coded tile, none dropped or repeated.
        '-frames:v', '${stream.frames}',
        '-fps_mode', 'passthrough',
        // Alpha is full range; a limited-range plane is expanded.
        '-vf', 'scale=out_range=full',
        '-f', 'rawvideo',
        '-pix_fmt', 'gray',
        output.path,
      ]);
      if (!await run.success) return null;
      final grey = await output.readAsBytes();
      final want = stream.frames * stream.width * stream.height;
      return grey.length == want ? grey : null;
    } catch (_) {
      return null; // the caller records the failed decode
    } finally {
      for (final f in [input, output]) {
        try {
          if (f.existsSync()) f.deleteSync();
        } catch (_) {
          // A leftover temporary file is not a reason to fail the image.
        }
      }
    }
  }
}
