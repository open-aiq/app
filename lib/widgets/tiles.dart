import 'package:flutter/material.dart';

import '../aqi.dart';

/// AQI tile: band color plus the band label (never color alone).
class AqiTile extends StatelessWidget {
  const AqiTile({super.key, required this.aqi, this.caption});

  final num? aqi;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final info = aqiInfo(aqi);
    return Semantics(
      label: 'Air quality index ${aqi ?? 'unknown'}, ${info.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: info.background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Text(
              aqi?.round().toString() ?? '--',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: info.foreground,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'US AQI',
                    style: TextStyle(color: info.foreground, fontSize: 12),
                  ),
                  Text(
                    info.label,
                    style: TextStyle(
                      color: info.foreground,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  if (caption != null)
                    Text(
                      caption!,
                      style: TextStyle(color: info.foreground, fontSize: 12),
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

/// A labelled metric value, e.g. "PM2.5  12 µg/m³".
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.filled(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                text: value,
                style: theme.textTheme.titleLarge,
                children: [
                  if (unit.isNotEmpty)
                    TextSpan(text: ' $unit', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatNumber(num? value, {int digits = 0}) =>
    value == null ? '--' : value.toStringAsFixed(digits);
