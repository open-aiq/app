import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services.dart';
import '../../format.dart';
import '../../widgets/aiq_app_bar.dart';
import '../../widgets/keep_last.dart';
import '../../widgets/monitor_illustration.dart';
import '../../widgets/ota_badge.dart';
import '../../widgets/soft_card.dart';
import '../../widgets/states.dart';
import '../../widgets/tiles.dart';
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
                onBadgeTap: () => _open(device, DeviceTab.updates),
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
            const SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CardHeader(
                    icon: SkeletonShape(radius: 10, child: Icon(Icons.home)),
                    name: SkeletonShape(child: _CardName('Living room')),
                    status: SkeletonShape(child: _StatusLine.placeholder()),
                  ),
                  SizedBox(height: _cardGap),
                  _ReadingRow.placeholder(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Space between a card's header and its readings.
const _cardGap = 18.0;

/// Icon, name, then status and update badge on the right.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.name,
    required this.status,
    this.badge,
  });

  final Widget icon;
  final Widget name;
  final Widget status;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        icon,
        const SizedBox(width: 10),
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: name),
        ),
        const SizedBox(width: 12),
        status,
        if (badge != null) ...[const SizedBox(width: 8), badge!],
      ],
    );
  }
}

class _CardName extends StatelessWidget {
  const _CardName(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

/// The AQI block with temperature and PM2.5 beside it.
class _ReadingRow extends StatelessWidget {
  const _ReadingRow({super.key, required this.reading}) : loading = false;

  const _ReadingRow.placeholder() : reading = null, loading = true;

  final CurrentReading? reading;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final current = reading;
    final hasData = current != null && current.sampleCount > 0;
    final m = current?.metrics;
    final aqi = AqiBlock(aqi: hasData ? m!.aqi : null);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 5,
          child: loading ? SkeletonShape(radius: 20, child: aqi) : aqi,
        ),
        const SizedBox(width: 18),
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Stat(
                icon: Icons.thermostat_outlined,
                label: 'Temperature',
                value: hasData ? formatNumber(m!.temperature, digits: 1) : '--',
                unit: '°C',
                loading: loading,
              ),
              const SizedBox(height: 22),
              _Stat(
                icon: Icons.grain,
                label: 'PM2.5',
                value: hasData ? formatNumber(m!.pm25, digits: 1) : '--',
                unit: 'µg/m³',
                loading: loading,
              ),
            ],
          ),
        ),
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
    final device = widget.device;
    return SoftCard(
      onTap: widget.onTap,
      child: ListenableBuilder(
        listenable: _current,
        builder: (context, _) {
          final loading = _current.isFirstLoad;
          // A failed first load and "no readings yet" both show the same
          // layout with empty values, so the card keeps its size.
          final reading = _current.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(
                icon: Icon(
                  device.isOutdoor ? Icons.park_outlined : Icons.home_outlined,
                  size: 22,
                  color: Theme.of(context).colorScheme.secondary,
                  semanticLabel: device.isOutdoor ? 'Outdoor' : 'Indoor',
                ),
                name: _CardName(device.name),
                status: SoftSwitcher(
                  child: loading
                      ? const Skeleton(
                          key: ValueKey('loading'),
                          child: SkeletonShape(
                            child: _StatusLine.placeholder(),
                          ),
                        )
                      : _StatusLine(
                          key: const ValueKey('status'),
                          online: reading?.online ?? false,
                          seen: reading?.lastSeen,
                          unavailable: !_current.hasData,
                        ),
                ),
                badge: OtaBadge(
                  summary: device.ota,
                  onTap: widget.onBadgeTap,
                  compact: true,
                ),
              ),
              const SizedBox(height: _cardGap),
              SoftSwitcher(
                child: loading
                    ? const Skeleton(
                        key: ValueKey('loading'),
                        label: 'Loading the latest reading',
                        child: _ReadingRow.placeholder(),
                      )
                    : _ReadingRow(
                        key: const ValueKey('reading'),
                        reading: reading,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One reading beside the AQI block: an icon as tall as the two lines of
/// text next to it, centred against them.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: muted);
    final scaler = MediaQuery.textScalerOf(context);
    double lineHeight(TextStyle? style) =>
        scaler.scale(style?.fontSize ?? 14) * (style?.height ?? 1.2);
    final iconSize = lineHeight(valueStyle) + lineHeight(labelStyle);

    Widget shape(Widget child, [double radius = 6]) =>
        loading ? SkeletonShape(radius: radius, child: child) : child;

    return Semantics(
      label: loading ? null : '$label $value $unit',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          shape(
            Icon(icon, size: iconSize, color: theme.colorScheme.secondary),
            iconSize / 2,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                shape(
                  Text.rich(
                    TextSpan(
                      text: loading ? '00.0' : value,
                      style: valueStyle,
                      children: [
                        TextSpan(
                          text: ' $unit',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                  ),
                ),
                shape(Text(label, maxLines: 1, style: labelStyle)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Online or offline as an icon, then how long ago the monitor was seen.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    super.key,
    required this.online,
    required this.seen,
    this.unavailable = false,
  });

  const _StatusLine.placeholder()
    : online = true,
      seen = null,
      unavailable = false;

  final bool online;
  final DateTime? seen;

  /// The reading couldn't be loaded at all.
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = unavailable
        ? 'Unavailable'
        : seen == null
        ? '--m ago'
        : shortAgo(seen!);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          online ? Icons.wifi : Icons.wifi_off,
          size: 16,
          color: online ? scheme.secondary : scheme.outline,
          semanticLabel: online ? 'Online' : 'Offline',
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
