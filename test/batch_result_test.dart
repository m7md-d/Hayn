import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/core/isolates/media_task.dart';
import 'package:hayn/core/isolates/task_runner.dart';
import 'package:hayn/features/image_ops/data/image_compress_task.dart';
import 'package:hayn/features/image_ops/data/image_encoder.dart';
import 'package:hayn/features/settings/providers/preferences_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.fluttercandies/photo_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final asset = {
    'id': 'source',
    'type': 1,
    'width': 1,
    'height': 1,
    'title': 'sample.jpg',
  };
  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'fetchEntityProperties':
          return (call.arguments as Map)['id'] == 'source' ? asset : null;
        case 'getTitleAsync':
          return 'sample.jpg';
        case 'saveImage':
          return {...asset, 'id': 'saved'};
        default:
          return null;
      }
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final ids in [
    ['source'],
    ['source', 'missing'],
  ]) {
    test('batch result reflects all ${ids.length} requested inputs', () async {
      final task = ImageCompressTask(
        assetIds: ids,
        format: DefaultFormat.jpeg,
        quality: 80,
        keepMetadata: false,
        precomputedId: 'source',
        precomputed: EncodedImage(
          Uint8List.fromList([1, 2]),
          DefaultFormat.jpeg,
        ),
      );
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(taskRunnerProvider.notifier).enqueue(task);
      for (
        var i = 0;
        i < 200 &&
            c.read(taskRunnerProvider).single.status == TaskStatus.running;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final state = c.read(taskRunnerProvider).single;
      expect(
        state.status,
        ids.length == 1 ? TaskStatus.completed : TaskStatus.failed,
      );
      expect(task.outputAssetIds, ['saved']);
      if (ids.length > 1) {
        final error = state.error! as IncompleteBatch;
        expect(error.saved, 1);
        expect(error.total, 2);
      }
    });
  }
}
