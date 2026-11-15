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

  /// Takes commands but never answers, like a monitor that went out of range.
  bool silent = false;

  /// Saved (NVS) copies, updated on SAVE.
  Map<String, String> saved = {};

  @override
  Stream<String> get lines => _out.stream;

  void _send(String line) => scheduleMicrotask(() => _out.add(line));

  /// `OK: <KEY> set to <value>`, as the firmware answers a setter.
  static String _okSet(String key, String value) =>
      '${Reply.okSet(key)} set to $value';

  /// Simulates a 20 s sample while live mode is on.
  void emitReading() {
    if (!live) return;
    _send(
      '${Reply.prefix(Reply.reading)}{"pm1_0":3,"pm2_5":12,"pm10_0":18,"aqi":57,"temperature":24.5,'
      '"humidity":40.0,"heat_index":24.9,"uptime_ms":20000}',
    );
  }

  /// A coordinate within ±[limit] degrees, as the firmware accepts it
  /// (device/src/ble/mod.rs `coordinate`), or null.
  static double? _coordinate(String value, double limit) {
    final degrees = double.tryParse(value.trim());
    if (degrees == null || !degrees.isFinite || degrees.abs() > limit) {
      return null;
    }
    return degrees;
  }

  @override
  Future<void> writeLine(String line) async {
    received.add(line);
    if (silent) return;
    switch (line) {
      case Command.ping:
        _send(Reply.pong);
      case Command.info:
        final keySet = (saved['devkey'] ?? deviceKey).isNotEmpty;
        for (final reply in [
          Reply.infoBegin,
          Reply.field(Reply.firmware, '0.1.0'),
          Reply.field(Reply.mac, 'AABBCCDDEEFF'),
          Reply.field(Reply.deviceId, saved['devid'] ?? deviceId),
          Reply.field(
            Reply.deviceKeySet,
            keySet ? Reply.flagSet : Reply.flagUnset,
          ),
          Reply.field(Reply.wifi, Reply.disconnected),
          Reply.field(Reply.ssid, ssid),
          Reply.field(Reply.ip, Reply.noIp),
          Reply.field(Reply.lastUpload, Reply.none),
          Reply.infoEnd,
        ]) {
          _send(reply);
        }
      case Command.scan:
        for (final reply in [
          Reply.scanBegin,
          Reply.field(Reply.network, '-48,${Reply.secured},Home, Upstairs'),
          Reply.field(Reply.network, '-80,${Reply.open},Cafe'),
          Reply.scanEnd,
        ]) {
          _send(reply);
        }
      case Command.save:
        saved = {
          'ssid': ssid,
          'pass': password,
          'devid': deviceId,
          'devkey': deviceKey,
        };
        _send(Reply.saveBegin);
        _send(Reply.wifiConnecting);
        if (wifiJoins) {
          _send(Reply.saveOk);
          _send(Reply.field(Reply.ip, '192.168.1.20'));
        } else {
          _send(Reply.field(Reply.saveFailed, Reply.failedWifi));
        }
        _send(Reply.saveEnd);
      case Command.clear:
        saved = {};
        _send(Reply.cleared);
      case Command.liveOn:
        live = true;
        _send(Reply.okLiveOn);
      case Command.liveOff:
        live = false;
        _send(Reply.okLiveOff);
      case Command.read:
        _send('$errorPrefix${DeviceErrorCode.noReading}');
      case Command.otaCheck:
        _send(Reply.okOtaCheck);
      default:
        final colon = line.indexOf(separator);
        final key = colon < 0 ? line : line.substring(0, colon);
        final value = colon < 0 ? '' : line.substring(colon + 1);
        switch (key) {
          case Setter.ssid:
            ssid = value;
            _send(_okSet(Setter.ssid, value));
          case Setter.password:
            password = value;
            _send(Reply.okPasswordSet);
          case Setter.latitude:
            final degrees = _coordinate(value, 90);
            if (degrees == null) {
              _send('$errorPrefix${DeviceErrorCode.invalidLat}');
            } else {
              lat = degrees;
              _send(_okSet(Setter.latitude, degrees.toStringAsFixed(6)));
            }
          case Setter.longitude:
            final degrees = _coordinate(value, 180);
            if (degrees == null) {
              _send('$errorPrefix${DeviceErrorCode.invalidLon}');
            } else {
              lon = degrees;
              _send(_okSet(Setter.longitude, degrees.toStringAsFixed(6)));
            }
          case Setter.deviceId:
            deviceId = value;
            _send(_okSet(Setter.deviceId, value));
          case Setter.deviceKey:
            deviceKey = value;
            _send(Reply.okDeviceKeySet);
          default:
            _send('$errorPrefix${DeviceErrorCode.unknownCommand}');
        }
    }
  }
}
