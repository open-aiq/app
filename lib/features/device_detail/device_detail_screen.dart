import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../aqi.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../ble/protocol.dart';
import '../../services.dart';
import '../../widgets/aiq_app_bar.dart';
import '../../widgets/keep_last.dart';
import '../../widgets/monitor_illustration.dart';
import '../../widgets/ota_badge.dart';
import '../../widgets/states.dart';
import '../../widgets/tiles.dart';
import '../../format.dart';
import '../firmware/firmware_screen.dart' show FirmwareView;
import '../logs/logs_screen.dart' show LogsView;
import '../provisioning/connect_screen.dart';
import '../settings/device_settings_screen.dart' show DeviceSettingsView;
import 'history_series.dart';

/// The sections of a monitor, in bottom-bar order.
enum DeviceTab { overview, live, logs, updates, settings }

/// One monitor. A bottom navigation bar switches between its sections; tabs
/// never change on a swipe, so the history chart keeps horizontal drags.
class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({
    super.key,
    required this.device,
    this.initialTab = DeviceTab.overview,
  });

  final Device device;
  final DeviceTab initialTab;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late Device _device = widget.device;
  late DeviceTab _tab = widget.initialTab;

  /// Tabs are built the first time they're opened, then kept, so switching
  /// back doesn't reload or lose your place.
  late final Set<DeviceTab> _opened = {widget.initialTab};

  /// The latest reading, shared by the top bar's status and the Overview tab.
  final _current = KeepLast<CurrentReading?>();
  Timer? _refresh;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_refresh == null) {
      _loadCurrent();
      // Devices upload every 10 minutes; refreshing every minute is plenty.
      _refresh = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _loadCurrent(),
      );
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _current.dispose();
    super.dispose();
  }

  Future<void> _loadCurrent() {
    final api = AppServices.of(context).api;
    return _current.load(() async {
      try {
        return await api.current(_device.id);
      } on ApiException catch (e) {
        if (e.isNoReadings) return null;
        rethrow;
      }
    });
  }

  String? get _status {
    final current = _current.data;
    if (current == null) return null;
    final seen = current.lastSeen;
    final state = current.online ? 'Online' : 'Offline';
    return seen == null ? state : '$state · ${shortAgo(seen)}';
  }

  void _select(DeviceTab tab) => setState(() {
    _tab = tab;
    _opened.add(tab);
  });

  Widget _build(DeviceTab tab) => switch (tab) {
    DeviceTab.overview => _OnlineTab(
      device: _device,
      current: _current,
      reloadCurrent: _loadCurrent,
    ),
    DeviceTab.live => _LiveTab(device: _device),
    DeviceTab.logs => LogsView(device: _device),
    DeviceTab.updates => FirmwareView(device: _device),
    DeviceTab.settings => DeviceSettingsView(
      device: _device,
      onChanged: (device) => setState(() => _device = device),
      onDeleted: () => Navigator.of(context).pop(),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final ota = _device.ota;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const AiqAppBar(title: '').preferredSize,
        child: ListenableBuilder(
          listenable: _current,
          builder: (context, _) => AiqAppBar(
            title: _device.name,
            subtitle: _status,
            chip: _tab == DeviceTab.updates
                ? null
                : OtaBadge(
                    summary: ota,
                    onTap: () => _select(DeviceTab.updates),
                  ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _tab.index,
        children: [
          for (final tab in DeviceTab.values)
            _opened.contains(tab)
                ? TickerMode(enabled: tab == _tab, child: _build(tab))
                : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (index) => _select(DeviceTab.values[index]),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Overview',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bluetooth),
            selectedIcon: Icon(Icons.bluetooth_connected),
            label: 'Live',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Logs',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: ota?.needsAttention ?? false,
              child: const Icon(Icons.system_update_outlined),
            ),
            selectedIcon: const Icon(Icons.system_update),
            label: 'Updates',
          ),
          const NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _OnlineTab extends StatefulWidget {
  const _OnlineTab({
    required this.device,
    required this.current,
    required this.reloadCurrent,
  });

  final Device device;

  /// Owned by the monitor screen, which also shows it in the top bar.
  final KeepLast<CurrentReading?> current;
  final Future<void> Function() reloadCurrent;

  @override
  State<_OnlineTab> createState() => _OnlineTabState();
}

class _OnlineTabState extends State<_OnlineTab>
    with AutomaticKeepAliveClientMixin {
  static const _timelines = {
    'daily': '24 h',
    'weekly': '7 d',
    'monthly': '30 d',
    'yearly': '12 mo',
  };

  late final _current = widget.current;

  /// Every range at once, so picking 24 h, 7 d, 30 d or 12 mo only switches
  /// what's shown. Refreshed together on each poll.
  final _history = KeepLast<Map<String, List<HistoricalPoint>>>();
  String _timeline = 'daily';
  Timer? _poll;

  bool _started = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _loadHistory();
      _poll = Timer.periodic(const Duration(minutes: 1), (_) => _loadHistory());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _history.dispose();
    super.dispose();
  }

  Future<void> _load() => Future.wait([_loadCurrent(), _loadHistory()]);

  Future<void> _loadCurrent() => widget.reloadCurrent();

  Future<void> _loadHistory() {
    final api = AppServices.of(context).api;
    final id = widget.device.id;
    return _history.load(() async {
      final ranges = _timelines.keys.toList();
      final results = await Future.wait(
        ranges.map((range) => api.historical(id, range)),
      );
      return {for (var i = 0; i < ranges.length; i++) ranges[i]: results[i]};
    });
  }

  /// The chart for the selected range, or the skeleton it fades in from.
  Widget _historyBody() {
    if (_history.isFirstLoad) {
      return const Skeleton(
        key: ValueKey('loading'),
        label: 'Loading AQI history',
        child: SkeletonBlock(height: 220, radius: 12),
      );
    }
    if (!_history.hasData) {
      return KeyedSubtree(
        key: const ValueKey('error'),
        child: ErrorView(
          message: _message(_history.error),
          onRetry: _loadHistory,
        ),
      );
    }
    final slots = buildHistorySeries(
      _history.data![_timeline] ?? const [],
      _timeline,
    );
    return Column(
      key: const ValueKey('history'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_history.error != null)
          QuietNote(updatedAt: _history.updatedAt, onRetry: _loadHistory),
        SizedBox(
          height: 220,
          // Each range fades into the next; a refresh of the same range
          // animates inside the chart instead.
          child: SoftSwitcher(
            child: slots.any((s) => s.aqi != null)
                ? _AqiChart(key: ValueKey(_timeline), slots: slots)
                : Center(
                    key: ValueKey('empty-$_timeline'),
                    child: const Text('No data for this period.'),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListenableBuilder(
            listenable: _current,
            builder: (context, _) => SoftSwitcher(
              child: Builder(
                key: ValueKey(
                  _current.isFirstLoad
                      ? 'loading'
                      : _current.hasData
                      ? 'reading'
                      : 'error',
                ),
                builder: (context) {
                  if (_current.isFirstLoad) {
                    return const _CurrentSkeleton();
                  }
                  if (!_current.hasData) {
                    return ErrorView(
                      message: _message(_current.error),
                      onRetry: _loadCurrent,
                    );
                  }
                  final current = _current.data;
                  final note = _current.error == null
                      ? null
                      : QuietNote(
                          updatedAt: _current.updatedAt,
                          onRetry: _loadCurrent,
                        );
                  if (current == null) {
                    return Column(
                      children: [
                        ?note,
                        const EmptyView(
                          illustration: MonitorIllustration(size: 110),
                          title: 'No readings yet',
                          message:
                              'The first reading appears shortly after the monitor joins WiFi.',
                        ),
                      ],
                    );
                  }
                  final m = current.metrics;
                  final hasData = current.sampleCount > 0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ?note,
                      AqiTile(
                        aqi: hasData ? m.aqi : null,
                        caption: 'Last hour average',
                      ),
                      const SizedBox(height: 12),
                      _MetricGrid(
                        tiles: [
                          MetricTile(
                            label: 'PM2.5',
                            value: hasData
                                ? formatNumber(m.pm25, digits: 1)
                                : '--',
                            unit: 'µg/m³',
                          ),
                          MetricTile(
                            label: 'PM10',
                            value: hasData
                                ? formatNumber(m.pm10, digits: 1)
                                : '--',
                            unit: 'µg/m³',
                          ),
                          MetricTile(
                            label: 'PM1',
                            value: hasData
                                ? formatNumber(m.pm1, digits: 1)
                                : '--',
                            unit: 'µg/m³',
                          ),
                          MetricTile(
                            label: 'Temperature',
                            value: hasData
                                ? formatNumber(m.temperature, digits: 1)
                                : '--',
                            unit: '°C',
                          ),
                          MetricTile(
                            label: 'Humidity',
                            value: hasData ? formatNumber(m.humidity) : '--',
                            unit: '%',
                          ),
                          MetricTile(
                            label: 'Feels like',
                            value: hasData
                                ? formatNumber(m.heatIndex, digits: 1)
                                : '--',
                            unit: '°C',
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('AQI history', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              for (final entry in _timelines.entries)
                ButtonSegment(value: entry.key, label: Text(entry.value)),
            ],
            selected: {_timeline},
            onSelectionChanged: (selection) =>
                setState(() => _timeline = selection.first),
          ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: _history,
            builder: (context, _) => SoftSwitcher(child: _historyBody()),
          ),
        ],
      ),
    );
  }
}

/// First-load placeholder: the AQI tile and metric grid drawn as soft shapes
/// from the real widgets, so the reading fades in without moving anything.
class _CurrentSkeleton extends StatelessWidget {
  const _CurrentSkeleton();

  static const _tiles = [
    ('PM2.5', 'µg/m³'),
    ('PM10', 'µg/m³'),
    ('PM1', 'µg/m³'),
    ('Temperature', '°C'),
    ('Humidity', '%'),
    ('Feels like', '°C'),
  ];

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      label: 'Loading the latest reading',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SkeletonShape(
            radius: 20,
            child: AqiTile(aqi: null, caption: 'Last hour average'),
          ),
          const SizedBox(height: 12),
          _MetricGrid(
            tiles: [
              for (final (label, unit) in _tiles)
                SkeletonShape(
                  radius: 18,
                  inset: const EdgeInsets.all(4),
                  child: MetricTile(label: label, value: '00.0', unit: unit),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _message(Object? error) => error is ApiException
    ? error.message
    : 'Could not load data. Check your connection.';

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    // Size tiles from their content rather than a fixed aspect ratio, so large
    // accessibility text sizes don't overflow them.
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double lineHeight(TextStyle? style) {
      final size = style?.fontSize ?? 14;
      return scaler.scale(size) * (style?.height ?? 1.2);
    }

    final extent =
        8 + // Card margin
        28 + // MetricTile padding
        lineHeight(theme.textTheme.labelMedium) +
        4 +
        lineHeight(theme.textTheme.titleLarge) +
        4; // rounding slack
    return GridView(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: extent,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: tiles,
    );
  }
}

class _AqiChart extends StatelessWidget {
  const _AqiChart({super.key, required this.slots});

  /// Every bucket of the timeline; empty buckets break the line.
  final List<HistorySlot> slots;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Axis labels scale with the system text size, so size the y-axis gutter
    // from the widest label instead of a fixed width.
    const axisStyle = TextStyle(fontSize: 10);
    final textScaler = MediaQuery.textScalerOf(context);
    final leftAxisWidth =
        (TextPainter(
          text: const TextSpan(text: '000', style: axisStyle),
          textDirection: Directionality.of(context),
          textScaler: textScaler,
        )..layout()).width +
        8;
    final spots = [
      for (var i = 0; i < slots.length; i++)
        if (slots[i].aqi case final aqi?)
          FlSpot(i.toDouble(), aqi.toDouble())
        else
          FlSpot.nullSpot,
    ];
    // A reading with no neighbouring readings can't be drawn as a line.
    bool hasData(int i) => i >= 0 && i < slots.length && slots[i].aqi != null;
    final isolated = {
      for (var i = 0; i < slots.length; i++)
        if (hasData(i) && !hasData(i - 1) && !hasData(i + 1)) i,
    };
    final maxAqi = spots
        .where((s) => s.isNotNull())
        .map((s) => s.y)
        .fold<double>(50, (a, b) => a > b ? a : b);
    final step = (slots.length / 4).ceil().clamp(1, slots.length);
    final latest = slots.lastWhere((s) => s.aqi != null);
    final missing = slots.where((s) => s.aqi == null).length;
    return Semantics(
      label:
          'AQI history chart, ${slots.length} periods'
          '${missing > 0 ? ', $missing without data' : ''}, latest ${latest.aqi} '
          '(${aqiInfo(latest.aqi).label}) at ${latest.tooltipLabel}',
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (slots.length - 1).toDouble(),
          minY: 0,
          maxY: (maxAqi * 1.2).ceilToDouble(),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Theme.of(context).colorScheme.outlineVariant,
              strokeWidth: 1,
              dashArray: const [1, 6],
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              fitInsideHorizontally: true,
              getTooltipItems: (touched) => [
                for (final spot in touched)
                  LineTooltipItem(
                    '${slots[spot.x.round()].tooltipLabel}\n'
                    'AQI ${spot.y.round()}',
                    TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                  ),
              ],
              getTooltipColor: (_) => scheme.inverseSurface,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: leftAxisWidth,
                getTitlesWidget: (value, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(
                    meta.formattedValue,
                    style: axisStyle,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: step.toDouble(),
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= slots.length) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    // Keep the first and last labels inside the chart.
                    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                    child: Text(
                      slots[index].axisLabel,
                      style: axisStyle,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: scheme.primary,
              barWidth: 3,
              dotData: FlDotData(
                checkToShowDot: (spot, _) =>
                    slots.length < 15 || isolated.contains(spot.x.round()),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: scheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
        // Fresh data for the same range eases into place.
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
      ),
    );
  }
}

class _LiveTab extends StatefulWidget {
  const _LiveTab({required this.device});

  final Device device;

  @override
  State<_LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<_LiveTab> with AutomaticKeepAliveClientMixin {
  StreamSubscription<LiveReading>? _readings;
  AiqSession? _session;
  LiveReading? _latest;
  DateTime? _receivedAt;
  String? _error;
  bool _starting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _stop() {
    _readings?.cancel();
    _readings = null;
    final session = _session;
    _session = null;
    if (session != null) unawaited(session.setLive(false).catchError((_) {}));
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    final ble = AppServices.of(context).ble;
    try {
      if (!await ConnectScreen.ensureConnected(
        context,
        expectedDeviceId: widget.device.deviceId,
      )) {
        return;
      }
      final session = ble.session!;
      _session = session;
      _readings = session.readings.listen((reading) {
        if (mounted) {
          setState(() {
            _latest = reading;
            _receivedAt = DateTime.now();
          });
        }
      });
      await session.setLive(true);
      final first = await session.read();
      if (first != null && mounted) {
        setState(() {
          _latest = first;
          _receivedAt = DateTime.now();
        });
      }
    } on BleProtocolException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Live readings failed: $e';
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ble = AppServices.of(context).ble;
    return ListenableBuilder(
      listenable: ble,
      builder: (context, _) {
        final live =
            _session != null && ble.isConnectedTo(widget.device.deviceId);
        if (!live) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              EmptyView(
                icon: Icons.bluetooth,
                title: 'Live readings',
                message:
                    'Connect over Bluetooth to see a new reading from the monitor every 20 seconds.',
                action: FilledButton.icon(
                  onPressed: _starting ? null : _start,
                  icon: const Icon(Icons.bluetooth_connected),
                  label: Text(_starting ? 'Connecting…' : 'Connect'),
                ),
              ),
              InlineError(_error),
            ],
          );
        }
        final reading = _latest;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AqiTile(
              aqi: reading?.aqi,
              caption: _receivedAt == null
                  ? 'Waiting for a sample…'
                  : 'Live · ${DateFormat.Hms().format(_receivedAt!)}',
            ),
            const SizedBox(height: 8),
            _MetricGrid(
              tiles: [
                MetricTile(
                  label: 'PM2.5',
                  value: formatNumber(reading?.pm25),
                  unit: 'µg/m³',
                ),
                MetricTile(
                  label: 'PM10',
                  value: formatNumber(reading?.pm10),
                  unit: 'µg/m³',
                ),
                MetricTile(
                  label: 'PM1',
                  value: formatNumber(reading?.pm1),
                  unit: 'µg/m³',
                ),
                MetricTile(
                  label: 'Temperature',
                  value: formatNumber(reading?.temperature, digits: 1),
                  unit: '°C',
                ),
                MetricTile(
                  label: 'Humidity',
                  value: formatNumber(reading?.humidity),
                  unit: '%',
                ),
                MetricTile(
                  label: 'Feels like',
                  value: formatNumber(reading?.heatIndex, digits: 1),
                  unit: '°C',
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Instant readings; the Online tab shows the averages uploaded every 10 minutes.',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                _stop();
                await ble.disconnect();
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.bluetooth_disabled),
              label: const Text('Disconnect'),
            ),
          ],
        );
      },
    );
  }
}
