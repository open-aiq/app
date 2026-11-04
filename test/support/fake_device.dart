import 'dart:async';

import 'package:app/ble/protocol.dart';

/// In-memory emulation of the firmware's BLE command handler
/// (device/src/main.rs `handle_ble`), for protocol and wizard tests.
class FakeDevice implements LineTransport {
  final _out = StreamController<String>.broadcast();
  final List<String> received = [];

  String ssid = '';
  String password = '';
  double lat = 0;
  double lon = 0;
  String deviceId = '';
  String deviceKey = '';
  bool wifiJoins = true;
  bool live = false;

  /// Saved (NVS) copies, updated on SAVE.
  Map<String, String> saved = {};

  @override
  Stream<String> get lines => _out.stream;

  void _send(String line) => scheduleMicrotask(() => _out.add(line));

  /// Simulates a 20 s sample while live mode is on.
  void emitReading() {
    if (!live) return;
    _send(
      'READING:{"pm1_0":3,"pm2_5":12,"pm10_0":18,"aqi":57,"temperature":24.5,'
      '"humidity":40.0,"heat_index":24.9,"uptime_ms":20000}',
    );
  }

  @override
  Future<void> writeLine(String line) async {
    received.add(line);
    switch (line) {
      case 'PING':
        _send('PONG');
      case 'INFO':
        for (final reply in [
          'INFO_BEGIN',
          'FW:0.1.0',
          'MAC:AABBCCDDEEFF',
          'DEVID:${saved['devid'] ?? deviceId}',
          'DEVKEY_SET:${(saved['devkey'] ?? deviceKey).isEmpty ? 0 : 1}',
          'WIFI:disconnected',
          'SSID:$ssid',
          'IP:0.0.0.0',
          'LAST_UPLOAD:none',
          'INFO_END',
        ]) {
          _send(reply);
        }
      case 'SCAN':
        for (final reply in [
          'SCAN_BEGIN',
          'NET:-48,secured,Home, Upstairs',
          'NET:-80,open,Cafe',
          'SCAN_END',
        ]) {
          _send(reply);
        }
      case 'SAVE':
        saved = {
          'ssid': ssid,
          'pass': password,
          'devid': deviceId,
          'devkey': deviceKey,
        };
        _send('SAVE_BEGIN');
        _send('WIFI_CONNECTING');
        if (wifiJoins) {
          _send('SAVE_OK');
          _send('IP:192.168.1.20');
        } else {
          _send('SAVE_FAILED:WIFI');
        }
        _send('SAVE_END');
      case 'CLEAR':
        saved = {};
        _send('CLEARED all stored config');
      case 'LIVE:ON':
        live = true;
        _send('OK: live on');
      case 'LIVE:OFF':
        live = false;
        _send('OK: live off');
      case 'READ':
        _send('ERROR:NO_READING');
      case 'OTA:CHECK':
        _send('OK: ota check');
      default:
        final colon = line.indexOf(':');
        final key = colon < 0 ? line : line.substring(0, colon);
        final value = colon < 0 ? '' : line.substring(colon + 1);
        switch (key) {
          case 'SSID':
            ssid = value;
            _send('OK: SSID set to $value');
          case 'PASS':
            password = value;
            _send('OK: password set');
          case 'LAT':
            lat = double.parse(value);
            _send('OK: LAT set to $value');
          case 'LON':
            lon = double.parse(value);
            _send('OK: LON set to $value');
          case 'DEVID':
            deviceId = value;
            _send('OK: DEVID set to $value');
          case 'DEVKEY':
            deviceKey = value;
            _send('OK: device key set');
          default:
            _send('echo: $line');
        }
    }
  }
}
