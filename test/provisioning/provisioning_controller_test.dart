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
/// [onlineAfter] polls.
class FakeBackend {
  FakeBackend({this.existingDeviceId, this.onlineAfter = 1});

  final String? existingDeviceId;
  final int onlineAfter;
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

ProvisioningController _controller(FakeDevice device, FakeBackend backend) =>
    ProvisioningController(
      session: AiqSession(device),
      api: backend.client(),
      pollInterval: const Duration(milliseconds: 5),
      verifyTimeout: const Duration(milliseconds: 300),
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

    await controller.rotateAndResendKey();
    expect(controller.error, isNull);
    expect(device.saved['devkey'], 'sk_rotated');
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
