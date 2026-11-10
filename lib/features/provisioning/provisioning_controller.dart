import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../ble/protocol.dart';

enum ProvisioningStep {
  inspecting,
  register,
  wifi,
  location,
  saving,
  verifying,
  done,
}

/// Drives provisioning of one connected device:
/// inspect (INFO) -> register on the backend if needed -> WiFi -> location ->
/// SAVE -> wait until the backend reports the device online.
class ProvisioningController extends ChangeNotifier {
  ProvisioningController({
    required this.session,
    required this.api,
    this.pollInterval = const Duration(seconds: 5),
    this.verifyTimeout = const Duration(minutes: 7),
  });

  final AiqSession session;
  final ApiClient api;
  final Duration pollInterval;

  /// How long to wait for the first reading. The monitor samples the air in a
  /// burst every 5 minutes and uploads after one, so the first reading can
  /// take 3 to 5 minutes; 7 leaves room for a slow WiFi join.
  final Duration verifyTimeout;

  ProvisioningStep step = ProvisioningStep.inspecting;
  bool busy = false;
  String? error;
  DeviceInfo? info;

  /// The backend device being provisioned (existing or just registered).
  Device? device;

  /// The device holds a `dev_…` id that is not in this account.
  bool registeredElsewhere = false;
  List<WifiNetwork> networks = const [];
  String? ip;
  bool verifyTimedOut = false;

  /// The last poll for the first reading could not reach the backend (phone
  /// offline, request timed out). Polling carries on regardless.
  bool serverUnreachable = false;

  /// How long the current wait for the first reading has lasted, as of the
  /// last poll.
  Duration verifyElapsed = Duration.zero;
  bool _disposed = false;

  Future<void> start() => _run(() async {
    info = await session.info();
    final devices = await api.listDevices();
    final id = info!.deviceId;
    final match = devices
        .where((d) => id.isNotEmpty && d.deviceId == id)
        .firstOrNull;
    if (match != null && info!.deviceKeySet) {
      device = match;
      step = ProvisioningStep.wifi;
    } else {
      registeredElsewhere = id.isNotEmpty && match == null;
      step = ProvisioningStep.register;
    }
  });

  /// Registers a new backend device and stages its credentials on the device.
  Future<void> register({
    required String name,
    bool isOutdoor = false,
    bool isPublic = false,
    bool isLocationPublic = false,
  }) => _run(() async {
    final created = await api.registerDevice(
      name: name,
      isOutdoor: isOutdoor,
      isPublic: isPublic,
      isLocationPublic: isLocationPublic,
    );
    device = created.device;
    // The key exists only in this response; send it before anything else.
    await session.setCredentials(created.device.deviceId, created.deviceKey);
    step = ProvisioningStep.wifi;
  });

  Future<void> scanWifi() => _run(() async {
    networks = await session.scanWifi();
  });

  Future<void> submitWifi(String ssid, String password) => _run(() async {
    if (ssid.trim().isEmpty) {
      throw BleProtocolException('Choose a WiFi network.');
    }
    await session.setWifi(ssid, password);
    step = ProvisioningStep.location;
  });

  /// Sends the location (when given), saves, then verifies the device online.
  Future<void> submitLocation({double? lat, double? lon}) async {
    final saved = await _run(() async {
      if (lat != null && lon != null) await session.setLocation(lat, lon);
      step = ProvisioningStep.saving;
      _notify();
      final result = await session.save();
      if (!result.ok) {
        step = result.failure == SaveFailure.wifi
            ? ProvisioningStep.wifi
            : ProvisioningStep.location;
        throw BleProtocolException(
          result.failure == SaveFailure.wifi
              ? 'The device could not join that WiFi network. Check the password and that it is a 2.4 GHz network.'
              : 'The device could not store the settings. Try again.',
        );
      }
      ip = result.ip;
      step = ProvisioningStep.verifying;
    });
    if (saved) await _verifyOnline();
  }

  /// Issues a fresh device key and stores it on the device (recovery when the
  /// original key never reached it).
  Future<void> rotateAndResendKey() => _run(() async {
    final current = device;
    if (current == null) return;
    final rotated = await api.rotateKey(current.id);
    await session.setCredentials(rotated.device.deviceId, rotated.deviceKey);
    final result = await session.save();
    if (!result.ok && result.failure == SaveFailure.storage) {
      throw BleProtocolException('The device could not store the new key.');
    }
  });

  Future<void> retryVerify() => _verifyOnline();

  Future<void> _verifyOnline() async {
    final current = device;
    if (current == null) return;
    verifyTimedOut = false;
    serverUnreachable = false;
    verifyElapsed = Duration.zero;
    step = ProvisioningStep.verifying;
    _notify();
    final waited = Stopwatch()..start();
    while (!_disposed && waited.elapsed < verifyTimeout) {
      try {
        final reading = await api.current(current.id);
        serverUnreachable = false;
        if (reading.online) {
          step = ProvisioningStep.done;
          _notify();
          return;
        }
      } on ApiException catch (e) {
        // The backend answered, so the connection is fine.
        serverUnreachable = false;
        if (!e.isNoReadings) error = e.message;
      } catch (_) {
        // No connection or a slow one (ClientException, TimeoutException…).
        // Keep polling: the monitor may well be uploading in the meantime.
        serverUnreachable = true;
      }
      verifyElapsed = waited.elapsed;
      _notify();
      await Future<void>.delayed(pollInterval);
    }
    verifyElapsed = waited.elapsed;
    verifyTimedOut = true;
    _notify();
  }

  /// Runs [action] with busy/error bookkeeping; returns whether it succeeded.
  Future<bool> _run(Future<void> Function() action) async {
    busy = true;
    error = null;
    _notify();
    try {
      await action();
      return true;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } on BleProtocolException catch (e) {
      error = e.message;
      return false;
    } on TimeoutException {
      error =
          'The device stopped responding. Make sure it is still in pairing mode.';
      return false;
    } catch (e) {
      error = 'Something went wrong: $e';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
