import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/account/account.dart';
import 'package:app/gallery/gallery_app.dart';

/// Text that shows once each `?screen=` home has loaded its mock data.
const _screens = {
  'gallery': 'Monitor card',
  'monitors': 'Ridge lookout',
  'monitor': 'Good',
  'monitor-new': 'New sensor',
  'monitor-logs': 'Uploaded 6 readings',
  'monitor-settings': 'dev_garden000000a1b2c3d4e5f6',
  'settings': 'Manage account',
  'account': 'Sign-in methods',
};

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

  test('every screen key has a check', () {
    expect(_screens.keys, unorderedEquals(galleryScreens));
  });

  for (final MapEntry(key: screen, value: text) in _screens.entries) {
    testWidgets('?screen=$screen opens on mock data', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: GalleryApp(themeMode: ThemeMode.light, screen: screen),
        ),
      );
      // Monitors load first, then each card's reading: two mock round trips.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 350));
      }

      expect(tester.takeException(), isNull);
      expect(find.text(text), findsWidgets);

      // Let requests still in flight finish before the next test.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('an unknown screen key opens the gallery', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: GalleryApp(themeMode: ThemeMode.light, screen: 'nope'),
      ),
    );
    await tester.pump();
    expect(find.text('Gallery'), findsOneWidget);
  });

  testWidgets('monitor settings copies the device ID', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: GalleryApp(
          themeMode: ThemeMode.light,
          screen: 'monitor-settings',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.byTooltip('Copy device ID'));
    await tester.pump();
    expect(copied, 'dev_garden000000a1b2c3d4e5f6');
    expect(find.text('Device ID copied'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
