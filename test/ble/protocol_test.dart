import 'dart:convert';

import 'package:app/ble/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_device.dart';

void main() {
  group('LineAssembler', () {
    test('reassembles fragmented and coalesced notifications', () {
      final assembler = LineAssembler();
      expect(assembler.push(utf8.encode('INFO_BE')), isEmpty);
      expect(assembler.push(utf8.encode('GIN\r\nFW:0.1')), ['INFO_BEGIN']);
      expect(assembler.push(utf8.encode('.0\nSSID:Caf')), ['FW:0.1.0']);
      // A multi-byte character split across two 20-byte notifications.
      final bytes = utf8.encode('é\n');
      expect(assembler.push(bytes.sublist(0, 1)), isEmpty);
      expect(assembler.push(bytes.sublist(1)), ['SSID:Café']);
    });
  });

  group('parsers', () {
    test('parses INFO', () {
      final info = parseInfo([
        'FW:0.2.0',
        'MAC:AABBCCDDEEFF',
        'DEVID:dev_abc',
        'DEVKEY_SET:1',
        'WIFI:connected',
        'SSID:Home:5G',
        'IP:192.168.1.5',
        'LAST_UPLOAD:201,42',
      ]);
      expect(info.firmwareVersion, '0.2.0');
      expect(info.hasCredentials, isTrue);
      expect(info.wifiConnected, isTrue);
      expect(info.ssid, 'Home:5G', reason: 'values may contain colons');
      expect(info.lastUploadHttp, 201);
      expect(info.lastUploadSecondsAgo, 42);
      final fresh = parseInfo(['DEVID:', 'DEVKEY_SET:0', 'LAST_UPLOAD:none']);
      expect(fresh.hasCredentials, isFalse);
      expect(fresh.lastUploadHttp, isNull);
    });

    test('parses SCAN with commas in SSIDs and reports errors', () {
      final networks = parseScan([
        'NET:-48,secured,Home, Upstairs',
        'NET:-90,open,Cafe',
        'garbage',
      ]);
      expect(networks.map((n) => n.ssid), ['Home, Upstairs', 'Cafe']);
      expect(networks.first.secured, isTrue);
      expect(networks.first.bars, 4);
      expect(networks.last.bars, 0);
      expect(
        () => parseScan(['ERROR:SCAN']),
        throwsA(isA<BleProtocolException>()),
      );
    });

    test('parses SAVE outcomes', () {
      final ok = parseSave(['WIFI_CONNECTING', 'SAVE_OK', 'IP:10.0.0.2']);
      expect(ok.ok, isTrue);
      expect(ok.ip, '10.0.0.2');
      expect(
        parseSave(['WIFI_CONNECTING', 'SAVE_FAILED:WIFI']).failure,
        SaveFailure.wifi,
      );
      expect(parseSave(['SAVE_FAILED:STORAGE']).failure, SaveFailure.storage);
      expect(parseSave([]).ok, isFalse);
    });

    test('parses live readings with missing sensors', () {
      final reading = parseReading(
        'READING:{"pm1_0":3,"pm2_5":12,"pm10_0":18,"aqi":57,"temperature":24.5,"humidity":null,"heat_index":null,"uptime_ms":20000}',
      )!;
      expect(reading.pm25, 12);
      expect(reading.aqi, 57);
      expect(reading.temperature, 24.5);
      expect(reading.humidity, isNull);
      expect(parseReading('READING:not json'), isNull);
      expect(parseReading('OK: live on'), isNull);
    });

    test('setter rejects values that break framing', () {
      expect(setter('SSID', 'Home'), 'SSID:Home');
      expect(
        () => setter('SSID', 'a\nPASS:x'),
        throwsA(isA<BleProtocolException>()),
      );
      expect(
        () => setter('PASS', 'x' * 600),
        throwsA(isA<BleProtocolException>()),
      );
    });
  });

  group('AiqSession', () {
    late FakeDevice device;
    late AiqSession session;

    setUp(() {
      device = FakeDevice();
      session = AiqSession(device);
    });

    test('provisions WiFi, location and credentials, then saves', () async {
      await session.ping();
      await session.setCredentials('dev_1', 'sk_secret');
      await session.setWifi('Home', 'p:ss');
      await session.setLocation(24.8607, 67.0011);
      final result = await session.save();
      expect(result.ok, isTrue);
      expect(result.ip, '192.168.1.20');
      expect(device.saved, {
        'ssid': 'Home',
        'pass': 'p:ss',
        'devid': 'dev_1',
        'devkey': 'sk_secret',
      });
      expect(device.received, contains('LAT:24.860700'));
      final info = await session.info();
      expect(info.deviceId, 'dev_1');
      expect(info.deviceKeySet, isTrue);
    });

    test('serializes concurrent commands', () async {
      final results = await Future.wait([
        session.info(),
        session.scanWifi(),
        session.info(),
      ]);
      expect((results[1] as List<WifiNetwork>).length, 2);
      expect(device.received, ['INFO', 'SCAN', 'INFO']);
    });

    test('device errors surface as exceptions', () async {
      expect(
        await session.read(),
        isNull,
        reason: 'READ before the first sample returns ERROR:NO_READING',
      );
      await expectLater(
        session.expect('READ', (line) => line.startsWith('READING:')),
        throwsA(isA<BleProtocolException>()),
      );
    });

    test('times out when the device does not answer', () async {
      device.silent = true;
      await expectLater(
        session.expect(
          'PING',
          (line) => line == 'PONG',
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<BleProtocolException>().having(
            (e) => e.message,
            'message',
            contains('did not answer'),
          ),
        ),
      );
    });

    test('an unknown command is refused right away', () async {
      await expectLater(
        session.expect('NOPE', (line) => line == 'NEVER'),
        throwsA(
          isA<BleProtocolException>().having(
            (e) => e.message,
            'message',
            'Device error: UNKNOWN_COMMAND',
          ),
        ),
      );
      // The session is still usable afterwards.
      await session.ping();
    });

    test('coordinates out of range are refused when set', () async {
      await expectLater(
        session.setLocation(91, 67),
        throwsA(
          isA<BleProtocolException>().having(
            (e) => e.message,
            'message',
            'Device error: INVALID_LAT',
          ),
        ),
      );
      await expectLater(
        session.setLocation(24.86, 181),
        throwsA(
          isA<BleProtocolException>().having(
            (e) => e.message,
            'message',
            'Device error: INVALID_LON',
          ),
        ),
      );
      expect(device.lon, 0, reason: 'the bad longitude was not stored');
      expect(device.received, isNot(contains('LON:67.000000')));
    });

    test('streams live readings', () async {
      await session.setLive(true);
      final next = session.readings.first;
      device.emitReading();
      expect((await next).pm25, 12);
      await session.setLive(false);
      expect(device.live, isFalse);
    });
  });
}
