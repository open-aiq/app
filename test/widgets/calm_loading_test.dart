import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:app/ble/connection_manager.dart';
import 'package:app/features/devices/device_list_screen.dart';
import 'package:app/services.dart';
import 'package:app/widgets/keep_last.dart';
import 'package:app/widgets/states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('KeepLast', () {
    test('keeps the last value when a refresh fails', () async {
      final loader = KeepLast<int>();
      expect(loader.isFirstLoad, isTrue);

      await loader.load(() async => 1);
      await loader.load(() async => throw Exception('offline'));

      expect(loader.data, 1);
      expect(loader.hasData, isTrue);
      expect(loader.error, isNotNull);
    });

    test('ignores a stale response that settles after a newer one', () async {
      final loader = KeepLast<String>();
      final slow = loader.load(
        () => Future.delayed(const Duration(milliseconds: 20), () => 'old'),
      );
      await loader.load(() async => 'new');
      await slow;

      expect(loader.data, 'new');
    });
  });

  testWidgets('skeleton holds still when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Skeleton(child: SkeletonBlock(width: 40, height: 10)),
        ),
      ),
    );

    final fade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(Skeleton),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('quiet note shows when data was last loaded and retries', (
    tester,
  ) async {
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuietNote(
            updatedAt: DateTime(2026, 1, 1, 10, 42),
            onRetry: () => retried++,
          ),
        ),
      ),
    );

    expect(find.textContaining("Couldn't refresh"), findsOneWidget);
    expect(find.textContaining('10:42'), findsOneWidget);
    await tester.tap(find.byType(QuietNote));
    expect(retried, 1);
  });

  testWidgets('device list keeps monitors on screen when a refresh fails', (
    tester,
  ) async {
    var online = true;
    final api = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      tokenProvider: () async => 'jwt',
      httpClient: MockClient((request) async {
        if (!online) throw http.ClientException('offline');
        if (request.url.path == '/api/v1/devices') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'c0ffee00-0000-4000-8000-000000000001',
                  'device_id': 'dev_1',
                  'name': 'Living room',
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'type': 'https://docs.air-iq.net/reference/errors/#no-readings',
            'status': 404,
          }),
          404,
        );
      }),
    );
    final ble = BleConnectionManager();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: AppServices(
            api: api,
            ble: ble,
            child: DeviceListScreen(onSignOut: () async {}),
          ),
        ),
      ),
    );
    expect(find.byType(Skeleton), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.text('Living room'), findsOneWidget);
    expect(find.byType(QuietNote), findsNothing);

    // The next periodic refresh fails: the monitor stays, with a quiet note.
    online = false;
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('Living room'), findsOneWidget);
    expect(find.byType(QuietNote), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // Dispose the screen so its refresh timer is cancelled.
    await tester.pumpWidget(const SizedBox());
    ble.dispose();
  });
}
