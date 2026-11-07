import 'dart:async';
import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:app/api/models.dart';
import 'package:app/ble/connection_manager.dart';
import 'package:app/features/device_detail/device_detail_screen.dart';
import 'package:app/features/devices/device_list_screen.dart';
import 'package:app/widgets/soft_card.dart';
import 'package:app/services.dart';
import 'package:app/theme.dart';
import 'package:app/widgets/monitor_illustration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _device = {
  'id': 'c0ffee00-0000-4000-8000-000000000001',
  'device_id': 'dev_1',
  'name': 'Living room',
  'ota': {'status': 'update_available', 'version': '0.4.0'},
};

ApiClient _api() => ApiClient(
  baseUrl: 'https://api.test/api/v1',
  tokenProvider: () async => 'jwt',
  httpClient: MockClient((request) async {
    if (request.url.path.endsWith('/logs')) {
      return http.Response(jsonEncode({'data': []}), 200);
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

void main() {
  testWidgets('monitor sections live in a bottom bar, not swipeable tabs', (
    tester,
  ) async {
    final ble = BleConnectionManager();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: AppServices(
            api: _api(),
            ble: ble,
            child: DeviceDetailScreen(device: Device.fromJson(_device)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(TabBarView), findsNothing);
    for (final label in ['Overview', 'Live', 'Logs', 'Updates', 'Settings']) {
      expect(find.text(label), findsOneWidget);
    }
    // A pending update shows a dot on the Updates tab.
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byType(Badge),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    expect(find.text('No log entries'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    ble.dispose();
  });

  testWidgets('monitor illustration holds still under reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const Center(child: MonitorIllustration()),
        ),
      ),
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('history loads every range at once; switching makes no request', (
    tester,
  ) async {
    final ranges = <String>[];
    final api = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      tokenProvider: () async => 'jwt',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/historical')) {
          ranges.add(request.url.queryParameters['timeline'] ?? '');
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return http.Response('{"status":404}', 404);
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
            child: DeviceDetailScreen(device: Device.fromJson(_device)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(ranges.toSet(), {'daily', 'weekly', 'monthly', 'yearly'});

    final before = ranges.length;
    await tester.tap(find.text('7 d'));
    await tester.pumpAndSettle();
    expect(ranges.length, before);

    await tester.pumpWidget(const SizedBox());
    ble.dispose();
  });

  testWidgets('a home card is the same size loading and loaded', (
    tester,
  ) async {
    final reading = Completer<http.Response>();
    final api = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      tokenProvider: () async => 'jwt',
      httpClient: MockClient((request) {
        if (request.url.path == '/api/v1/devices') {
          return Future.value(
            http.Response(
              jsonEncode({
                'data': [_device],
              }),
              200,
            ),
          );
        }
        return reading.future;
      }),
    );
    final ble = BleConnectionManager();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: AppServices(
            api: api,
            ble: ble,
            child: const DeviceListScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final loading = tester.getSize(find.byType(SoftCard));

    reading.complete(
      http.Response(
        jsonEncode({
          'data': {
            'status': 'online',
            'last_seen': DateTime.now().toUtc().toIso8601String(),
            'sample_count': 6,
            'aqi': 128,
            'pm2_5': 46.2,
            'temperature': 31.0,
          },
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('128'), findsOneWidget);
    expect(tester.getSize(find.byType(SoftCard)), loading);

    await tester.pumpWidget(const SizedBox());
    ble.dispose();
  });
}
