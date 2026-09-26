import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/app/shell/swipeable_tabs.dart';

// A tab tap animates the PageView across every page in between. Those
// intermediate pages must not be reported back as page changes — otherwise the
// shell switches branch mid-sweep and the nav bar bounces through the middle
// tab (Settings → Tools → Library).
void main() {
  /// Hosts the tabs the way the shell does: a report becomes the new
  /// currentIndex (goBranch), and a tab tap sets it from outside.
  Future<ValueNotifier<int>> pumpHost(
      WidgetTester tester, int initial, List<int> reported) async {
    final index = ValueNotifier(initial);
    addTearDown(index.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<int>(
        valueListenable: index,
        builder: (_, current, __) => SwipeableTabs(
          currentIndex: current,
          onPageChanged: (page) {
            reported.add(page);
            index.value = page;
          },
          children: [for (var i = 0; i < 3; i++) Center(child: Text('page $i'))],
        ),
      ),
    ));
    return index;
  }

  PageController controller(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!;

  testWidgets('a tab jump does not report the pages it sweeps past',
      (tester) async {
    final reported = <int>[];
    final index = await pumpHost(tester, 2, reported);
    index.value = 0;
    await tester.pumpAndSettle();

    expect(controller(tester).page, 0);
    expect(reported, isEmpty);
  });

  testWidgets('a user swipe still reports the new page', (tester) async {
    final reported = <int>[];
    await pumpHost(tester, 0, reported);
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(controller(tester).page, 1);
    expect(reported, [1]);
  });

  testWidgets('a drag that interrupts a tab jump reports where it lands',
      (tester) async {
    final reported = <int>[];
    final index = await pumpHost(tester, 2, reported);
    index.value = 0;
    // Mid-sweep: step until the jump is past page 1's midpoint but still
    // closer to 1 than to 0.
    await tester.pump();
    while (controller(tester).page! > 1.3) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(PageView)));
    await gesture.moveBy(const Offset(4, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller(tester).page, 1);
    expect(reported, [1]);
    expect(index.value, 1);
  });
}
