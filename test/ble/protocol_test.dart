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
        () => parseScan(['$errorPrefix${DeviceErrorCode.scan}']),
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
      expect(
        device.received,
        contains(Reply.field(Setter.latitude, '24.860700')),
      );
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
      expect(device.received, [Command.info, Command.scan, Command.info]);
    });

    test('device errors surface as exceptions', () async {
      expect(
        await session.read(),
        isNull,
        reason: 'READ before the first sample returns ERROR:NO_READING',
      );
      await expectLater(
        session.expect(
          Command.read,
          (line) => line.startsWith(Reply.prefix(Reply.reading)),
        ),
        throwsA(isA<BleProtocolException>()),
      );
    });

    test('times out when the device does not answer', () async {
      device.silent = true;
      await expectLater(
        session.expect(
          Command.ping,
          (line) => line == Reply.pong,
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
            'Device error: ${DeviceErrorCode.unknownCommand}',
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
            'Device error: ${DeviceErrorCode.invalidLat}',
          ),
        ),
      );
      await expectLater(
        session.setLocation(24.86, 181),
        throwsA(
          isA<BleProtocolException>().having(
            (e) => e.message,
            'message',
            'Device error: ${DeviceErrorCode.invalidLon}',
          ),
        ),
      );
      expect(device.lon, 0, reason: 'the bad longitude was not stored');
      expect(
        device.received,
        isNot(contains(Reply.field(Setter.longitude, '67.000000'))),
      );
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

  // The one place the wire strings are spelled out. If this fails, the
  // firmware (device/src/ble/wire.rs) and the protocol docs need the same
  // change.
  test('wire format is unchanged', () {
    const lines = {
      Command.ping: 'PING',
      Command.status: 'STATUS',
      Command.info: 'INFO',
      Command.scan: 'SCAN',
      Command.read: 'READ',
      Command.liveOn: 'LIVE:ON',
      Command.liveOff: 'LIVE:OFF',
      Command.otaCheck: 'OTA:CHECK',
      Command.save: 'SAVE',
      Command.load: 'LOAD',
      Command.clear: 'CLEAR',
      Setter.ssid: 'SSID',
      Setter.password: 'PASS',
      Setter.latitude: 'LAT',
      Setter.longitude: 'LON',
      Setter.deviceId: 'DEVID',
      Setter.deviceKey: 'DEVKEY',
      Reply.pong: 'PONG',
      Reply.infoBegin: 'INFO_BEGIN',
      Reply.infoEnd: 'INFO_END',
      Reply.scanBegin: 'SCAN_BEGIN',
      Reply.scanEnd: 'SCAN_END',
      Reply.saveBegin: 'SAVE_BEGIN',
      Reply.saveEnd: 'SAVE_END',
      Reply.loadBegin: 'LOAD_BEGIN',
      Reply.loadEnd: 'LOAD_END',
      Reply.wifiConnecting: 'WIFI_CONNECTING',
      Reply.saveOk: 'SAVE_OK',
      Reply.cleared: 'CLEARED all stored config',
      Reply.okLiveOn: 'OK: live on',
      Reply.okLiveOff: 'OK: live off',
      Reply.okOtaCheck: 'OK: ota check',
      Reply.okPasswordSet: 'OK: password set',
      Reply.okDeviceKeySet: 'OK: device key set',
      Reply.otaNone: 'OTA:NONE',
      Reply.otaFailed: 'OTA:FAILED',
      Reply.otaStarting: 'OTA:STARTING',
    };
    lines.forEach((actual, expected) => expect(actual, expected));

    expect(Reply.field(Reply.firmware, '1.2.3'), 'FW:1.2.3');
    expect(Reply.field(Reply.deviceKeySet, Reply.flagSet), 'DEVKEY_SET:1');
    expect(Reply.field(Reply.passwordSet, Reply.flagUnset), 'PASS_SET:0');
    expect(Reply.field(Reply.wifi, Reply.connected), 'WIFI:connected');
    expect(Reply.field(Reply.wifi, Reply.disconnected), 'WIFI:disconnected');
    expect(Reply.field(Reply.ip, Reply.noIp), 'IP:0.0.0.0');
    expect(Reply.field(Reply.lastUpload, Reply.none), 'LAST_UPLOAD:none');
    expect(Reply.field(Reply.ssid, 'Home'), 'SSID:Home');
    expect(Reply.field(Reply.mac, 'AA'), 'MAC:AA');
    expect(Reply.field(Reply.deviceId, 'd'), 'DEVID:d');
    expect(Reply.field(Reply.latitude, '1'), 'LAT:1');
    expect(Reply.field(Reply.longitude, '1'), 'LON:1');
    expect(
      Reply.field(Reply.network, '-61$listSeparator${Reply.open}'),
      'NET:-61,open',
    );
    expect(Reply.field(Reply.network, Reply.secured), 'NET:secured');
    expect(Reply.prefix(Reply.reading), 'READING:');
    expect(
      Reply.field(Reply.saveFailed, Reply.failedStorage),
      'SAVE_FAILED:STORAGE',
    );
    expect(Reply.field(Reply.saveFailed, Reply.failedWifi), 'SAVE_FAILED:WIFI');
    expect(Reply.okSet(Setter.latitude), 'OK: LAT');

    const errors = {
      DeviceErrorCode.scan: 'ERROR:SCAN',
      DeviceErrorCode.noReading: 'ERROR:NO_READING',
      DeviceErrorCode.storage: 'ERROR:STORAGE',
      DeviceErrorCode.commandTooLong: 'ERROR:COMMAND_TOO_LONG',
      DeviceErrorCode.invalidUtf8: 'ERROR:INVALID_UTF8',
      DeviceErrorCode.invalidLat: 'ERROR:INVALID_LAT',
      DeviceErrorCode.invalidLon: 'ERROR:INVALID_LON',
      DeviceErrorCode.unknownCommand: 'ERROR:UNKNOWN_COMMAND',
    };
    errors.forEach((code, line) => expect('$errorPrefix$code', line));
  });
}
