import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services.dart';
import '../../widgets/ota_badge.dart';
import '../../widgets/states.dart';
import '../../widgets/tiles.dart';
import '../device_detail/device_detail_screen.dart';
import '../firmware/firmware_screen.dart';
import '../provisioning/provisioning_screen.dart';

/// The signed-in home: the user's monitors with their latest AQI.
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key, required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  Future<List<Device>>? _devices;
  Timer? _refresh;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_devices == null) {
      _load();
      _refresh = Timer.periodic(const Duration(minutes: 1), (_) => _load());
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final future = AppServices.of(context).api.listDevices();
    setState(() => _devices = future);
    await future.catchError((_) => <Device>[]);
  }

  Future<void> _addMonitor() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<bool>(builder: (_) => const ProvisioningScreen()));
    if (mounted) await _load();
  }

  Future<void> _open(Device device) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeviceDetailScreen(device: device),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My monitors'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final ble = AppServices.of(context).ble;
              if (await confirmDialog(
                context,
                title: 'Sign out?',
                message: 'You can sign in again any time.',
                confirmLabel: 'Sign out',
              )) {
                await ble.disconnect();
                await widget.onSignOut();
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMonitor,
        icon: const Icon(Icons.add),
        label: const Text('Add monitor'),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Device>>(
          future: _devices,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done &&
                !snapshot.hasData) {
              return const LoadingView(message: 'Loading your monitors…');
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              return ErrorView(
                message: error is ApiException
                    ? error.message
                    : 'Could not load your monitors. Check your connection.',
                onRetry: _load,
              );
            }
            final devices = snapshot.data ?? const [];
            if (devices.isEmpty) {
              return EmptyView(
                icon: Icons.sensors,
                title: 'No monitors yet',
                message:
                    'Put your monitor in pairing mode and add it over Bluetooth.',
                action: FilledButton.icon(
                  onPressed: _addMonitor,
                  icon: const Icon(Icons.add),
                  label: const Text('Add monitor'),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: devices.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _DeviceCard(
                  device: devices[index],
                  onTap: () => _open(devices[index]),
                  onBadgeTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FirmwareScreen(device: devices[index]),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DeviceCard extends StatefulWidget {
  const _DeviceCard({
    required this.device,
    required this.onTap,
    required this.onBadgeTap,
  });

  final Device device;
  final VoidCallback onTap;
  final VoidCallback onBadgeTap;

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  Future<CurrentReading?>? _current;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _current ??= _fetch();
  }

  @override
  void didUpdateWidget(covariant _DeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device != widget.device) _current = _fetch();
  }

  Future<CurrentReading?> _fetch() async {
    try {
      return await AppServices.of(context).api.current(widget.device.id);
    } on ApiException catch (e) {
      if (e.isNoReadings) return null;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = widget.device;
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    device.isOutdoor ? Icons.park : Icons.home,
                    size: 20,
                    semanticLabel: device.isOutdoor ? 'Outdoor' : 'Indoor',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      device.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  OtaBadge(summary: device.ota, onTap: widget.onBadgeTap),
                ],
              ),
              const SizedBox(height: 12),
              FutureBuilder<CurrentReading?>(
                future: _current,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    return const Text('Latest reading unavailable');
                  }
                  final current = snapshot.data;
                  if (current == null) return const Text('No readings yet');
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AqiTile(
                        aqi: current.sampleCount > 0
                            ? current.metrics.aqi
                            : null,
                        caption: 'Last hour average',
                      ),
                      const SizedBox(height: 8),
                      _StatusLine(current: current),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.current});

  final CurrentReading current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = current.online ? Colors.green.shade700 : scheme.outline;
    return Row(
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(current.online ? 'Online' : 'Offline'),
        if (current.lastSeen != null) ...[
          const Text(' · '),
          Flexible(
            child: Text(
              'last seen ${relativeTime(current.lastSeen!)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

String relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}
