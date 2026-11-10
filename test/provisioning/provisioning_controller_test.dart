import 'dart:async';
import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:app/ble/protocol.dart';
import 'package:app/features/provisioning/provisioning_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_device.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// Fake backend: one optional existing device; `current` is NoReadings until
/// [onlineAfter] polls. The first [unreachableFor] polls never reach it: they
/// fail the way a phone without a connection does.
class FakeBackend {
  FakeBackend({
    this.existingDeviceId,
    this.onlineAfter = 1,
    this.unreachableFor = 0,
  });

  final String? existingDeviceId;
  final int onlineAfter;
  final int unreachableFor;
  int currentCalls = 0;
  int registered = 0;

  ApiClient client() => ApiClient(
    baseUrl: 'https://api.test/api/v1',
    tokenProvider: () async => 'jwt',
    httpClient: MockClient((request) async {
      final route = '${request.method} ${request.url.path}';
      switch (route) {
        case 'GET /api/v1/devices':
          return _json({
            'data': [
              if (existingDeviceId != null)
                {
                  'id': 'uuid-existing',
                  'device_id': existingDeviceId,
                  'name': 'Kitchen',
                },
            ],
          });
        case 'POST /api/v1/devices':
          registered++;
          return _json({
            'data': {
              'id': 'uuid-new',
              'device_id': 'dev_new',
              'name': 'Balcony',
              'device_key': 'sk_new',
            },
          }, 201);
        case 'POST /api/v1/devices/uuid-new/rotate-key':
          return _json({
            'data': {
              'id': 'uuid-new',
              'device_id': 'dev_new',
              'name': 'Balcony',
              'device_key': 'sk_rotated',
            },
          });
      }
      if (route.endsWith('/current')) {
        currentCalls++;
        if (currentCalls <= unreachableFor) {
          // Alternate the two errors a dead connection produces.
          if (currentCalls.isOdd) {
            throw http.ClientException('Failed host lookup', request.url);
          }
          throw TimeoutException('No response from the server');
        }
        if (currentCalls < onlineAfter) {
          return _json({
            'type': 'https://docs.air-iq.net/reference/errors/#no-readings',
            'status': 404,
          }, 404);
        }
        return _json({
          'data': {'status': 'online', 'sample_count': 1, 'aqi': 40},
        });
      }
      return _json({'status': 404}, 404);
    }),
  );
}

ProvisioningController _controller(
  FakeDevice device,
  FakeBackend backend, {
  Duration verifyTimeout = const Duration(milliseconds: 300),
}) => ProvisioningController(
  session: AiqSession(device),
  api: backend.client(),
  pollInterval: const Duration(milliseconds: 5),
  verifyTimeout: verifyTimeout,
);

