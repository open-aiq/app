import 'package:flutter/material.dart';

import '../aqi.dart';
import '../theme.dart';
import 'sections.dart';
import 'states.dart';

/// The big AQI block at the top of a monitor: the number, "AQI" and the
/// band name, centred on the band colour. Colour never carries meaning alone.
class AqiTile extends StatelessWidget {
  const AqiTile({super.key, required this.aqi, this.caption});

  final num? aqi;

  /// A quiet line at the bottom, e.g. when a live reading arrived.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final info = aqiInfo(aqi);
    final ink = info.foreground;
    return Semantics(
      label:
          'Air quality index ${aqi?.round() ?? 'unknown'}, ${info.label}'
          '${caption == null ? '' : ', $caption'}',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 208),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        decoration: BoxDecoration(
          color: info.background,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              aqi?.round().toString() ?? '--',
              style: TextStyle(
                fontSize: 80,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -2,
                color: ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'AQI',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: ink.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              info.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 6),
              Text(
                caption!,
                style: TextStyle(
                  fontSize: 12,
                  color: ink.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The compact AQI block on the home screen: the number and a short band
/// name, nothing else.
class AqiBlock extends StatelessWidget {
  const AqiBlock({super.key, required this.aqi, this.height = 136});

  final num? aqi;
  final double height;

  @override
  Widget build(BuildContext context) {
    final info = aqiInfo(aqi);
    return Semantics(
      label: 'Air quality index ${aqi?.round() ?? 'unknown'}, ${info.label}',
      excludeSemantics: true,
      child: Container(
        constraints: BoxConstraints(minHeight: height),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: info.background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  aqi?.round().toString() ?? '--',
                  style: TextStyle(
                    fontSize: 40,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: info.foreground,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'AQI',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: info.foreground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              info.short,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: info.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One reading for [MetricGroups].
typedef Metric = ({IconData icon, String label, String value, String unit});

/// The readings grouped into themed cards, one card per row: particulates,
/// how it feels, then temperature and humidity. Pass null for values that
/// aren't known yet; they show as "--".
List<List<Metric>> metricGroups({
  num? pm25,
  num? pm10,
  num? pm1,
  num? temperature,
  num? humidity,
  num? heatIndex,
}) => [
  [
    (
      icon: Icons.grain,
      label: 'PM2.5',
      value: formatNumber(pm25, digits: 1),
      unit: 'µg/m³',
    ),
    (
      icon: Icons.bubble_chart_outlined,
      label: 'PM1',
      value: formatNumber(pm1, digits: 1),
      unit: 'µg/m³',
    ),
    (
      icon: Icons.blur_on,
      label: 'PM10',
      value: formatNumber(pm10, digits: 1),
      unit: 'µg/m³',
    ),
  ],
  [
    (
      icon: Icons.wb_sunny_outlined,
      label: 'Feels like',
      value: formatNumber(heatIndex, digits: 1),
      unit: '°C',
    ),
  ],
  [
    (
      icon: Icons.thermostat_outlined,
      label: 'Temperature',
      value: formatNumber(temperature, digits: 1),
      unit: '°C',
    ),
    (
      icon: Icons.water_drop_outlined,
      label: 'Humidity',
      value: formatNumber(humidity),
      unit: '%',
    ),
  ],
];

/// Readings as stacked cards, one group per card. Groups with several
/// readings sit side by side, each centred; a single reading runs across
/// the card. With [loading], each card is drawn as a soft skeleton shape of
/// exactly its real size.
class MetricGroups extends StatelessWidget {
  const MetricGroups({super.key, required this.groups, this.loading = false});

  final List<List<Metric>> groups;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          loading
              ? SkeletonShape(radius: 20, child: _GroupCard(groups[i]))
              : _GroupCard(groups[i]),
        ],
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard(this.metrics);

  final List<Metric> metrics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: raisedSurface(scheme),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: metrics.length == 1
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _MetricRow(metrics.single),
            )
          : IntrinsicHeight(
              child: Row(
                children: [
                  for (var i = 0; i < metrics.length; i++) ...[
                    if (i > 0)
                      VerticalDivider(
                        width: 1,
                        indent: 6,
                        endIndent: 6,
                        color: scheme.outlineVariant,
                      ),
                    Expanded(child: _MetricColumn(metrics[i])),
                  ],
                ],
              ),
            ),
    );
  }
}

/// A reading stacked vertically: icon, value with unit, then its name.
class _MetricColumn extends StatelessWidget {
  const _MetricColumn(this.metric);

  final Metric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: '${metric.label} ${metric.value} ${metric.unit}',
      excludeSemantics: true,
      child: Column(
        children: [
          IconBubble(icon: Icon(metric.icon), size: 40),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              text: metric.value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              children: [
                TextSpan(
                  text: ' ${metric.unit}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            metric.label,
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// A reading laid out across the card: icon, then value and name.
class _MetricRow extends StatelessWidget {
  const _MetricRow(this.metric);

  final Metric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: '${metric.label} ${metric.value} ${metric.unit}',
      excludeSemantics: true,
      child: Row(
        children: [
          IconBubble(icon: Icon(metric.icon), size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              metric.label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text.rich(
            TextSpan(
              text: metric.value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              children: [
                TextSpan(
                  text: ' ${metric.unit}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String formatNumber(num? value, {int digits = 0}) =>
    value == null ? '--' : value.toStringAsFixed(digits);
