// Open AIQ BLE provisioning protocol (Nordic UART Service).
//
// Must stay in sync with device/src/ble/mod.rs and device/src/main.rs
// (`handle_ble`) and the protocol docs in device/README.md.
//
// Phone -> device: newline-terminated text commands written to RX.
// Device -> phone: newline-terminated reply lines notified on TX, split into
// MTU-sized chunks that must be reassembled.

import 'dart:async';
import 'dart:convert';

const nusServiceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
const nusRxUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
const nusTxUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

/// Devices advertise as `AirMonitor-XXXX`.
const deviceNamePrefix = 'AirMonitor-';

/// The device rejects lines longer than this (RX_BUFFER_LIMIT).
const maxCommandBytes = 512;

class BleProtocolException implements Exception {
  BleProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reassembles notification chunks into lines.
class LineAssembler {
  final List<int> _buffer = [];

  List<String> push(List<int> bytes) {
    _buffer.addAll(bytes);
    final lines = <String>[];
    while (true) {
      final newline = _buffer.indexOf(0x0A);
      if (newline < 0) break;
      var line = _buffer.sublist(0, newline);
      _buffer.removeRange(0, newline + 1);
      if (line.isNotEmpty && line.last == 0x0D) {
        line = line.sublist(0, line.length - 1);
      }
      lines.add(utf8.decode(line, allowMalformed: true));
    }
    return lines;
  }

  void clear() => _buffer.clear();
}

/// Everything after the first `:`; values (SSID, ids) may themselves contain `:`.
String _value(String line) {
  final index = line.indexOf(':');
  return index < 0 ? '' : line.substring(index + 1);
}

/// `INFO` reply.
class DeviceInfo {
  const DeviceInfo({
    required this.firmwareVersion,
    required this.mac,
    required this.deviceId,
    required this.deviceKeySet,
    required this.wifiConnected,
    required this.ssid,
    required this.ip,
    this.lastUploadHttp,
    this.lastUploadSecondsAgo,
  });

  final String firmwareVersion;
  final String mac;

  /// Empty when the device has never been registered.
  final String deviceId;
  final bool deviceKeySet;
  final bool wifiConnected;
  final String ssid;
  final String ip;
  final int? lastUploadHttp;
  final int? lastUploadSecondsAgo;

  bool get hasCredentials => deviceId.isNotEmpty && deviceKeySet;
}

DeviceInfo parseInfo(List<String> lines) {
  final fields = <String, String>{};
  for (final line in lines) {
    final index = line.indexOf(':');
    if (index > 0) fields[line.substring(0, index)] = _value(line);
  }
  int? uploadHttp;
  int? uploadAgo;
  final upload = fields['LAST_UPLOAD'];
  if (upload != null && upload != 'none') {
    final parts = upload.split(',');
    uploadHttp = int.tryParse(parts.first);
    if (parts.length > 1) uploadAgo = int.tryParse(parts[1]);
  }
  return DeviceInfo(
    firmwareVersion: fields['FW'] ?? '',
    mac: fields['MAC'] ?? '',
    deviceId: fields['DEVID'] ?? '',
    deviceKeySet: fields['DEVKEY_SET'] == '1',
    wifiConnected: fields['WIFI'] == 'connected',
    ssid: fields['SSID'] ?? '',
    ip: fields['IP'] ?? '',
    lastUploadHttp: uploadHttp,
    lastUploadSecondsAgo: uploadAgo,
  );
}

class WifiNetwork {
  const WifiNetwork({
    required this.ssid,
    required this.rssi,
    required this.secured,
  });

  final String ssid;
  final int rssi;
  final bool secured;

