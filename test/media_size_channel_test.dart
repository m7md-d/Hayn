import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/data/index/media_size_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(MediaSizeChannel.channel, null);
  });

  test('returns id → size map from the native side', () async {
    messenger.setMockMethodCallHandler(MediaSizeChannel.channel, (call) async {
      expect(call.method, 'getSizes');
      final ids = ((call.arguments as Map)['ids'] as List).cast<String>();
      return {for (final id in ids) id: id.length * 10};
    });

    final sizes = await MediaSizeChannel.getSizes(['a', 'bb', 'ccc']);
    expect(sizes, {'a': 10, 'bb': 20, 'ccc': 30});
  });

  test('omits ids the platform could not resolve', () async {
    messenger.setMockMethodCallHandler(MediaSizeChannel.channel, (call) async {
      return {'a': 100}; // 'b' deliberately absent
    });

    final sizes = await MediaSizeChannel.getSizes(['a', 'b']);
    expect(sizes, {'a': 100});
  });

  test('empty input never hits the channel', () async {
    var called = false;
    messenger.setMockMethodCallHandler(MediaSizeChannel.channel, (call) async {
      called = true;
      return <String, int>{};
    });

    expect(await MediaSizeChannel.getSizes([]), isEmpty);
    expect(called, isFalse);
  });

  test('a missing native plugin yields an empty map (no throw)', () async {
    // No handler registered → MissingPluginException under the hood.
    messenger.setMockMethodCallHandler(MediaSizeChannel.channel, null);
    expect(await MediaSizeChannel.getSizes(['x']), isEmpty);
  });

  test('a native error yields an empty map (no throw)', () async {
    messenger.setMockMethodCallHandler(MediaSizeChannel.channel, (call) async {
      throw PlatformException(code: 'boom');
    });
    expect(await MediaSizeChannel.getSizes(['x']), isEmpty);
  });

  test('coerces numeric (non-int) sizes and drops negatives', () async {
    messenger.setMockMethodCallHandler(MediaSizeChannel.channel, (call) async {
      return {'a': 12.0, 'b': -5, 'c': 7};
    });
    final sizes = await MediaSizeChannel.getSizes(['a', 'b', 'c']);
    expect(sizes, {'a': 12, 'c': 7}); // b dropped (negative)
  });
}
