import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/account/account.dart';
import 'package:app/gallery/gallery_app.dart';

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('gallery renders every section in ${mode.name} mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 8000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: GalleryApp(themeMode: mode),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Monitor card'), findsOneWidget);
      expect(find.text('Inside the monitor'), findsOneWidget);
      expect(find.text('AQI bands'), findsOneWidget);
      expect(find.text('States'), findsOneWidget);
      expect(find.text('Back garden'), findsOneWidget);
    });
  }

  testWidgets('the avatar menu switches the theme and stays open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: GalleryApp(themeMode: ThemeMode.light),
      ),
    );
    await tester.tap(find.byTooltip('Account and settings'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Riley Review'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Docs'), findsOneWidget);
    expect(find.text('Public map'), findsOneWidget);

    await tester.tap(find.byTooltip('Dark'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(themeModePreference.value, ThemeMode.dark);
    expect(find.text('Sign out'), findsOneWidget);
  });
}