  /// 0–4 signal bars.
  int get bars => rssi >= -55
      ? 4
      : rssi >= -65
      ? 3
      : rssi >= -75
      ? 2
      : rssi >= -85
      ? 1
      : 0;
}

/// `SCAN` reply: `NET:<rssi>,<open|secured>,<ssid>` lines (SSID may contain commas).
List<WifiNetwork> parseScan(List<String> lines) {
  final networks = <WifiNetwork>[];
  for (final line in lines) {
    if (line.startsWith('ERROR:')) {
      throw BleProtocolException(
        'The device could not scan for WiFi networks.',
      );
    }
    if (!line.startsWith('NET:')) continue;
    final parts = _value(line).split(',');
    if (parts.length < 3) continue;
    networks.add(
      WifiNetwork(
        rssi: int.tryParse(parts[0]) ?? -100,
        secured: parts[1] != 'open',
        ssid: parts.sublist(2).join(','),
      ),
    );
  }
  return networks;
}

enum SaveFailure { wifi, storage }

class SaveResult {
  const SaveResult.ok(this.ip) : failure = null;
  const SaveResult.failed(this.failure) : ip = null;

  final String? ip;
  final SaveFailure? failure;

  bool get ok => failure == null;
}

/// `SAVE` reply: `SAVE_OK` + `IP:<ip>`, or `SAVE_FAILED:WIFI|STORAGE`.
SaveResult parseSave(List<String> lines) {
  for (final line in lines) {
    if (line == 'SAVE_FAILED:STORAGE') {
      return const SaveResult.failed(SaveFailure.storage);
    }
    if (line.startsWith('SAVE_FAILED')) {
      return const SaveResult.failed(SaveFailure.wifi);
    }
  }
  if (!lines.contains('SAVE_OK')) {
    return const SaveResult.failed(SaveFailure.wifi);
  }
  final ip = lines.firstWhere(
    (line) => line.startsWith('IP:'),
    orElse: () => 'IP:',
  );
  return SaveResult.ok(_value(ip));
}

/// One 20-second sample streamed as `READING:{json}`; null fields are missing sensors.
class LiveReading {
  const LiveReading({
    this.pm1,
    this.pm25,
    this.pm10,
    this.aqi,
    this.temperature,
    this.humidity,
    this.heatIndex,
    this.uptimeMs = 0,
  });

  final int? pm1;
  final int? pm25;
  final int? pm10;
  final int? aqi;
  final double? temperature;
  final double? humidity;
  final double? heatIndex;
  final int uptimeMs;
}

LiveReading? parseReading(String line) {
  if (!line.startsWith('READING:')) return null;
  try {
    final json = jsonDecode(line.substring('READING:'.length));
    if (json is! Map<String, dynamic>) return null;
    int? asInt(String key) => (json[key] as num?)?.toInt();
    double? asDouble(String key) => (json[key] as num?)?.toDouble();
    return LiveReading(
      pm1: asInt('pm1_0'),
      pm25: asInt('pm2_5'),
      pm10: asInt('pm10_0'),
      aqi: asInt('aqi'),
      temperature: asDouble('temperature'),
      humidity: asDouble('humidity'),
      heatIndex: asDouble('heat_index'),
      uptimeMs: asInt('uptime_ms') ?? 0,
    );
  } on FormatException {
    return null;
  }
}

/// Builds a setter command, rejecting values that would break line framing.
String setter(String key, String value) {
  if (value.contains('\n') || value.contains('\r')) {
    throw BleProtocolException('$key must not contain line breaks.');
  }
  final command = '$key:$value';
  if (utf8.encode(command).length >= maxCommandBytes) {
    throw BleProtocolException('$key is too long.');
  }
  return command;
}

/// A bidirectional line channel to one device (implemented over BLE in
/// ble_transport.dart; faked in tests).
abstract class LineTransport {
  Stream<String> get lines;
  Future<void> writeLine(String line);
}

/// Request/response helpers for the device protocol.
class AiqSession {
  AiqSession(this.transport);

  final LineTransport transport;
  static const _timeout = Duration(seconds: 10);

