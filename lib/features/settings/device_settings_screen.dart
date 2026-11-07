import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../ble/protocol.dart';
import '../../services.dart';
import '../../widgets/sections.dart';
import '../../widgets/states.dart';
import '../firmware/firmware_screen.dart' show FirmwareSection;
import '../provisioning/connect_screen.dart';
import '../provisioning/provisioning_screen.dart' show currentPosition;

/// Everything the web portal can change, plus settings that live on the
/// monitor itself and need a Bluetooth connection.
///
/// Pops the updated [Device], or [deleted] after deletion.
/// Name, sharing, WiFi, location and maintenance for one monitor. Shown as
/// the Settings tab of the monitor screen.
class DeviceSettingsView extends StatefulWidget {
  const DeviceSettingsView({
    super.key,
    required this.device,
    required this.onChanged,
    required this.onDeleted,
  });

  final Device device;

  /// Called with the saved device after a successful save.
  final ValueChanged<Device> onChanged;

  /// Called once the monitor has been removed from the account.
  final VoidCallback onDeleted;

  @override
  State<DeviceSettingsView> createState() => _DeviceSettingsViewState();
}

class _DeviceSettingsViewState extends State<DeviceSettingsView> {
  late final _name = TextEditingController(text: widget.device.name);
  late bool _outdoor = widget.device.isOutdoor;
  late bool _public = widget.device.isPublic;
  late bool _locationPublic = widget.device.isLocationPublic;
  late Device _device = widget.device;
  bool _saving = false;
  String? _error;
  String? _bleBusy;
  String? _bleError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _name.text.trim() != _device.name ||
      _outdoor != _device.isOutdoor ||
      _public != _device.isPublic ||
      (_public && _locationPublic) != _device.isLocationPublic;

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Mirrors DeviceSettingsPage.jsx: location sharing requires public sharing.
      final updated = await AppServices.of(context).api.updateDevice(
        _device.id,
        name: name,
        isOutdoor: _outdoor,
        isPublic: _public,
        isLocationPublic: _public && _locationPublic,
      );
      setState(() => _device = updated);
      widget.onChanged(updated);
      _snack('Settings saved');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Runs a Bluetooth action against this monitor, connecting first.
  Future<void> _withDevice(
    String label,
    Future<void> Function(AiqSession session) action,
  ) async {
    setState(() => _bleError = null);
    if (!await ConnectScreen.ensureConnected(
      context,
      expectedDeviceId: _device.deviceId,
    )) {
      return;
    }
    if (!mounted) return;
    final session = AppServices.of(context).ble.session!;
    setState(() => _bleBusy = label);
    try {
      await action(session);
    } on BleProtocolException catch (e) {
      setState(() => _bleError = e.message);
    } on ApiException catch (e) {
      setState(() => _bleError = e.message);
    } catch (e) {
      setState(() => _bleError = '$label failed: $e');
    } finally {
      if (mounted) setState(() => _bleBusy = null);
    }
  }

  Future<void> _saveOnDevice(AiqSession session) async {
    final ble = AppServices.of(context).ble;
    final result = await session.save();
    if (!result.ok) {
      throw BleProtocolException(
        result.failure == SaveFailure.wifi
            ? 'Saved, but the monitor could not join WiFi. Check the network and password.'
            : 'The monitor could not store the settings.',
      );
    }
    await ble.refreshInfo();
  }