void main() {
  test(
    'registers a new device, sends WiFi and location, then sees it online',
    () async {
      final device = FakeDevice();
      final backend = FakeBackend(onlineAfter: 3);
      final controller = _controller(device, backend);

      await controller.start();
      expect(controller.step, ProvisioningStep.register);
      expect(controller.registeredElsewhere, isFalse);

      await controller.register(name: 'Balcony', isOutdoor: true);
      expect(controller.error, isNull);
      expect(controller.step, ProvisioningStep.wifi);
      expect(device.deviceId, 'dev_new');
      expect(device.deviceKey, 'sk_new');

      await controller.scanWifi();
      expect(controller.networks.first.ssid, 'Home, Upstairs');

      await controller.submitWifi('Home, Upstairs', 'secret');
      expect(controller.step, ProvisioningStep.location);

      await controller.submitLocation(lat: 24.86, lon: 67.0);
      expect(controller.step, ProvisioningStep.done);
      expect(controller.ip, '192.168.1.20');
      expect(device.saved['devkey'], 'sk_new');
      expect(device.lat, 24.86);
      expect(backend.currentCalls, 3);
    },
  );

  test('skips registration for a device already in the account', () async {
    final device = FakeDevice()
      ..deviceId = 'dev_kitchen'
      ..deviceKey = 'sk_old';
    final backend = FakeBackend(existingDeviceId: 'dev_kitchen');
    final controller = _controller(device, backend);

    await controller.start();
    expect(controller.step, ProvisioningStep.wifi);
    expect(controller.device!.name, 'Kitchen');
    expect(backend.registered, 0);
    expect(
      device.received.where((line) => line.startsWith('DEVKEY')),
      isEmpty,
      reason: 'existing credentials are kept',
    );
  });

  test('flags a device registered to another account', () async {
    final device = FakeDevice()
      ..deviceId = 'dev_foreign'
      ..deviceKey = 'sk_x';
    final controller = _controller(device, FakeBackend());
    await controller.start();
    expect(controller.step, ProvisioningStep.register);
    expect(controller.registeredElsewhere, isTrue);
  });

  test('returns to the WiFi step when the device cannot join', () async {
    final device = FakeDevice()..wifiJoins = false;
    final controller = _controller(device, FakeBackend());
    await controller.start();
    await controller.register(name: 'Balcony');
    await controller.submitWifi('Home', 'wrong');
    await controller.submitLocation();
    expect(controller.step, ProvisioningStep.wifi);
    expect(controller.error, contains('could not join'));
    expect(
      device.received.where((line) => line.startsWith('LAT')),
      isEmpty,
      reason: 'skipped location',
    );
  });

  test('reports a timeout and can resend a rotated key', () async {
    final device = FakeDevice();
    final backend = FakeBackend(onlineAfter: 1000);
    final controller = _controller(device, backend);
    await controller.start();
    await controller.register(name: 'Balcony');
    await controller.submitWifi('Home', 'pw');
    await controller.submitLocation();
    expect(controller.step, ProvisioningStep.verifying);
    expect(controller.verifyTimedOut, isTrue);
    expect(
      controller.verifyElapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 300)),
    );

    await controller.rotateAndResendKey();
    expect(controller.error, isNull);
    expect(device.saved['devkey'], 'sk_rotated');
  });

  test(
    'keeps polling through network errors until the reading arrives',
    () async {
      final device = FakeDevice();
      final backend = FakeBackend(unreachableFor: 4, onlineAfter: 6);
      final controller = _controller(device, backend);
      final unreachableSeen = <bool>[];
      controller.addListener(
        () => unreachableSeen.add(controller.serverUnreachable),
      );
      await controller.start();
      await controller.register(name: 'Balcony');
      await controller.submitWifi('Home', 'pw');
      await controller.submitLocation();

      expect(controller.step, ProvisioningStep.done);
      expect(controller.verifyTimedOut, isFalse);
      expect(backend.currentCalls, 6);
      expect(unreachableSeen, contains(true), reason: 'shown while offline');
      expect(controller.serverUnreachable, isFalse);
      expect(controller.error, isNull);
    },
  );

  test('times out when the server stays unreachable', () async {
    final device = FakeDevice();
    final backend = FakeBackend(unreachableFor: 1 << 30);
    final controller = _controller(device, backend);
    await controller.start();
    await controller.register(name: 'Balcony');
    await controller.submitWifi('Home', 'pw');
    await controller.submitLocation();

    expect(controller.step, ProvisioningStep.verifying);
    expect(controller.verifyTimedOut, isTrue);
    expect(controller.serverUnreachable, isTrue);
    expect(backend.currentCalls, greaterThan(1));
    expect(controller.error, isNull, reason: 'not a failure, still trying');
  });

  test('waits 7 minutes for the first reading by default', () {
    final controller = ProvisioningController(
      session: AiqSession(FakeDevice()),
      api: FakeBackend().client(),
    );
    expect(controller.verifyTimeout, const Duration(minutes: 7));
  });

  test('a late first reading still finishes setup', () async {
    // The monitor uploads after its first sampling burst, so the reading
    // shows up many polls in. The window is scaled down; nothing waits long.
    final device = FakeDevice();
    final backend = FakeBackend(onlineAfter: 40);
    final controller = _controller(
      device,
      backend,
      verifyTimeout: const Duration(seconds: 5),
    );
    await controller.start();
    await controller.register(name: 'Balcony');
    await controller.submitWifi('Home', 'pw');
    await controller.submitLocation();

    expect(controller.step, ProvisioningStep.done);
    expect(controller.verifyTimedOut, isFalse);
    expect(backend.currentCalls, 40);
    // 39 pauses of 5 ms between the polls.
    expect(
      controller.verifyElapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 150)),
    );
  });

  test('rejects an empty SSID without talking to the device', () async {
    final device = FakeDevice();
    final controller = _controller(device, FakeBackend());
    await controller.start();
    await controller.register(name: 'Balcony');
    final sent = device.received.length;
    await controller.submitWifi('  ', 'pw');
    expect(controller.error, isNotNull);
    expect(device.received.length, sent);
  });
}
