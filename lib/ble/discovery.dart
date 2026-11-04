import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'protocol.dart';

/// A device found in pairing mode.
class FoundDevice {
  const FoundDevice({required this.remoteId, required this.name, this.rssi});

  /// FlutterBluePlus remote id (iOS peripheral UUID / Android MAC).
  final String remoteId;
  final String name;
  final int? rssi;

  BluetoothDevice get bluetoothDevice => BluetoothDevice.fromId(remoteId);
}

/// iOS AccessorySetupKit bridge (ios/Runner/AppDelegate.swift).
///
/// On iOS 18+ the system shows its own accessory sheet, so the app never needs
/// the broad Bluetooth permission prompt; the picked accessory is then
/// reachable through CoreBluetooth (and FlutterBluePlus) by its identifier.
class AccessorySetup {
  static const _channel = MethodChannel('org.openaiq/accessory_setup');

  static Future<bool> isSupported() async {
    if (!Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Monitors this app was already authorized for (reconnect without the picker).
  static Future<List<FoundDevice>> knownAccessories() async {
    final list =
        await _channel.invokeListMethod<Map<Object?, Object?>>(
          'listAccessories',
        ) ??
        const [];
    return [
      for (final item in list)
        if (item['bluetoothIdentifier'] is String)
          FoundDevice(
            remoteId: item['bluetoothIdentifier'] as String,
            name: item['name'] as String? ?? 'Open AIQ monitor',
          ),
    ];
  }

  /// Shows the system picker. Returns null when the user dismissed it.
  static Future<FoundDevice?> pick() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'showPicker',
    );
    final id = result?['bluetoothIdentifier'] as String?;
    if (id == null) return null;
    return FoundDevice(
      remoteId: id,
      name: result?['name'] as String? ?? 'Open AIQ monitor',
    );
  }
}

/// Classic BLE scan for devices advertising the Nordic UART Service.
class BleScanner {
  /// Requests the runtime permissions scanning needs on Android 12+ and older.
  static Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final scan = statuses[Permission.bluetoothScan];
    final connect = statuses[Permission.bluetoothConnect];
    // Location is only required on Android 11 and older; scan/connect are
    // reported as granted there.
    return (scan?.isGranted ?? false) && (connect?.isGranted ?? false);
  }

  /// Streams the devices seen so far, strongest first, for [duration].
  static Stream<List<FoundDevice>> scan({
    Duration duration = const Duration(seconds: 15),
  }) async* {
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      await FlutterBluePlus.adapterState
          .where((state) => state == BluetoothAdapterState.on)
          .first
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw BleProtocolException(
              'Turn on Bluetooth to find the device.',
            ),
          );
    }
    await FlutterBluePlus.startScan(
      withServices: [Guid(nusServiceUuid)],
      timeout: duration,
    );
    yield* FlutterBluePlus.scanResults.map((results) {
      final found = [
        for (final result in results)
          FoundDevice(
            remoteId: result.device.remoteId.str,
            name: result.advertisementData.advName.isNotEmpty
                ? result.advertisementData.advName
                : result.device.platformName.isNotEmpty
                ? result.device.platformName
                : 'Open AIQ monitor',
            rssi: result.rssi,
          ),
      ]..sort((a, b) => (b.rssi ?? -127).compareTo(a.rssi ?? -127));
      return found;
    });
  }

  static Future<void> stop() => FlutterBluePlus.stopScan();
}
