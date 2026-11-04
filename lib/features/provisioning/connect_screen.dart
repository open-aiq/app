import 'dart:async';

import 'package:flutter/material.dart';

import '../../ble/discovery.dart';
import '../../ble/protocol.dart';
import '../../services.dart';
import '../../widgets/states.dart';

/// Finds a monitor in pairing mode and opens a secure BLE session to it.
///
/// Pops `true` once [AppServices.ble] is connected. With [expectedDeviceId]
/// (`dev_…`), a different monitor is rejected.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    super.key,
    this.expectedDeviceId,
    this.title = 'Connect to monitor',
  });

  final String? expectedDeviceId;
  final String title;

  /// Connects (if not already connected to the expected device) and reports success.
  static Future<bool> ensureConnected(
    BuildContext context, {
    String? expectedDeviceId,
  }) async {
    final ble = AppServices.of(context).ble;
    if (ble.isConnected &&
        (expectedDeviceId == null || ble.isConnectedTo(expectedDeviceId))) {
      return true;
    }
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConnectScreen(expectedDeviceId: expectedDeviceId),
      ),
    );
    return connected ?? false;
  }

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  bool? _accessorySetup;
  bool _scanning = false;
  String? _connectingTo;
  String? _error;
  StreamSubscription<List<FoundDevice>>? _scan;
  List<FoundDevice> _found = const [];

  @override
  void initState() {
    super.initState();
    AccessorySetup.isSupported().then((supported) async {
      if (mounted) setState(() => _accessorySetup = supported);
      if (supported) {
        final known = await AccessorySetup.knownAccessories().catchError(
          (_) => <FoundDevice>[],
        );
        if (mounted) setState(() => _found = known);
      }
    });
  }

  @override
  void dispose() {
    _scan?.cancel();
    BleScanner.stop();
    super.dispose();
  }

  Future<void> _pickWithAccessorySetup() async {
    setState(() => _error = null);
    try {
      final found = await AccessorySetup.pick();
      if (found != null) await _connect(found);
    } catch (e) {
      setState(() => _error = 'Could not show the accessory picker: $e');
    }
  }

  Future<void> _startScan() async {
    setState(() {
      _error = null;
      _found = const [];
    });
    if (!await BleScanner.ensurePermissions()) {
      setState(
        () => _error =
            'Allow Bluetooth ("Nearby devices") access to find the monitor.',
      );
      return;
    }
    await _scan?.cancel();
    setState(() => _scanning = true);
    _scan = BleScanner.scan().listen(
      (found) => setState(() => _found = found),
      onError: (Object e) => setState(() {
        _error = e.toString();
        _scanning = false;
      }),
      onDone: () => setState(() => _scanning = false),
    );
    Future<void>.delayed(const Duration(seconds: 15), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  Future<void> _connect(FoundDevice found) async {
    await _scan?.cancel();
    await BleScanner.stop();
    if (!mounted) return;
    final ble = AppServices.of(context).ble;
    setState(() {
      _connectingTo = found.name;
      _error = null;
    });
    try {
      await ble.connect(found);
      final expected = widget.expectedDeviceId;
      if (expected != null && ble.info?.deviceId != expected) {
        final actual = ble.info?.deviceId;
        await ble.disconnect();
        throw BleProtocolException(
          actual == null || actual.isEmpty
              ? 'That monitor is not set up yet. Use "Add monitor" instead.'
              : 'That is a different monitor ($actual).',
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectingTo = null;
          _error = e is BleProtocolException
              ? e.message
              : 'Could not connect. Make sure the monitor is still in pairing mode and that you entered the code shown on it.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: _connectingTo != null
            ? LoadingView(
                message:
                    'Connecting to $_connectingTo…\n\nWhen asked, enter the 6-digit code shown on the monitor.',
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card.outlined(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Put the monitor in pairing mode',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Hold both buttons on the monitor for 3 seconds until its screen shows PAIRING. '
                            'Bluetooth stays on for 5 minutes.\n\n'
                            'Development board without buttons: type BTN:PAIR in the serial monitor.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  InlineError(_error),
                  const SizedBox(height: 8),
                  if (_accessorySetup == null)
                    const LoadingView(message: 'Checking Bluetooth…')
                  else if (_accessorySetup!) ...[
                    FilledButton.icon(
                      onPressed: _pickWithAccessorySetup,
                      icon: const Icon(Icons.bluetooth_searching),
                      label: const Text('Find a new monitor'),
                    ),
                    if (_found.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Monitors on this iPhone',
                        style: theme.textTheme.titleSmall,
                      ),
                      for (final device in _found)
                        ListTile(
                          leading: const Icon(Icons.sensors),
                          title: Text(device.name),
                          subtitle: const Text('Must be in pairing mode'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _connect(device),
                        ),
                    ],
                  ] else ...[
                    FilledButton.icon(
                      onPressed: _scanning ? null : _startScan,
                      icon: const Icon(Icons.bluetooth_searching),
                      label: Text(
                        _scanning ? 'Searching…' : 'Search for monitors',
                      ),
                    ),
                    if (_scanning)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                    for (final device in _found)
                      ListTile(
                        leading: const Icon(Icons.sensors),
                        title: Text(device.name),
                        subtitle: device.rssi == null
                            ? null
                            : Text('Signal ${device.rssi} dBm'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _connect(device),
                      ),
                    if (!_scanning && _found.isEmpty && _error == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Text(
                          'No monitors found yet. Check that the monitor shows PAIRING and search again.',
                        ),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}