  Future<void> _changeWifi() => _withDevice('Changing WiFi', (session) async {
    final networks = await session.scanWifi();
    if (!mounted) return;
    final choice = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WifiSheet(networks: networks),
    );
    if (choice == null) return;
    await session.setWifi(choice.$1, choice.$2);
    await _saveOnDevice(session);
    _snack('Monitor joined ${choice.$1}');
  });

  Future<void> _updateLocation() =>
      _withDevice('Updating location', (session) async {
        final position = await currentPosition();
        await session.setLocation(position.latitude, position.longitude);
        await _saveOnDevice(session);
        _snack('Location updated');
      });

  Future<void> _rotateKey() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Rotate device key?',
      message:
          'A new secret key is created and sent to the monitor over Bluetooth. The old key stops working immediately.',
      confirmLabel: 'Rotate key',
    );
    if (!confirmed || !mounted) return;
    await _withDevice('Rotating key', (session) async {
      // Only rotate while connected, so the monitor receives the new key right away.
      final rotated = await AppServices.of(context).api.rotateKey(_device.id);
      await session.setCredentials(rotated.device.deviceId, rotated.deviceKey);
      final result = await session.save();
      if (!result.ok && result.failure == SaveFailure.storage) {
        throw BleProtocolException(
          'The monitor could not store the new key. Rotate again while connected.',
        );
      }
      _snack('Device key rotated');
    });
  }

  Future<void> _showInfo() => _withDevice('Reading device info', (
    session,
  ) async {
    final info = await AppServices.of(context).ble.refreshInfo();
    if (!mounted || info == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Monitor details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Firmware: ${info.firmwareVersion}'),
            Text('Device id: ${info.deviceId}'),
            Text('MAC: ${info.mac}'),
            Text(
              'WiFi: ${info.wifiConnected ? 'connected to ${info.ssid} (${info.ip})' : 'disconnected'}',
            ),
            Text(
              info.lastUploadHttp == null
                  ? 'Last upload: none since boot'
                  : 'Last upload: HTTP ${info.lastUploadHttp}, ${info.lastUploadSecondsAgo}s ago',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  });

  Future<void> _factoryReset() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Factory reset the monitor?',
      message:
          'WiFi, location, credentials and Bluetooth pairings are erased from the monitor. '
          'It stops uploading until it is set up again. The device stays in your account.',
      confirmLabel: 'Reset',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ble = AppServices.of(context).ble;
    await _withDevice('Resetting', (session) async {
      await session.clear();
      await ble.disconnect();
      _snack('Monitor reset');
    });
  }

  Future<void> _delete() async {
    final services = AppServices.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(
        name: _device.name,
        connected: services.ble.isConnectedTo(_device.deviceId),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (services.ble.isConnectedTo(_device.deviceId)) {
        await services.ble.session!.clear().catchError((_) {});
        await services.ble.disconnect();
      }
      await services.api.deleteDevice(_device.id);
      if (mounted) widget.onDeleted();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ble = AppServices.of(context).ble;
    final idle = _bleBusy == null;
    return Scaffold(
      body: ListView(
        padding: pagePadding,
        children: [
          const SectionLabel('General'),
          SectionCard(
            children: [
              SectionField(
                child: TextField(
                  controller: _name,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SectionSwitch(
                icon: const Icon(Icons.park_outlined),
                title: 'Installed outdoors',
                value: _outdoor,
                onChanged: (value) => setState(() => _outdoor = value),
              ),
              SectionSwitch(
                icon: const Icon(Icons.public),
                title: 'Share data publicly',
                subtitle: 'Readings appear on the public map',
                value: _public,
                onChanged: (value) => setState(() => _public = value),
              ),
              SectionSwitch(
                icon: const Icon(Icons.place_outlined),
                title: 'Share exact location',
                subtitle: _public
                    ? 'Shown on the public map'
                    : 'Turn on public sharing first',
                value: _public && _locationPublic,
                onChanged: _public
                    ? (value) => setState(() => _locationPublic = value)
                    : null,
              ),
            ],
          ),
          InlineError(_error),
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            child: _dirty || _saving
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save changes'),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SectionLabel('Firmware'),
          FirmwareSection(device: _device),
          SectionLabel(
            'On the monitor',
            trailing: ListenableBuilder(
              listenable: ble,
              builder: (context, _) {
                final connected = ble.isConnectedTo(_device.deviceId);
                return _BleChip(connected: connected);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Text(
              'These need a Bluetooth connection. Put the monitor in pairing mode first.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_bleBusy != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: LinearProgressIndicator(
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
                semanticsLabel: _bleBusy,
              ),
            ),
          InlineError(_bleError),
          SectionCard(
            children: [
              SectionRow(
                icon: const Icon(Icons.wifi),
                title: 'Change WiFi network',
                onTap: _changeWifi,
                enabled: idle,
              ),
              SectionRow(
                icon: const Icon(Icons.my_location),
                title: 'Update location',
                subtitle: "Uses this phone's location",
                onTap: _updateLocation,
                enabled: idle,
              ),
              SectionRow(
                icon: const Icon(Icons.key_outlined),
                title: 'Replace device key',
                subtitle: 'The old key stops working right away',
                onTap: _rotateKey,
                enabled: idle,
              ),
              SectionRow(
                icon: const Icon(Icons.info_outline),
                title: 'Monitor details',
                onTap: _showInfo,
                enabled: idle,
              ),
              SectionRow(
                icon: const Icon(Icons.restart_alt),
                title: 'Factory reset',
                subtitle: 'Erases WiFi, location and pairing',
                destructive: true,
                onTap: _factoryReset,
                enabled: idle,
              ),
            ],
          ),
          SectionLabel('Danger zone', color: theme.colorScheme.error),
          SectionCard(
            children: [
              SectionRow(
                icon: const Icon(Icons.delete_outline),
                title: 'Delete monitor',
                subtitle: 'Removes it and its readings from your account',
                destructive: true,
                onTap: _delete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bluetooth connection state for the "On the monitor" section.
class _BleChip extends StatelessWidget {
  const _BleChip({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: connected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            size: 14,
            color: connected
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            connected ? 'Connected' : 'Not connected',
            style: theme.textTheme.labelSmall?.copyWith(
              color: connected
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _WifiSheet extends StatefulWidget {
  const _WifiSheet({required this.networks});

  final List<WifiNetwork> networks;

  @override
  State<_WifiSheet> createState() => _WifiSheetState();
}

class _WifiSheetState extends State<_WifiSheet> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Choose WiFi network',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final network in widget.networks)
              ListTile(
                selected: network.ssid == _ssid.text,
                leading: Icon(
                  network.secured ? Icons.wifi_password : Icons.wifi,
                ),
                title: Text(network.ssid),
                onTap: () => setState(() => _ssid.text = network.ssid),
              ),
            TextField(
              controller: _ssid,
              decoration: const InputDecoration(
                labelText: 'Network name (SSID)',
              ),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _ssid.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, (
                      _ssid.text.trim(),
                      _password.text,
                    )),
              child: const Text('Send to monitor'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Delete confirmation that requires typing the device name (as on the web).
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.name, required this.connected});

  final String name;
  final bool connected;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Delete device?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This permanently deletes "${widget.name}" and all of its readings and logs.'
            '${widget.connected ? ' The connected monitor is also factory reset.' : ''}',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Type "${widget.name}" to confirm',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _confirm.text.trim() == widget.name
              ? () => Navigator.pop(context, true)
              : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
