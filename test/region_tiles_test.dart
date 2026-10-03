import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/features/image_ops/data/region_image.dart';
import 'package:hayn/features/image_ops/presentation/widgets/region_tiles.dart';

// PERF-03: the zoomed views decode the tiles in view only, at the coarsest
// level that still gives one image pixel per screen pixel, and nothing while
// the screen-sized rendition holds enough detail.

const _giant = Size(16128, 12096); // 195 MP, the RUN-01 sample

void main() {
  group('planTiles', () {
    TilePlan? plan(double scale, {Rect? visible}) => planTiles(
      image: _giant,
      box: const Size(400, 300),
      visible: visible ?? const Rect.fromLTWH(0, 0, 400, 300),
      screenPxPerLocal: scale * 3.5,
      baseLongEdge: 2048,
    );

    test('from afar the rendition is enough', () {
      // 1400 screen pixels across: 1/8 of the image (2016 px) fits the
      // 2048 px rendition.
      expect(plan(1), isNull);
    });

    test('zoomed, the tiles in view at the level the zoom needs', () {
      // ×2 on the centre: 2800 screen pixels across the whole image, so a
      // quarter of its 16128 is the coarsest level that covers them.
      final p = plan(2, visible: const Rect.fromLTRB(100, 75, 300, 225))!;
      expect(p.sample, 4);
      // The view is 4032..12096 × 3024..9072 image pixels; tiles span 2048.
      expect(p.tiles.map((t) => t.col).toSet(), {1, 2, 3, 4, 5});
      expect(p.tiles.map((t) => t.row).toSet(), {1, 2, 3, 4});
      expect(p.tiles, hasLength(20));
      // The centre first.
      expect((p.tiles.first.col, p.tiles.first.row), (3, 2));
      expect(p.tiles.first.rect, const Rect.fromLTWH(6144, 4096, 2048, 2048));
    });

    test('fully zoomed, full-size pixels; edge tiles stop at the image', () {
      final p = plan(16, visible: const Rect.fromLTRB(380, 280, 400, 300))!;
      expect(p.sample, 1);
      final last = p.tiles.reduce(
        (a, b) => a.col >= b.col && a.row >= b.row ? a : b,
      );
      expect(last.rect.right, _giant.width);
      expect(last.rect.bottom, _giant.height);
      expect(last.rect.width, _giant.width - 31 * 512);
      for (final t in p.tiles) {
        expect(
          t.rect.overlaps(const Rect.fromLTRB(15321.6, 11289.6, 16128, 12096)),
          isTrue,
        );
      }
    });

    test('a 12 MP photo needs tiles only past the rendition', () {
      TilePlan? small(double scale) => planTiles(
        image: const Size(4032, 3024),
        box: const Size(400, 300),
        visible: const Rect.fromLTWH(0, 0, 400, 300),
        screenPxPerLocal: scale * 3.5,
        baseLongEdge: 2048,
      );
      expect(small(1), isNull);
      expect(small(2)!.sample, 1);
    });
  });

  group('RegionTiles', () {
    late List<Map<Object?, Object?>> asked;

    setUp(() {
      asked = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(RegionImage.channel, (call) async {
            if (call.method == 'tiles') {
              asked.add(call.arguments as Map<Object?, Object?>);
            }
            return null; // a failed tile: the rendition stays
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(RegionImage.channel, null);
    });

    Future<TransformationController> pumpViewer(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ctrl = TransformationController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: InteractiveViewer(
            transformationController: ctrl,
            maxScale: 64,
            child: SizedBox(
              width: 400,
              height: 300,
              child: RegionTiles(
                region: RegionImage.forTest(7, 4000, 3000),
                transform: ctrl,
                baseLongEdge: 1000,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return ctrl;
    }

    testWidgets('asks nothing from afar', (tester) async {
      await pumpViewer(tester);
      expect(asked, isEmpty);
    });

    testWidgets('zoomed, asks for the tiles in view only', (tester) async {
      final ctrl = await pumpViewer(tester);
      // ×8 on the top-left corner: 50×37.5 logical pixels in view, that is
      // 500×375 image pixels at full size (10 image pixels per logical one).
      ctrl.value = Matrix4.diagonal3Values(8, 8, 1);
      await tester.pump();
      await tester.pump();
      expect(asked, isNotEmpty);
      for (final call in asked) {
        expect(call['id'], 7);
        expect(call['sample'], 1);
        final r = call['rect'] as List<int>;
        expect(r[0], lessThan(500), reason: '$r is out of view');
        expect(r[1], lessThan(375), reason: '$r is out of view');
      }
      // One tile covers the view; never the whole image.
      final rects = asked.map((c) => (c['rect'] as List<int>).toList());
      expect(rects, contains(orderedEquals([0, 0, 512, 512])));
      expect(asked.length, lessThan(3));
    });
  });
}
