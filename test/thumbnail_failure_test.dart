import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:hayn/core/diagnostics/media_diagnostics.dart';
import 'package:hayn/features/library/presentation/providers/thumbnail_cache.dart';
import 'package:hayn/features/library/presentation/providers/asset_entity_cache.dart';
import 'package:hayn/features/library/presentation/widgets/id_thumbnail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.fluttercandies/photo_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final asset = AssetEntity(id: 'synthetic', typeInt: 1, width: 16, height: 12);
  setUp(ThumbnailCache.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'late native thumbnail failure is diagnosed and remains retryable',
    () async {
      final reply = Completer<Uint8List?>();
      messenger.setMockMethodCallHandler(channel, (call) {
        expect(call.method, 'getThumb');
        return reply.future;
      });
      final attempt = MediaDiagnostics.trace((trace) async {
        expect(await ThumbnailCache.load(asset), isNull);
        return trace.events;
      });
      await Future<void>.delayed(Duration.zero);
      reply.completeError(PlatformException(code: 'thumbnail_failed'));
      final events = await attempt;
      expect(events.map((e) => e.toString()), ['gallery.thumbnail.exception']);
      expect(ThumbnailCache.get(asset.id), isNull);
      var calls = 0;
      final bytes = Uint8List.fromList([1, 2, 3]);
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return bytes;
      });
      expect(await ThumbnailCache.load(asset), bytes);
      expect(await ThumbnailCache.load(asset), bytes);
      expect(calls, 1);
    },
  );

  for (final output in <Uint8List?>[null, Uint8List(0)]) {
    test(
      'empty thumbnail is diagnosed and never cached: ${output == null ? 'null' : 'bytes'}',
      () async {
        messenger.setMockMethodCallHandler(channel, (_) async => output);
        final events = await MediaDiagnostics.trace((trace) async {
          expect(await ThumbnailCache.load(asset), isNull);
          return trace.events;
        });
        expect(events.map((e) => e.toString()), [
          'gallery.thumbnail.emptyOutput',
        ]);
        expect(ThumbnailCache.get(asset.id), isNull);
      },
    );
  }
  test('cancel before fetch avoids the platform call and warning', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('Cancelled fetch reached native'),
    );
    final events = await MediaDiagnostics.trace((trace) async {
      expect(await ThumbnailCache.load(asset, cancelled: () => true), isNull);
      return trace.events;
    });
    expect(events, isEmpty);
  });
  test('missing native thumbnail service is classified', () async {
    final events = await MediaDiagnostics.trace((trace) async {
      expect(await ThumbnailCache.load(asset), isNull);
      return trace.events;
    });
    expect(events.map((e) => e.toString()), ['gallery.thumbnail.unavailable']);
  });
  testWidgets(
    'native rejection leaves the tile placeholder without an unhandled error',
    (tester) async {
      AssetEntityCache.put(asset.id, asset);
      messenger.setMockMethodCallHandler(channel, (_) async {
        await Future<void>.delayed(Duration.zero);
        throw PlatformException(code: 'thumbnail_failed');
      });
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: IdThumbnail(id: asset.id),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ColoredBox), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      AssetEntityCache.clear();
    },
  );
}
