import 'dart:async';
import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:app/api/models.dart';
import 'package:app/ble/connection_manager.dart';
import 'package:app/features/firmware/firmware_screen.dart';
import 'package:app/features/settings/device_settings_screen.dart';
import 'package:app/services.dart';
import 'package:app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _device = {
  'id': 'c0ffee00-0000-4000-8000-000000000001',
  'device_id': 'dev_1',
  'name': 'Living room',
};

http.Response _json(Object body) => http.Response(jsonEncode(body), 200);

/// A backend that answers reads but can't be reached for anything that
/// changes data, the way a phone that dropped offline behaves. [job] is the
/// update already in progress, if any.
ApiClient _offlineForWrites({Map<String, Object?>? job}) => ApiClient(
  baseUrl: 'https://api.test/api/v1',
  tokenProvider: () async => 'jwt',
  httpClient: MockClient((request) async {
    if (request.method != 'GET') {
      throw http.ClientException('Failed host lookup', request.url);
    }
    if (request.url.path.endsWith('/ota')) {
      return _json({
        'data': {
          'current_version': '0.3.0',
          if (job == null)
            'available': {
              'id': 'rel_1',
              'version': '0.4.0',
              'size': 1048576,
              'notes': '',
            },
          'job': ?job,
        },
      });
    }
    return http.Response('{"status":404}', 404);
  }),
);

Future<BleConnectionManager> _pump(
  WidgetTester tester,
  ApiClient api,
  Widget child,
) async {
  // Tall enough that the whole settings list is built.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final ble = BleConnectionManager();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: AppServices(
        api: api,
        ble: ble,
        child: Scaffold(body: child),
      ),
    ),
  );
  // Not pumpAndSettle: a pending update shows a progress bar that never rests.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return ble;
}

Future<void> _close(WidgetTester tester, BleConnectionManager ble) async {
  // Unmount first, so the firmware section's poll timer stops.
  await tester.pumpWidget(const SizedBox());
  ble.dispose();
}

void main() {
  test('friendlyError words network failures and keeps API messages', () {
    expect(
      friendlyError(http.ClientException('Failed host lookup')),
      unreachableMessage,
    );
    expect(friendlyError(TimeoutException('slow')), unreachableMessage);
    expect(
      friendlyError(ApiException(409, detail: 'Already approved.')),
      'Already approved.',
    );
    expect(
      friendlyError(StateError('boom'), fallback: 'Try again.'),
      'Try again.',
    );
    expect(friendlyError(StateError('boom')), isNot(contains('boom')));
  });

  testWidgets('saving settings offline says the server is out of reach', (
    tester,
  ) async {
    var changed = false;
    final ble = await _pump(
      tester,
      _offlineForWrites(),
      DeviceSettingsView(
        device: Device.fromJson(_device),
        onChanged: (_) => changed = true,
        onDeleted: () {},
      ),
    );

    await tester.enterText(find.byType(TextField), 'Kitchen');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text(unreachableMessage), findsOneWidget);
    expect(changed, isFalse);
    // Still editable, so the change can be saved once back online.
    expect(find.text('Save changes'), findsOneWidget);

    await _close(tester, ble);
  });

  testWidgets('deleting a monitor offline keeps it and says why', (
    tester,
  ) async {
    var deleted = false;
    final ble = await _pump(
      tester,
      _offlineForWrites(),
      DeviceSettingsView(
        device: Device.fromJson(_device),
        onChanged: (_) {},
        onDeleted: () => deleted = true,
      ),
    );

    await tester.tap(find.text('Delete monitor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Living room',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text(unreachableMessage), findsOneWidget);
    expect(deleted, isFalse);

    await _close(tester, ble);
  });

  testWidgets('approving an update offline says the server is out of reach', (
    tester,
  ) async {
    final ble = await _pump(
      tester,
      _offlineForWrites(),
      SingleChildScrollView(
        child: FirmwareSection(device: Device.fromJson(_device)),
      ),
    );

    await tester.tap(find.text('Install update'));
    await tester.pumpAndSettle();
    // The confirmation dialog's button carries the same label.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Install update'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(unreachableMessage), findsOneWidget);
    // The button is usable again for another try.
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Install update'),
              matching: find.bySubtype<FilledButton>(),
            ),
          )
          .onPressed,
      isNotNull,
    );

    await _close(tester, ble);
  });

  testWidgets('cancelling an update offline says the server is out of reach', (
    tester,
  ) async {
    final ble = await _pump(
      tester,
      _offlineForWrites(
        job: {
          'id': 'job_1',
          'version': '0.4.0',
          'status': 'approved',
          'progress': 0,
        },
      ),
      SingleChildScrollView(
        child: FirmwareSection(device: Device.fromJson(_device)),
      ),
    );

    await tester.tap(find.text('Cancel update'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(unreachableMessage), findsOneWidget);

    await _close(tester, ble);
  });
}
