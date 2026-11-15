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

// The protocol vocabulary. Mirrors device/src/ble/wire.rs; keep the two in
// step. Lines are `KEY` or `KEY:value`.

/// Splits a key from its value, as in `SSID:home`.
const separator = ':';

/// Splits the parts of a value, as in `NET:-61,open,Home`.
const listSeparator = ',';

/// Phone -> device commands that take no value.
abstract final class Command {
  static const ping = 'PING';
  static const status = 'STATUS';
  static const info = 'INFO';
  static const scan = 'SCAN';
  static const read = 'READ';
  static const liveOn = 'LIVE:ON';
  static const liveOff = 'LIVE:OFF';
  static const otaCheck = 'OTA:CHECK';
  static const save = 'SAVE';
  static const load = 'LOAD';
  static const clear = 'CLEAR';
}

/// Phone -> device setters, sent as `<KEY>:<value>` (build them with [setter]).
abstract final class Setter {
  static const ssid = 'SSID';
  static const password = 'PASS';
  static const latitude = 'LAT';
  static const longitude = 'LON';
  static const deviceId = 'DEVID';
  static const deviceKey = 'DEVKEY';
}

/// Device -> phone lines, field keys and values.
abstract final class Reply {
  static const pong = 'PONG';
  static const infoBegin = 'INFO_BEGIN';
  static const infoEnd = 'INFO_END';
  static const scanBegin = 'SCAN_BEGIN';
  static const scanEnd = 'SCAN_END';
  static const saveBegin = 'SAVE_BEGIN';
  static const saveEnd = 'SAVE_END';
  static const loadBegin = 'LOAD_BEGIN';
  static const loadEnd = 'LOAD_END';
  static const wifiConnecting = 'WIFI_CONNECTING';
  static const saveOk = 'SAVE_OK';
  static const cleared = 'CLEARED all stored config';
  static const okLiveOn = 'OK: live on';
  static const okLiveOff = 'OK: live off';
  static const okOtaCheck = 'OK: ota check';
  static const okPasswordSet = 'OK: password set';
  static const okDeviceKeySet = 'OK: device key set';
  static const otaNone = 'OTA:NONE';
  static const otaFailed = 'OTA:FAILED';

  /// Followed by a space and the version being installed.
  static const otaStarting = 'OTA:STARTING';

  // Field keys, sent as `<KEY>:<value>`.
  static const firmware = 'FW';
  static const mac = 'MAC';
  static const deviceId = 'DEVID';
  static const deviceKeySet = 'DEVKEY_SET';
  static const passwordSet = 'PASS_SET';
  static const wifi = 'WIFI';
  static const ssid = 'SSID';
  static const ip = 'IP';
  static const latitude = 'LAT';
  static const longitude = 'LON';
  static const lastUpload = 'LAST_UPLOAD';
  static const network = 'NET';
  static const reading = 'READING';
  static const saveFailed = 'SAVE_FAILED';
  static const error = 'ERROR';

  // Values.
  static const connected = 'connected';
  static const disconnected = 'disconnected';
  static const noIp = '0.0.0.0';
  static const none = 'none';
  static const open = 'open';
  static const secured = 'secured';
  static const flagSet = '1';
  static const flagUnset = '0';
  static const failedWifi = 'WIFI';
  static const failedStorage = 'STORAGE';

  /// `<KEY>:<value>`.
  static String field(String key, Object value) => '$key$separator$value';

  /// `<KEY>:`, the start of a field line.
  static String prefix(String key) => '$key$separator';

  /// `OK: <KEY>`, the start of the answer to a setter
  /// (`OK: <KEY> set to <value>`).
  static String okSet(String key) => 'OK: $key';
}

/// Every failure reply starts with this, followed by a [DeviceErrorCode].
const errorPrefix = '${Reply.error}$separator';

