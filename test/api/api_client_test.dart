import 'dart:convert';

import 'package:app/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<http.Request> requests;

  ApiClient client(Map<String, http.Response Function(http.Request)> routes) {
    requests = [];
    return ApiClient(
      baseUrl: 'https://api.test/api/v1/',
      tokenProvider: () async => 'jwt-token',
      httpClient: MockClient((request) async {
        requests.add(request);
        final handler = routes['${request.method} ${request.url.path}'];
        return handler?.call(request) ??
            http.Response('{"title":"Not found","status":404}', 404);
      }),
    );
  }

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  test('lists devices with the Clerk bearer token and OTA summary', () async {
    final api = client({
      'GET /api/v1/devices': (_) => json({
        'data': [
          {
            'id': 'c0ffee00-0000-4000-8000-000000000001',
            'device_id': 'dev_1',
            'name': 'Living room',
            'is_outdoor': false,
            'is_public': true,
            'is_location_public': false,
            'firmware_version': '0.1.0',
            'ota': {'status': 'update_available', 'version': '0.2.0'},
            'created_at': '2026-11-01T10:00:00Z',
          },
          {
            'id': 'c0ffee00-0000-4000-8000-000000000002',
            'device_id': 'dev_2',
            'name': 'Old',
            'firmware_version': null,
            'ota': null,
          },
        ],
      }),
    });
    final devices = await api.listDevices();
    expect(requests.single.headers['Authorization'], 'Bearer jwt-token');
    expect(devices.first.ota!.status, 'update_available');
    expect(devices.first.ota!.needsAttention, isTrue);
    expect(devices.last.ota, isNull);
    expect(devices.last.firmwareVersion, isNull);
  });

  test('registers a device and returns the one-time key', () async {
    final api = client({
      'POST /api/v1/devices': (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body, {
          'name': 'Balcony',
          'is_outdoor': true,
          'is_public': false,
          'is_location_public': false,
        });
        expect(request.headers['Content-Type'], startsWith('application/json'));
        return json({
          'data': {
            'id': 'c0ffee00-0000-4000-8000-000000000003',
            'device_id': 'dev_3',
            'name': 'Balcony',
            'device_key': 'sk_123',
          },
        }, 201);
      },
    });
    final created = await api.registerDevice(
      name: 'Balcony',
      isOutdoor: true,
      isLocationPublic: true,
    );
    expect(created.deviceKey, 'sk_123');
    expect(created.device.deviceId, 'dev_3');
  });

  test('sends only the provided fields on update', () async {
    final api = client({
      'PATCH /api/v1/devices/abc': (request) {
        expect(jsonDecode(request.body), {'name': 'New'});
        return json({
          'data': {'id': 'abc', 'device_id': 'dev_1', 'name': 'New'},
        });
      },
    });
    expect((await api.updateDevice('abc', name: 'New')).name, 'New');
  });

  test('maps problem documents, including no-readings', () async {
    final api = client({
      'GET /api/v1/devices/abc/current': (_) => json({
        'type': 'https://docs.air-iq.net/reference/errors/#no-readings',
        'title': 'No readings available',
        'status': 404,
        'detail': 'The device has not reported any readings.',
      }, 404),
      'POST /api/v1/devices/abc/ota/cancel': (_) => json({
        'title': 'Conflict',
        'status': 409,
        'detail': 'There is no approved update to cancel.',
      }, 409),
    });
    final noReadings = await api
        .current('abc')
        .then<ApiException?>(
          (_) => null,
          onError: (Object e) => e as ApiException,
        );
    expect(noReadings!.isNoReadings, isTrue);
    expect(noReadings.isNotFound, isFalse);
    await expectLater(
      api.cancelOta('abc'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.isConflict, 'conflict', isTrue)
            .having((e) => e.message, 'message', contains('no approved')),
      ),
    );
  });

  test('pages logs with level and cursor', () async {
    final api = client({
      'GET /api/v1/devices/abc/logs': (request) {
        expect(request.url.queryParameters, {
          'limit': '50',
          'level': 'warn',
          'before': '90',
        });
        return json({
          'data': [
            {
              'id': 89,
              'level': 'warn',
              'tag': 'wifi',
              'message': 'reconnect failed',
              'boot_count': 3,
              'device_ts': null,
              'created_at': '2026-11-01T10:00:00Z',
            },
          ],
          'next_before': 89,
        });
      },
    });
    final page = await api.logs('abc', minLevel: 'warn', before: 90);
    expect(page.entries.single.tag, 'wifi');
    expect(page.entries.single.deviceTs, isNull);
    expect(page.nextBefore, 89);
  });

  test('parses OTA state and approves', () async {
    final api = client({
      'GET /api/v1/devices/abc/ota': (_) => json({
        'data': {
          'current_version': '0.1.0',
          'available': {
            'id': 'rel',
            'version': '0.2.0',
            'size': 1600800,
            'notes': 'Secure pairing',
          },
          'job': null,
        },
      }),
      'POST /api/v1/devices/abc/ota/approve': (request) {
        expect(jsonDecode(request.body), {'release_id': 'rel'});
        return json({
          'data': {
            'id': 'job',
            'version': '0.2.0',
            'status': 'approved',
            'progress': 0,
            'error': null,
          },
        });
      },
    });
    final state = await api.ota('abc');
    expect(state.available!.version, '0.2.0');
    expect(state.job, isNull);
    final job = await api.approveOta('abc', 'rel');
    expect(job.active, isTrue);
  });
}
