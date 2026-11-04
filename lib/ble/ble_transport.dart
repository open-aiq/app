import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../config.dart';
import 'protocol.dart';

/// [LineTransport] over the Nordic UART Service using FlutterBluePlus.
///
/// The device's RX/TX characteristics require an encrypted, MITM-protected
/// link: the first write triggers the OS passkey prompt (6 digits shown on the
/// device OLED / serial log). Writes use write-with-response so iOS receives
/// "insufficient authentication" and starts pairing.
class BleLineTransport implements LineTransport {
  BleLineTransport._(
    this.device,
    this._rx,
    this._lines,
    this._subscriptions,
    this._payload,
  );

  final BluetoothDevice device;
  final BluetoothCharacteristic _rx;
  final StreamController<String> _lines;
  final List<StreamSubscription<dynamic>> _subscriptions;
  final int _payload;

  @override
  Stream<String> get lines => _lines.stream;

  /// Emits once when the link drops.
  Stream<void> get disconnected => device.connectionState
      .where((state) => state == BluetoothConnectionState.disconnected)
      .map((_) {});

  static Future<BleLineTransport> connect(BluetoothDevice device) async {
    await device.connect(
      license: AppConfig.bleLicense,
      timeout: const Duration(seconds: 20),
      mtu: Platform.isAndroid ? 247 : null,
    );
    try {
      if (Platform.isAndroid) {
        // Ask for the passkey up front instead of failing the first write.
        await device.createBond(timeout: 90);
      }
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (service) => service.uuid == Guid(nusServiceUuid),
        orElse: () =>
            throw BleProtocolException('This is not an Open AIQ device.'),
      );
      BluetoothCharacteristic characteristic(String uuid) =>
          service.characteristics.firstWhere(
            (c) => c.uuid == Guid(uuid),
            orElse: () => throw BleProtocolException(
              'The device firmware is not compatible.',
            ),
          );
      final rx = characteristic(nusRxUuid);
      final tx = characteristic(nusTxUuid);

      final lines = StreamController<String>.broadcast();
      final assembler = LineAssembler();
      final subscriptions = <StreamSubscription<dynamic>>[
        tx.onValueReceived.listen((bytes) {
          for (final line in assembler.push(bytes)) {
            lines.add(line);
          }
        }),
      ];
      device.cancelWhenDisconnected(subscriptions.first);
      await tx.setNotifyValue(true);

      final payload = (device.mtuNow - 3).clamp(20, 244);
      return BleLineTransport._(device, rx, lines, subscriptions, payload);
    } catch (_) {
      await device.disconnect();
      rethrow;
    }
  }

  @override
  Future<void> writeLine(String line) async {
    final bytes = utf8.encode('$line\n');
    for (var offset = 0; offset < bytes.length; offset += _payload) {
      final end = (offset + _payload).clamp(0, bytes.length);
      await _rx.write(
        bytes.sublist(offset, end),
        withoutResponse: false,
        timeout: 95,
      );
    }
  }

  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _lines.close();
    await device.disconnect();
  }
}
