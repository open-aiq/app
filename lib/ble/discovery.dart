import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
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

/// A permission Android still needs before a scan can find anything.
enum ScanBlocker {
  /// "Nearby devices" (scan and connect), on Android 12 and newer.
  bluetooth,

  /// Location, which Android 11 and older require for any Bluetooth scan.
  location,
}

/// Android 11, the last version that scans through the location permission.
const _lastLocationScanSdk = 30;

/// Which permission is missing for a scan on Android API level [sdkInt], or
/// null when scanning can go ahead.
///
/// Android 11 and older report the Bluetooth permissions as granted and need
/// location instead; without it a scan runs but silently finds nothing.
/// Android 12 and newer need only the Bluetooth permissions.
ScanBlocker? scanBlocker({
  required int sdkInt,
  required bool bluetoothGranted,
  required bool locationGranted,
}) {
  if (sdkInt <= _lastLocationScanSdk) {
    return locationGranted ? null : ScanBlocker.location;
  }
  return bluetoothGranted ? null : ScanBlocker.bluetooth;
}

/// Classic BLE scan for devices advertising the Nordic UART Service.
class BleScanner {
  /// Requests the runtime permissions scanning needs on Android. Returns what
  /// is still missing, or null when the scan can start.
  static Future<ScanBlocker?> ensurePermissions() async {
    if (!Platform.isAndroid) return null;
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    bool granted(Permission permission) =>
        statuses[permission]?.isGranted ?? false;
    final android = await DeviceInfoPlugin().androidInfo;
    return scanBlocker(
      sdkInt: android.version.sdkInt,
      bluetoothGranted:
          granted(Permission.bluetoothScan) &&
          granted(Permission.bluetoothConnect),
      locationGranted: granted(Permission.locationWhenInUse),
    );
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