  /// Serializes commands so replies are never interleaved.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Sends [command] and returns the first reply line accepted by [matches].
  /// `ERROR:` replies throw.
  Future<String> expect(
    String command,
    bool Function(String line) matches, {
    Duration timeout = _timeout,
  }) => _serial(() async {
    final reply = transport.lines
        .firstWhere((line) => matches(line) || line.startsWith('ERROR:'))
        .timeout(
          timeout,
          onTimeout: () => throw BleProtocolException(
            'The device did not answer "$command".',
          ),
        );
    try {
      await transport.writeLine(command);
    } catch (_) {
      reply.ignore();
      rethrow;
    }
    final line = await reply;
    if (line.startsWith('ERROR:')) {
      throw BleProtocolException('Device error: ${_value(line)}');
    }
    return line;
  });

  /// Sends [command] and collects the lines between [begin] and [end].
  Future<List<String>> block(
    String command,
    String begin,
    String end, {
    Duration timeout = _timeout,
  }) => _serial(() async {
    final lines = <String>[];
    var inside = false;
    final done = Completer<List<String>>();
    final subscription = transport.lines.listen((line) {
      if (line == begin) {
        inside = true;
      } else if (line == end && inside) {
        if (!done.isCompleted) done.complete(lines);
      } else if (inside) {
        lines.add(line);
      }
    });
    try {
      await transport.writeLine(command);
      return await done.future.timeout(
        timeout,
        onTimeout: () =>
            throw BleProtocolException('The device did not finish "$command".'),
      );
    } finally {
      await subscription.cancel();
    }
  });

  Future<void> ping() => expect('PING', (line) => line == 'PONG');

  Future<DeviceInfo> info() async =>
      parseInfo(await block('INFO', 'INFO_BEGIN', 'INFO_END'));

  /// Scanning takes a few seconds on the device.
  Future<List<WifiNetwork>> scanWifi() async => parseScan(
    await block(
      'SCAN',
      'SCAN_BEGIN',
      'SCAN_END',
      timeout: const Duration(seconds: 20),
    ),
  );

  Future<void> setWifi(String ssid, String password) async {
    await expect(setter('SSID', ssid), (line) => line.startsWith('OK: SSID'));
    await expect(
      setter('PASS', password),
      (line) => line == 'OK: password set',
    );
  }

  Future<void> setLocation(double lat, double lon) async {
    await expect(
      setter('LAT', lat.toStringAsFixed(6)),
      (line) => line.startsWith('OK: LAT'),
    );
    await expect(
      setter('LON', lon.toStringAsFixed(6)),
      (line) => line.startsWith('OK: LON'),
    );
  }

  Future<void> setCredentials(String deviceId, String deviceKey) async {
    await expect(
      setter('DEVID', deviceId),
      (line) => line.startsWith('OK: DEVID'),
    );
    await expect(
      setter('DEVKEY', deviceKey),
      (line) => line == 'OK: device key set',
    );
  }

  /// Persists the staged settings and reconnects WiFi (up to ~15 s on the device).
  Future<SaveResult> save() async => parseSave(
    await block(
      'SAVE',
      'SAVE_BEGIN',
      'SAVE_END',
      timeout: const Duration(seconds: 40),
    ),
  );

  /// Factory reset: wipes provisioning and BLE bonds on the device.
  Future<void> clear() => expect('CLEAR', (line) => line.startsWith('CLEARED'));

  Future<LiveReading?> read() async {
    try {
      return parseReading(
        await expect('READ', (line) => line.startsWith('READING:')),
      );
    } on BleProtocolException {
      return null;
    }
  }

  Future<void> setLive(bool enabled) => expect(
    enabled ? 'LIVE:ON' : 'LIVE:OFF',
    (line) => line.startsWith('OK: live'),
  );

  /// Streamed samples while live mode is on.
  Stream<LiveReading> get readings => transport.lines
      .map(parseReading)
      .where((reading) => reading != null)
      .cast<LiveReading>();

  /// Asks the device to check for an approved OTA update right away.
  Future<void> otaCheck() =>
      expect('OTA:CHECK', (line) => line == 'OK: ota check');
}
