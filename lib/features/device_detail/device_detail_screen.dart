import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../aqi.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../ble/protocol.dart';
import '../../services.dart';
import '../../widgets/keep_last.dart';
import '../../widgets/ota_badge.dart';
import '../../widgets/states.dart';
import '../../widgets/tiles.dart';
import '../devices/device_list_screen.dart' show relativeTime;
import '../firmware/firmware_screen.dart';
import '../logs/logs_screen.dart';
import '../provisioning/connect_screen.dart';
import '../settings/device_settings_screen.dart';
import 'history_series.dart';

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({super.key, required this.device});

  final Device device;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late Device _device = widget.device;

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(builder: (_) => DeviceSettingsScreen(device: _device)),
    );
    if (!mounted) return;
    if (result == DeviceSettingsScreen.deleted) {
      Navigator.of(context).pop();
    } else if (result is Device) {
      setState(() => _device = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_device.name, overflow: TextOverflow.ellipsis),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: OtaBadge(
                  summary: _device.ota,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FirmwareScreen(device: _device),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Device logs',
              icon: const Icon(Icons.receipt_long),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LogsScreen(device: _device),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings),
              onPressed: _openSettings,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.cloud_outlined), text: 'Online'),
              Tab(icon: Icon(Icons.bluetooth), text: 'Live'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OnlineTab(device: _device),
            _LiveTab(device: _device),
          ],
        ),
      ),
    );
  }
}

class _OnlineTab extends StatefulWidget {
  const _OnlineTab({required this.device});

  final Device device;

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

  final _current = KeepLast<CurrentReading?>();
  final _history = KeepLast<List<HistoricalPoint>>();
  String _timeline = 'daily';

  /// The range the chart on screen belongs to; it lags [_timeline] while a
  /// new range loads, so the old chart stays put until the new one arrives.
  String _shownTimeline = 'daily';
  Timer? _refresh;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_refresh == null) {
      _load();
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
    _history.dispose();
    super.dispose();
  }

  Future<void> _load() => Future.wait([_loadCurrent(), _loadHistory()]);

  Future<void> _loadCurrent() {
    final api = AppServices.of(context).api;
    return _current.load(() async {
      try {
        return await api.current(widget.device.id);
      } on ApiException catch (e) {
        if (e.isNoReadings) return null;
        rethrow;
      }
    });
  }

  Future<void> _loadHistory() async {
    final api = AppServices.of(context).api;
    final timeline = _timeline;
    await _history.load(() => api.historical(widget.device.id, timeline));
    if (mounted && _history.error == null && timeline == _timeline) {
      setState(() => _shownTimeline = timeline);
    }
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
            builder: (context, _) {
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
                      icon: Icons.hourglass_empty,
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
                  const SizedBox(height: 8),
                  Text(
                    '${current.online ? 'Online' : 'Offline'}'
                    '${current.lastSeen == null ? '' : ' · last seen ${relativeTime(current.lastSeen!)}'}',
                  ),
                  const SizedBox(height: 8),
                  _MetricGrid(
                    tiles: [
                      MetricTile(
                        label: 'PM2.5',
                        value: hasData ? formatNumber(m.pm25, digits: 1) : '--',
                        unit: 'µg/m³',
                      ),
                      MetricTile(
                        label: 'PM10',
                        value: hasData ? formatNumber(m.pm10, digits: 1) : '--',
                        unit: 'µg/m³',
                      ),
                      MetricTile(
                        label: 'PM1',
                        value: hasData ? formatNumber(m.pm1, digits: 1) : '--',
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
          const SizedBox(height: 24),
          Text('AQI history', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              for (final entry in _timelines.entries)
                ButtonSegment(value: entry.key, label: Text(entry.value)),
            ],
            selected: {_timeline},
            onSelectionChanged: (selection) {
              setState(() => _timeline = selection.first);
              _loadHistory();
            },
          ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: _history,
            builder: (context, _) {
              if (_history.isFirstLoad) {
                return const Skeleton(
                  label: 'Loading AQI history',
                  child: SkeletonBlock(height: 220, radius: 12),
                );
              }
              if (!_history.hasData) {
                return ErrorView(
                  message: _message(_history.error),
                  onRetry: _loadHistory,
                );
              }
              final slots = buildHistorySeries(
                _history.data ?? const [],
                _shownTimeline,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_history.error != null)
                    QuietNote(
                      message: _timeline == _shownTimeline
                          ? null
                          : "Couldn't load that range. "
                                'Still showing ${_timelines[_shownTimeline]}.',
                      updatedAt: _history.updatedAt,
                      onRetry: _loadHistory,
                    ),
                  if (!slots.any((s) => s.aqi != null))
                    const Text('No data for this period.')
                  else
                    SizedBox(height: 220, child: _AqiChart(slots: slots)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// First-load placeholder shaped like the AQI tile and metric grid.
class _CurrentSkeleton extends StatelessWidget {
  const _CurrentSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Skeleton(
      label: 'Loading the latest reading',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBlock(height: 72, radius: 12),
          SizedBox(height: 12),
          SkeletonBlock(width: 200, height: 14),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: SkeletonBlock(height: 64, radius: 12)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBlock(height: 64, radius: 12)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBlock(height: 64, radius: 12)),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: SkeletonBlock(height: 64, radius: 12)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBlock(height: 64, radius: 12)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBlock(height: 64, radius: 12)),
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
        24 + // MetricTile padding
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
  const _AqiChart({required this.slots});

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
          gridData: const FlGridData(drawVerticalLine: false),
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
