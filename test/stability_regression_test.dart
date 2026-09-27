import 'dart:async';
import 'support/encoded_headers.dart';

import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/core/isolates/media_task.dart';
import 'package:hayn/core/isolates/task_progress.dart';
import 'package:hayn/core/isolates/task_runner.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';
import 'package:hayn/features/video_ops/data/animate_gif_task.dart';
import 'package:hayn/features/video_ops/data/extract_frames_task.dart';
import 'package:hayn/features/video_ops/data/remove_audio_task.dart';

class _RejectingEncoder extends FlutterImageCompressPlatform {
  final calls = <CompressFormat>[];
  bool rejectAll = false;
  bool empty = false;

  @override
  Future<Uint8List> compressWithList(
    Uint8List image, {
    int minWidth = 1920,
    int minHeight = 1080,
    int quality = 95,
    int rotate = 0,
    int inSampleSize = 1,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
  }) async {
    calls.add(format);
    if (empty) return Uint8List(0);
    if (rejectAll || format == CompressFormat.jpeg) {
      throw PlatformException(code: 'encode_failure');
    }
    return encodedHeader(DefaultFormat.webp);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BlockingTask extends MediaTask {
  final gate = Completer<void>();
  final entered = Completer<void>();
  bool cancellationDelivered = false;
  int cleanupCalls = 0;

  @override
  String get id => 'blocked';
  @override
  TaskType get type => TaskType.dummy;
  @override
  Stream<TaskProgress> run() async* {
    yield const TaskProgress(progress: 0, phase: 'process');
    entered.complete();
    await gate.future;
    yield const TaskProgress(progress: 1, phase: 'done');
  }

  @override
  Future<void> cancel() async {
    cancellationDelivered = true;
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Future<void> cleanup() async => cleanupCalls++;
}

class _SynchronousFailure extends _BlockingTask {
  @override
  Stream<TaskProgress> run() => throw StateError('cannot start');
}

class _PrematureClose extends _BlockingTask {
  @override
  Stream<TaskProgress> run() async* {
    yield const TaskProgress(progress: 0.2, phase: 'working');
  }
}

Future<TaskState> _settle(ProviderContainer container) async {
  for (var i = 0; i < 200; i++) {
    final state = container.read(taskRunnerProvider).single;
    if (state.status != TaskStatus.running &&
        state.status != TaskStatus.pending) {
      return state;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('task never settled');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('async encoder rejection reaches the next format', () async {
    final old = FlutterImageCompressPlatform.instance;
    final fake = _RejectingEncoder();
    FlutterImageCompressPlatform.instance = fake;
    addTearDown(() => FlutterImageCompressPlatform.instance = old);
    final encoded = await ImageEncoder.encode(
      source: Uint8List.fromList([1, 2, 3]),
      target: DefaultFormat.jpeg,
      allowFormatFallback: true,
      quality: 80,
      hasAlpha: false,
      keepMetadata: false,
    );
    expect(encoded.format, DefaultFormat.webp);
    expect(encoded.requestedFormat, DefaultFormat.jpeg);
    expect(encoded.backend, MediaBackend.imageCompress);
    expect(
      encoded.diagnostics.any(
        (e) =>
            e.backend == MediaBackend.imageCompress &&
            e.code == MediaDiagnosticCode.exception,
      ),
      isTrue,
    );
    expect(
      encoded.diagnostics.any(
        (e) => e.code == MediaDiagnosticCode.formatFallback,
      ),
      isTrue,
    );
    expect(fake.calls, [CompressFormat.jpeg, CompressFormat.webp]);
  });

  for (final empty in [false, true]) {
    test(
      'all encoders ${empty ? 'empty' : 'reject'}: explicit failure with diagnostics',
      () async {
        final old = FlutterImageCompressPlatform.instance;
        final fake = _RejectingEncoder()
          ..rejectAll = true
          ..empty = empty;
        FlutterImageCompressPlatform.instance = fake;
        addTearDown(() => FlutterImageCompressPlatform.instance = old);
        await expectLater(
          ImageEncoder.encode(
            source: Uint8List(3),
            target: DefaultFormat.jpeg,
            allowFormatFallback: true,
            quality: 80,
            hasAlpha: false,
            keepMetadata: false,
          ),
          throwsA(
            isA<ImageEncodingFailure>().having(
              (e) => e.diagnostics.any(
                (d) =>
                    d.backend == MediaBackend.imageCompress &&
                    d.code ==
                        (empty
                            ? MediaDiagnosticCode.emptyOutput
                            : MediaDiagnosticCode.exception),
              ),
              'original failure retained',
              isTrue,
            ),
          ),
        );
        expect(fake.calls, [
          CompressFormat.jpeg,
          CompressFormat.webp,
          CompressFormat.png,
        ]);
      },
    );
  }

  for (final task in <MediaTask>[
    RemoveAudioTask(assetId: 'missing'),
    ExtractFramesTask(assetId: 'missing', mode: FrameMode.single),
    AnimateGifFromVideoTask(
      assetId: 'missing',
      startSeconds: 0,
      endSeconds: 1,
      fps: 10,
      height: 120,
    ),
  ]) {
    test('${task.type.name}: unavailable video fails', () async {
      const channel = MethodChannel('com.fluttercandies/photo_manager');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(taskRunnerProvider.notifier).enqueue(task);
      expect((await _settle(container)).status, TaskStatus.failed);
      expect(task.outputAssetIds, isEmpty);
    });
  }

  test('cancel reaches producer before waiting for stream shutdown', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final task = _BlockingTask();
    final runner = container.read(taskRunnerProvider.notifier);
    await runner.enqueue(task);
    await task.entered.future;
    final cancelling = runner.cancel(task.id);
    await Future<void>.delayed(Duration.zero);
    final deliveredBeforeCompletion = task.cancellationDelivered;
    if (!task.gate.isCompleted) task.gate.complete();
    await cancelling;
    expect(deliveredBeforeCompletion, isTrue);
    expect(
      container.read(taskRunnerProvider).single.status,
      TaskStatus.cancelled,
    );
    expect(task.cleanupCalls, 1);
  });

  test('synchronous launch failure is recorded and cleaned up', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final task = _SynchronousFailure();
    await container.read(taskRunnerProvider.notifier).enqueue(task);
    expect((await _settle(container)).status, TaskStatus.failed);
    await Future<void>.delayed(Duration.zero);
    expect(task.cleanupCalls, 1);
  });

  test('stream closure without a success result is a failure', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(taskRunnerProvider.notifier)
        .enqueue(_PrematureClose());
    expect((await _settle(container)).status, TaskStatus.failed);
  });
}
