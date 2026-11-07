import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services.dart';
import '../../widgets/keep_last.dart';
import '../../widgets/ota_badge.dart';
import '../../widgets/states.dart';
import '../../widgets/tiles.dart';
import '../account/account.dart';
import '../account/settings_screen.dart';
import '../device_detail/device_detail_screen.dart';
import '../firmware/firmware_screen.dart';
import '../provisioning/provisioning_screen.dart';

/// The signed-in home: the user's monitors with their latest AQI.
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key, required this.onSignOut, this.account});

  final Future<void> Function() onSignOut;
  final Account? account;

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  final _devices = KeepLast<List<Device>>();
  Timer? _refresh;

  /// Bumped on every refresh so each card quietly reloads its reading too.
  int _tick = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_refresh == null) {
      _load();
      _refresh = Timer.periodic(const Duration(minutes: 1), (_) => _load());
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _devices.dispose();
    super.dispose();
  }

  Future<void> _load() {
    final api = AppServices.of(context).api;
    setState(() => _tick++);
    return _devices.load(api.listDevices);
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

  Future<void> _signOut() async {
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My monitors'),
        actions: [
          _AccountMenu(
            account: widget.account,
            onSettings: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(account: widget.account),
              ),
            ),
            onSignOut: _signOut,
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMonitor,
        icon: const Icon(Icons.add),
        label: const Text('Add monitor'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _devices,
          builder: (context, _) {
            if (_devices.isFirstLoad) {
              return const _DeviceListSkeleton();
            }
            if (!_devices.hasData) {
              final error = _devices.error;
              return ErrorView(
                message: error is ApiException
                    ? error.message
                    : 'Could not load your monitors. Check your connection.',
                onRetry: _load,
              );
            }
            final devices = _devices.data!;
            final note = _devices.error == null
                ? null
                : QuietNote(updatedAt: _devices.updatedAt, onRetry: _load);
            if (devices.isEmpty) {
              return RefreshIndicator(
                onRefresh: _load,
                child: LayoutBuilder(
                  builder: (context, constraints) => ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ?note,
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 64,
                        ),
                        child: EmptyView(
                          icon: Icons.sensors,
                          title: 'No monitors yet',
                          message:
                              'Put your monitor in pairing mode and add it over Bluetooth.',
                          action: FilledButton.icon(
                            onPressed: _addMonitor,
                            icon: const Icon(Icons.add),
                            label: const Text('Add monitor'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  if (note != null) ...[note, const SizedBox(height: 8)],
                  for (final (index, device) in devices.indexed) ...[
                    if (index > 0) const SizedBox(height: 12),
                    _DeviceCard(
                      key: ValueKey(device.id),
                      device: device,
                      tick: _tick,
                      onTap: () => _open(device),
                      onBadgeTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FirmwareScreen(device: device),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The avatar in the app bar. It opens a menu with the profile, Settings and
/// Sign out.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu({
    required this.account,
    required this.onSettings,
    required this.onSignOut,
  });

  final Account? account;
  final VoidCallback onSettings;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MenuAnchor(
      alignmentOffset: const Offset(-180, 4),
      menuChildren: [
        if (account != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Row(
                children: [
                  AccountAvatar(account: account, radius: 18),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account!.name,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (account!.email != null &&
                            account!.email != account!.name)
                          Text(
                            account!.email!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (account != null) const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.settings_outlined),
          onPressed: onSettings,
          child: const Text('Settings'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: onSignOut,
          child: const Text('Sign out'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Account and settings',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: AccountAvatar(account: account),
      ),
    );
  }
}

/// First-load placeholder shaped like a couple of monitor cards.
class _DeviceListSkeleton extends StatelessWidget {
  const _DeviceListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      label: 'Loading your monitors',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            const Card.outlined(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: _CardBodySkeleton(withTitle: true),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardBodySkeleton extends StatelessWidget {
  const _CardBodySkeleton({this.withTitle = false});

  final bool withTitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (withTitle) ...[
          const SkeletonBlock(width: 140, height: 18),
          const SizedBox(height: 16),
        ],
        const SkeletonBlock(height: 64, radius: 12),
        const SizedBox(height: 12),
        const SkeletonBlock(width: 180, height: 14),
      ],
    );
  }
}

class _DeviceCard extends StatefulWidget {
  const _DeviceCard({
    super.key,
    required this.device,
    required this.tick,
    required this.onTap,
    required this.onBadgeTap,
  });

  final Device device;

  /// Changes whenever the list refreshes; the card then reloads its reading.
  final int tick;
  final VoidCallback onTap;
  final VoidCallback onBadgeTap;

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  final _current = KeepLast<CurrentReading?>();
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _fetch();
    }
  }

  @override
  void didUpdateWidget(covariant _DeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tick != widget.tick) _fetch();
  }

  @override
  void dispose() {
    _current.dispose();
    super.dispose();
  }

  void _fetch() {
    final api = AppServices.of(context).api;
    _current.load(() async {
      try {
        return await api.current(widget.device.id);
      } on ApiException catch (e) {
        if (e.isNoReadings) return null;
        rethrow;
      }
    });
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
              ListenableBuilder(
                listenable: _current,
                builder: (context, _) {
                  if (_current.isFirstLoad) {
                    return const Skeleton(
                      label: 'Loading the latest reading',
                      child: _CardBodySkeleton(),
                    );
                  }
                  if (!_current.hasData) {
                    return Text(
                      'Latest reading unavailable',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    );
                  }
                  final current = _current.data;
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