/// The codes the device sends after [errorPrefix].
abstract final class DeviceErrorCode {
  static const scan = 'SCAN';
  static const noReading = 'NO_READING';
  static const storage = 'STORAGE';
  static const commandTooLong = 'COMMAND_TOO_LONG';
  static const invalidUtf8 = 'INVALID_UTF8';
  static const invalidLat = 'INVALID_LAT';
  static const invalidLon = 'INVALID_LON';
  static const unknownCommand = 'UNKNOWN_COMMAND';
}

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
  final index = line.indexOf(separator);
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
    final index = line.indexOf(separator);
    if (index > 0) fields[line.substring(0, index)] = _value(line);
  }
  int? uploadHttp;
  int? uploadAgo;
  final upload = fields[Reply.lastUpload];
  if (upload != null && upload != Reply.none) {
    final parts = upload.split(listSeparator);
    uploadHttp = int.tryParse(parts.first);
    if (parts.length > 1) uploadAgo = int.tryParse(parts[1]);
  }
  return DeviceInfo(
    firmwareVersion: fields[Reply.firmware] ?? '',
    mac: fields[Reply.mac] ?? '',
    deviceId: fields[Reply.deviceId] ?? '',
    deviceKeySet: fields[Reply.deviceKeySet] == Reply.flagSet,
    wifiConnected: fields[Reply.wifi] == Reply.connected,
    ssid: fields[Reply.ssid] ?? '',
    ip: fields[Reply.ip] ?? '',
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
    if (line.startsWith(errorPrefix)) {
      throw BleProtocolException(
        'The device could not scan for WiFi networks.',
      );
    }
    if (!line.startsWith(Reply.prefix(Reply.network))) continue;
    final parts = _value(line).split(listSeparator);
    if (parts.length < 3) continue;
    networks.add(
      WifiNetwork(
        rssi: int.tryParse(parts[0]) ?? -100,
        secured: parts[1] != Reply.open,
        ssid: parts.sublist(2).join(listSeparator),
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
    if (line == Reply.field(Reply.saveFailed, Reply.failedStorage)) {
      return const SaveResult.failed(SaveFailure.storage);
    }
    if (line.startsWith(Reply.saveFailed)) {
      return const SaveResult.failed(SaveFailure.wifi);
    }
  }
  if (!lines.contains(Reply.saveOk)) {
    return const SaveResult.failed(SaveFailure.wifi);
  }
  final ip = lines.firstWhere(
    (line) => line.startsWith(Reply.prefix(Reply.ip)),
    orElse: () => Reply.prefix(Reply.ip),
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
  final prefix = Reply.prefix(Reply.reading);
  if (!line.startsWith(prefix)) return null;
  try {
    final json = jsonDecode(line.substring(prefix.length));
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
  final command = '$key$separator$value';
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
        .firstWhere((line) => matches(line) || line.startsWith(errorPrefix))
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
    if (line.startsWith(errorPrefix)) {
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

  Future<void> ping() => expect(Command.ping, (line) => line == Reply.pong);

  Future<DeviceInfo> info() async =>
      parseInfo(await block(Command.info, Reply.infoBegin, Reply.infoEnd));

  /// Scanning takes a few seconds on the device.
  Future<List<WifiNetwork>> scanWifi() async => parseScan(
    await block(
      Command.scan,
      Reply.scanBegin,
      Reply.scanEnd,
      timeout: const Duration(seconds: 20),
    ),
  );

  Future<void> setWifi(String ssid, String password) async {
    await expect(
      setter(Setter.ssid, ssid),
      (line) => line.startsWith(Reply.okSet(Setter.ssid)),
    );
    await expect(
      setter(Setter.password, password),
      (line) => line == Reply.okPasswordSet,
    );
  }

  Future<void> setLocation(double lat, double lon) async {
    await expect(
      setter(Setter.latitude, lat.toStringAsFixed(6)),
      (line) => line.startsWith(Reply.okSet(Setter.latitude)),
    );
    await expect(
      setter(Setter.longitude, lon.toStringAsFixed(6)),
      (line) => line.startsWith(Reply.okSet(Setter.longitude)),
    );
  }

  Future<void> setCredentials(String deviceId, String deviceKey) async {
    await expect(
      setter(Setter.deviceId, deviceId),
      (line) => line.startsWith(Reply.okSet(Setter.deviceId)),
    );
    await expect(
      setter(Setter.deviceKey, deviceKey),
      (line) => line == Reply.okDeviceKeySet,
    );
  }

  /// Persists the staged settings and reconnects WiFi (up to ~15 s on the device).
  Future<SaveResult> save() async => parseSave(
    await block(
      Command.save,
      Reply.saveBegin,
      Reply.saveEnd,
      timeout: const Duration(seconds: 40),
    ),
  );

  /// Factory reset: wipes provisioning and BLE bonds on the device.
  Future<void> clear() =>
      expect(Command.clear, (line) => line == Reply.cleared);

  Future<LiveReading?> read() async {
    try {
      return parseReading(
        await expect(
          Command.read,
          (line) => line.startsWith(Reply.prefix(Reply.reading)),
        ),
      );
    } on BleProtocolException {
      return null;
    }
  }

  Future<void> setLive(bool enabled) => expect(
    enabled ? Command.liveOn : Command.liveOff,
    (line) => line == (enabled ? Reply.okLiveOn : Reply.okLiveOff),
  );

  /// Streamed samples while live mode is on.
  Stream<LiveReading> get readings => transport.lines
      .map(parseReading)
      .where((reading) => reading != null)
      .cast<LiveReading>();

  /// Asks the device to check for an approved OTA update right away.
  Future<void> otaCheck() =>
      expect(Command.otaCheck, (line) => line == Reply.okOtaCheck);
}
