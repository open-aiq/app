import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services.dart';
import '../../widgets/aiq_app_bar.dart';
import '../../widgets/keep_last.dart';
import '../../widgets/monitor_card.dart';
import '../../widgets/monitor_illustration.dart';
import '../../widgets/states.dart';
import '../device_detail/device_detail_screen.dart';
import '../provisioning/provisioning_screen.dart';

/// The signed-in home: the user's monitors with their latest AQI.
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

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

  Future<void> _open(
    Device device, [
    DeviceTab tab = DeviceTab.overview,
  ]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeviceDetailScreen(device: device, initialTab: tab),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AiqAppBar(title: 'My monitors'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMonitor,
        icon: const MonitorGlyph(),
        label: const Text('Add monitor'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _devices,
          builder: (context, _) => SoftSwitcher(child: _content()),
        ),
      ),
    );
  }

  /// The list, or the skeleton, error or empty state it fades in from.
  Widget _content() {
    if (_devices.isFirstLoad) {
      return const KeyedSubtree(
        key: ValueKey('skeleton'),
        child: _DeviceListSkeleton(),
      );
    }
    if (!_devices.hasData) {
      final error = _devices.error;
      return KeyedSubtree(
        key: const ValueKey('error'),
        child: ErrorView(
          message: error is ApiException
              ? error.message
              : 'Could not load your monitors. Check your connection.',
          onRetry: _load,
        ),
      );
    }
    final devices = _devices.data!;
    final note = _devices.error == null
        ? null
        : QuietNote(updatedAt: _devices.updatedAt, onRetry: _load);
    if (devices.isEmpty) {
      return KeyedSubtree(
        key: const ValueKey('empty'),
        child: RefreshIndicator(
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
                    illustration: const MonitorIllustration(),
                    title: 'No monitors yet',
                    message:
                        'Hold both buttons on your monitor for 3 seconds, '
                        'then add it here over Bluetooth.',
                    action: FilledButton.icon(
                      onPressed: _addMonitor,
                      icon: const MonitorGlyph(),
                      label: const Text('Add monitor'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return KeyedSubtree(
      key: const ValueKey('list'),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (note != null) ...[note, const SizedBox(height: 8)],
            for (final (index, device) in devices.indexed) ...[
              if (index > 0) const SizedBox(height: 16),
              _DeviceCard(
                key: ValueKey(device.id),
                device: device,
                tick: _tick,
                onTap: () => _open(device),
                onBadgeTap: () => _open(device, DeviceTab.settings),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// First-load placeholder: the same cards, drawn as soft shapes.
class _DeviceListSkeleton extends StatelessWidget {
  const _DeviceListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      label: 'Loading your monitors',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            const MonitorCardSkeleton(),
          ],
        ],
      ),
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
    return ListenableBuilder(
      listenable: _current,
      builder: (context, _) => MonitorCard(
        device: widget.device,
        // A failed first load and "no readings yet" both show the same
        // layout with empty values, so the card keeps its size.
        reading: _current.data,
        loading: _current.isFirstLoad,
        unavailable: !_current.hasData,
        onTap: widget.onTap,
        onBadgeTap: widget.onBadgeTap,
      ),
    );
  }
}
