import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Guards the iOS asset-open fix: PhotoKit ids contain slashes
// (`UUID/L0/001`). They must survive a push to `/asset/:id` without being
// read as extra path segments. The contract we rely on: encode at push,
// go_router decodes the param back to the original id.

void main() {
  testWidgets('an iOS-style asset id with slashes round-trips through /asset/:id',
      (tester) async {
    String? receivedId;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox.shrink()),
        GoRoute(
          path: '/asset/:id',
          builder: (_, state) {
            receivedId = state.pathParameters['id'];
            return const SizedBox.shrink();
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    const iosId = '2C48646E-3B5B-4E24-B03E-F880A2C6B74D/L0/001';
    router.push('/asset/${Uri.encodeComponent(iosId)}');
    await tester.pumpAndSettle();

    expect(receivedId, iosId);
  });

  testWidgets('a plain Android numeric id is unaffected by encoding',
      (tester) async {
    String? receivedId;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox.shrink()),
        GoRoute(
          path: '/asset/:id',
          builder: (_, state) {
            receivedId = state.pathParameters['id'];
            return const SizedBox.shrink();
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    const androidId = '1000000123';
    router.push('/asset/${Uri.encodeComponent(androidId)}');
    await tester.pumpAndSettle();

    expect(receivedId, androidId);
  });
}
