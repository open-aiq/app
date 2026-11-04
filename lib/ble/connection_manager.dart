import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble_transport.dart';
import 'discovery.dart';
import 'protocol.dart';

/// Holds the single active BLE session so every screen (live data, settings,
/// firmware) reuses one connection to the device.
class BleConnectionManager extends ChangeNotifier {
  BleLineTransport? _transport;
  AiqSession? _session;
  DeviceInfo? _info;
  StreamSubscription<void>? _disconnects;
  bool _disposed = false;

  AiqSession? get session => _session;

  /// `INFO` read right after connecting.
  DeviceInfo? get info => _info;
  bool get isConnected => _session != null;

  /// Whether the connected device carries [deviceId] (`dev_…`).
  bool isConnectedTo(String deviceId) =>
      _info?.deviceId == deviceId && isConnected;

  Future<AiqSession> connect(FoundDevice found) async {
    await disconnect();
    final transport = await BleLineTransport.connect(found.bluetoothDevice);
    final session = AiqSession(transport);
    try {
      _info = await session.info();
    } catch (_) {
      await transport.close();
      rethrow;
    }
    _transport = transport;
    _session = session;
    _disconnects = transport.disconnected.listen((_) => _clear());
    _notify();
    return session;
  }

  /// Re-reads `INFO` (e.g. after SAVE changed WiFi or credentials).
  Future<DeviceInfo?> refreshInfo() async {
    final session = _session;
    if (session == null) return null;
    _info = await session.info();
    _notify();
    return _info;
  }

  Future<void> disconnect() async {
    final transport = _transport;
    _clear();
    await transport?.close();
  }

  void _clear() {
    _disconnects?.cancel();
    _disconnects = null;
    _transport = null;
    _session = null;
    _info = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    super.dispose();
  }
}
