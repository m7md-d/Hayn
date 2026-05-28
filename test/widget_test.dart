import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/app/app.dart';

void main() {
  testWidgets('App renders without crash', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: HaynApp()));
    await tester.pumpAndSettle();
    expect(find.byType(ProviderScope), findsOneWidget);
  });
}
