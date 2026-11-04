import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../aqi.dart';
import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../ble/protocol.dart';
import '../../services.dart';
import '../../widgets/ota_badge.dart';
import '../../widgets/states.dart';
import '../../widgets/tiles.dart';
import '../devices/device_list_screen.dart' show relativeTime;
import '../firmware/firmware_screen.dart';
import '../logs/logs_screen.dart';
import '../provisioning/connect_screen.dart';
import '../settings/device_settings_screen.dart';

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

  Future<CurrentReading?>? _current;
  Future<List<HistoricalPoint>>? _history;
  String _timeline = 'daily';
  Timer? _refresh;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_current == null) {
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
    super.dispose();
  }

  Future<void> _load() async {
    _loadCurrent();
    _loadHistory();
    await Future.wait([
      _current!.catchError((_) => null),
      _history!.catchError((_) => <HistoricalPoint>[]),
    ]);
  }

  void _loadCurrent() {
    final api = AppServices.of(context).api;
    setState(() {
      _current = api
          .current(widget.device.id)
          .then<CurrentReading?>((value) => value)
          .catchError(
            (Object e) => e is ApiException && e.isNoReadings ? null : throw e,
          );
    });
  }

  void _loadHistory() {
    final api = AppServices.of(context).api;
    setState(() => _history = api.historical(widget.device.id, _timeline));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<CurrentReading?>(
            future: _current,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done &&
                  !snapshot.hasData) {
                return const SizedBox(height: 160, child: LoadingView());
              }
              if (snapshot.hasError) {
                return ErrorView(
                  message: _message(snapshot.error),
                  onRetry: _loadCurrent,
                );
              }
              final current = snapshot.data;
              if (current == null) {
                return const EmptyView(
                  icon: Icons.hourglass_empty,
                  title: 'No readings yet',
                  message:
                      'The first reading appears shortly after the monitor joins WiFi.',
                );
              }
              final m = current.metrics;
              final hasData = current.sampleCount > 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
              _timeline = selection.first;
              _loadHistory();
            },
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<HistoricalPoint>>(
            future: _history,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(height: 200, child: LoadingView());
              }
              if (snapshot.hasError) {
                return ErrorView(
                  message: _message(snapshot.error),
                  onRetry: _loadHistory,
                );
              }
              final points = snapshot.data ?? const [];
              if (points.isEmpty) return const Text('No data for this period.');
              return SizedBox(height: 220, child: _AqiChart(points: points));
            },
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
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      children: tiles,
    );
  }
}

class _AqiChart extends StatelessWidget {
  const _AqiChart({required this.points});

  final List<HistoricalPoint> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].metrics.aqi.toDouble()),
    ];
    final maxAqi = spots
        .map((s) => s.y)
        .fold<double>(50, (a, b) => a > b ? a : b);
    final step = (points.length / 4).ceil().clamp(1, points.length);
    return Semantics(
      label:
          'AQI history chart, ${points.length} points, latest ${points.last.metrics.aqi} '
          '(${aqiInfo(points.last.metrics.aqi).label})',
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: (maxAqi * 1.2).ceilToDouble(),
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 36),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: step.toDouble(),
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      points[index].label,
                      style: const TextStyle(fontSize: 10),
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
              dotData: FlDotData(show: points.length < 15),
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
