import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hayn/app/l10n/app_localizations.dart';
import 'package:hayn/app/theme/app_theme.dart';
import 'package:hayn/features/library/presentation/widgets/asset_metadata_sheet.dart';
import 'package:hayn/shared/widgets/sheets.dart';
import 'package:photo_manager/photo_manager.dart';

// Sheet layout from the viewer's details (2026-09-30, iPhone screenshots): the
// modal's handle floated above the surface with the header flush against its
// top edge; the pull-up sheet opened a status-bar-high gap; and the file name
// and date must read from the left in Arabic too.
void main() {
  Widget host(Widget child, {EdgeInsets padding = EdgeInsets.zero}) =>
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MediaQuery(
          data: MediaQueryData(size: const Size(390, 844), padding: padding),
          child: Scaffold(body: child),
        ),
      );

  testWidgets('the handle is drawn inside the sheet surface', (tester) async {
    await tester.pumpWidget(host(Builder(
      builder: (context) => TextButton(
        onPressed: () => showHaynSheet<void>(
          context: context,
          builder: (_) => const HaynSheetHeader(title: 'Title'),
        ),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final surface = tester.getRect(find
        .ancestor(
          of: find.byType(HaynSheetHandle),
          matching: find.byType(DecoratedBox),
        )
        .first);
    final handle = tester.getRect(find.byType(HaynSheetHandle));
    final title = tester.getRect(find.text('Title'));
    expect(handle.top, surface.top, reason: 'handle above the surface');
    expect(title.top, greaterThan(handle.bottom));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isFalse);
  });

  testWidgets('alignLeft pins the title and subtitle left in RTL',
      (tester) async {
    await tester.pumpWidget(host(const Column(children: [
      HaynSheetHeader(title: 'IMG_1309.JPG', subtitle: 'sub', alignLeft: true),
      HaynSheetHeader(title: 'right', subtitle: 'sub2'),
    ])));
    // The header's own left inset is AppSpacing.md (16).
    expect(tester.getRect(find.text('IMG_1309.JPG')).left, 16);
    expect(tester.getRect(find.text('sub')).left, 16);
    // Without it the header keeps following the language (right in Arabic).
    expect(tester.getRect(find.text('right')).left, greaterThan(200));
  });

  testWidgets('details sheet adds no top inset under a status bar',
      (tester) async {
    final asset = AssetEntity(
      id: 'asset-1',
      typeInt: AssetType.image.index,
      width: 1118,
      height: 1280,
    );
    await tester.pumpWidget(host(
      Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(height: 420, child: AssetMetadataSheet(asset: asset)),
      ),
      padding: const EdgeInsets.only(top: 47, bottom: 34),
    ));
    await tester.pump();

    final sheetTop = tester.getRect(find.byType(AssetMetadataSheet)).top;
    final titleTop = tester.getRect(find.text('asset-1')).top;
    expect(titleTop - sheetTop, lessThan(20));
    expect(tester.getRect(find.text('asset-1')).left, 16);
  });
}
