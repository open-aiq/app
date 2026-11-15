import 'dart:async';

import 'package:flutter/material.dart';

import '../../ble/discovery.dart';
import '../../ble/protocol.dart';
import '../../services.dart';
import '../../widgets/aiq_app_bar.dart';
import '../../widgets/monitor_illustration.dart';
import '../../widgets/sections.dart';
import '../../widgets/soft_card.dart';
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
    final blocker = await BleScanner.ensurePermissions();
    if (!mounted) return;
    if (blocker != null) {
      setState(
        () => _error = switch (blocker) {
          ScanBlocker.bluetooth =>
            'Allow Bluetooth ("Nearby devices") access to find the monitor.',
          ScanBlocker.location =>
            'This version of Android needs location access to find nearby '
                "monitors. Allow it, then scan again. If your phone doesn't "
                'ask, turn it on for this app in Settings.',
        },
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
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final Widget body;
    if (_connectingTo != null) {
      body = WaitingView(
        key: const ValueKey('connecting'),
        title: 'Connecting to $_connectingTo…',
        message: 'When asked, enter the 6-digit code shown on the monitor.',
      );
    } else {
      body = ListView(
        key: const ValueKey('pick'),
        padding: pagePadding,
        children: [
          SoftCard(
            child: Row(
              children: [
                const MonitorIllustration(size: 88),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Put it in pairing mode',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Hold both buttons for 3 seconds until the screen shows PAIRING. '
                        'Bluetooth stays on for 5 minutes.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
            child: Text(
              'Development board without buttons? Type BTN:PAIR in the serial monitor.',
              style: muted,
            ),
          ),
          InlineError(_error),
          const SizedBox(height: 20),
          if (_accessorySetup == null)
            Center(child: Text('Checking Bluetooth…', style: muted))
          else if (_accessorySetup!) ...[
            FilledButton.icon(
              onPressed: _pickWithAccessorySetup,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Find a new monitor'),
            ),
            if (_found.isNotEmpty) ...[
              const SectionLabel('Monitors on this iPhone'),
              SectionCard(
                children: [
                  for (final device in _found)
                    SectionRow(
                      icon: const MonitorGlyph(),
                      title: device.name,
                      subtitle: 'Must be in pairing mode',
                      onTap: () => _connect(device),
                    ),
                ],
              ),
            ],
          ] else ...[
            FilledButton.icon(
              onPressed: _scanning ? null : _startScan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(_scanning ? 'Searching…' : 'Search for monitors'),
            ),
            if (_scanning || _found.isNotEmpty) ...[
              const SectionLabel('Nearby'),
              SoftSwitcher(
                child: _found.isEmpty
                    ? const Skeleton(
                        key: ValueKey('searching'),
                        label: 'Searching for monitors',
                        child: SectionCard(
                          children: [
                            SkeletonShape(
                              child: SectionRow(
                                icon: Icon(Icons.sensors),
                                title: 'Open AIQ monitor',
                                subtitle: 'Signal -60 dBm',
                              ),
                            ),
                          ],
                        ),
                      )
                    : SectionCard(
                        key: const ValueKey('found'),
                        children: [
                          for (final device in _found)
                            SectionRow(
                              icon: const MonitorGlyph(),
                              title: device.name,
                              subtitle: device.rssi == null
                                  ? null
                                  : 'Signal ${device.rssi} dBm',
                              onTap: () => _connect(device),
                            ),
                        ],
                      ),
              ),
            ],
            if (!_scanning && _found.isEmpty && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
                child: Text(
                  "No monitors found yet. Check it shows PAIRING, then search again.",
                  style: muted,
                ),
              ),
          ],
        ],
      );
    }
    return Scaffold(
      appBar: AiqAppBar(title: widget.title),
      body: SoftSwitcher(child: body),
    );
  }
}
