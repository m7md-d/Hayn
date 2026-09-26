import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffmpeg_kit_flutter_new_min/abstract_session.dart';
import 'package:ffmpeg_kit_flutter_new_min/statistics.dart';
import 'package:ffmpeg_kit_flutter_new_min/src/ffmpeg_kit_factory.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/features/video_ops/data/ffmpeg_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter.arthenica.com/ffmpeg_kit');
  const events = MethodChannel('flutter.arthenica.com/ffmpeg_kit_event');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var nextId = 100;
  var cancelled = false;
  var failReturnCode = false;
  var failCancel = false;
  setUp(() {
    cancelled = false;
    failReturnCode = false;
    failCancel = false;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'ffmpegSession':
          return {'sessionId': ++nextId, 'createTime': 0};
        case 'getPlatform':
          return 'test';
        case 'getArch':
          return 'test';
        case 'isLTSBuild':
          return false;
        case 'getExternalLibraries':
          return <String>[];
        case 'cancelSession':
          if (failCancel) throw PlatformException(code: 'cancel_rejected');
          cancelled = true;
          return null;
        case 'abstractSessionGetReturnCode':
          if (failReturnCode) {
            throw PlatformException(code: 'broken_return_code');
          }
          return cancelled ? 255 : 0;
        default:
          return null;
      }
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  void finish(int id) {
    final callback = FFmpegKitFactory.getFFmpegSessionCompleteCallback(id)!;
    callback(
      AbstractSession.createFFmpegSessionFromMap({
        'sessionId': id,
        'command': '-test',
      }),
    );
  }

  test('cancellation waits for native completion before returning', () async {
    final run = await FfmpegRunner.run(['-test']);
    var finishedCancelling = false;
    final cancel = run.cancel().then((_) => finishedCancelling = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(cancelled, isTrue);
    expect(finishedCancelling, isFalse);
    finish(nextId);
    await cancel;
    expect(await run.success, isFalse);
  });

  test(
    'completion callback error resolves failure instead of hanging',
    () async {
      final run = await FfmpegRunner.run(['-test']);
      failReturnCode = true;
      finish(nextId);
      expect(await run.success.timeout(const Duration(seconds: 1)), isFalse);
      expect(MediaDiagnostics.recent.last.backend, MediaBackend.ffmpeg);
      expect(MediaDiagnostics.recent.last.code, MediaDiagnosticCode.exception);
    },
  );

  test('successful native completion resolves success', () async {
    final run = await FfmpegRunner.run(['-test']);
    finish(nextId);
    expect(await run.success, isTrue);
  });
  test('progress callbacks remain scoped to their own sessions', () async {
    final a = <int>[];
    final b = <int>[];
    final first = await FfmpegRunner.run(['-first'], onProgress: a.add);
    final firstId = nextId;
    final second = await FfmpegRunner.run(['-second'], onProgress: b.add);
    final secondId = nextId;
    FFmpegKitFactory.getStatisticsCallback(firstId)!(
      Statistics(firstId, 0, 0, 0, 0, 10, 0, 0),
    );
    FFmpegKitFactory.getStatisticsCallback(secondId)!(
      Statistics(secondId, 0, 0, 0, 0, 20, 0, 0),
    );
    expect(a, [10]);
    expect(b, [20]);
    finish(firstId);
    finish(secondId);
    expect(await first.success, isTrue);
    expect(await second.success, isTrue);
  });
  test(
    'failed cancellation still drains native work before reporting failure',
    () async {
      final run = await FfmpegRunner.run(['-test']);
      failCancel = true;
      var returned = false;
      final cancel = run.cancel().then<void>(
        (_) {
          returned = true;
          fail('cancellation failure must be reported');
        },
        onError: (Object error) {
          returned = true;
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(returned, isFalse);
      finish(nextId);
      await cancel;
      expect(returned, isTrue);
    },
  );
}
