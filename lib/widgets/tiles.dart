import 'package:flutter/material.dart';

import '../aqi.dart';
import '../theme.dart';
import 'sections.dart';

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

/// One reading on a soft tile: an icon bubble, the value with its unit,
/// and the name underneath.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.unit = '',
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: '$label $value $unit',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: raisedSurface(scheme),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            IconBubble(icon: Icon(icon), size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: value,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        if (unit.isNotEmpty)
                          TextSpan(
                            text: ' $unit',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Six readings as two columns of [MetricTile]s.
class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The six readings shown for a monitor, in a fixed order. Pass null for a
/// value that isn't known yet; it shows as "--".
List<MetricTile> metricTiles({
  num? pm25,
  num? pm10,
  num? pm1,
  num? temperature,
  num? humidity,
  num? heatIndex,
}) => [
  MetricTile(
    icon: Icons.grain,
    label: 'PM2.5',
    value: formatNumber(pm25, digits: 1),
    unit: 'µg/m³',
  ),
  MetricTile(
    icon: Icons.blur_on,
    label: 'PM10',
    value: formatNumber(pm10, digits: 1),
    unit: 'µg/m³',
  ),
  MetricTile(
    icon: Icons.bubble_chart_outlined,
    label: 'PM1',
    value: formatNumber(pm1, digits: 1),
    unit: 'µg/m³',
  ),
  MetricTile(
    icon: Icons.thermostat_outlined,
    label: 'Temperature',
    value: formatNumber(temperature, digits: 1),
    unit: '°C',
  ),
  MetricTile(
    icon: Icons.water_drop_outlined,
    label: 'Humidity',
    value: formatNumber(humidity),
    unit: '%',
  ),
  MetricTile(
    icon: Icons.wb_sunny_outlined,
    label: 'Feels like',
    value: formatNumber(heatIndex, digits: 1),
    unit: '°C',
  ),
];

String formatNumber(num? value, {int digits = 0}) =>
    value == null ? '--' : value.toStringAsFixed(digits);
