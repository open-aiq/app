import 'package:flutter/material.dart';

import '../api/models.dart';
import '../format.dart';
import 'ota_badge.dart';
import 'soft_card.dart';
import 'states.dart';
import 'tiles.dart';

/// The monitor card on the home screen: icon, name, status and update badge,
/// then the AQI block with temperature and PM2.5. It only draws what it's
/// given, so the home screen, the gallery and tests can all use it. The
/// visual spec lives on the docs site's visual playground page.
class MonitorCard extends StatelessWidget {
  const MonitorCard({
    super.key,
    required this.device,
    this.reading,
    this.loading = false,
    this.unavailable = false,
    this.onTap,
    this.onBadgeTap,
  });

  final Device device;

  /// The latest reading, or null when there's none yet.
  final CurrentReading? reading;

  /// The first load is still running.
  final bool loading;

  /// The reading couldn't be loaded at all.
  final bool unavailable;
  final VoidCallback? onTap;
  final VoidCallback? onBadgeTap;

  @override
  Widget build(BuildContext context) {
    final reading = this.reading;
    return SoftCard(
      onTap: onTap,
      child: Column(
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
                      child: SkeletonShape(child: _StatusLine.placeholder()),
                    )
                  : _StatusLine(
                      key: const ValueKey('status'),
                      online: reading?.online ?? false,
                      seen: reading?.lastSeen,
                      unavailable: unavailable,
                    ),
            ),
            badge: OtaBadge(
              summary: device.ota,
              onTap: onBadgeTap,
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
                : _ReadingRow(key: const ValueKey('reading'), reading: reading),
          ),
        ],
      ),
    );
  }
}

/// A first-load placeholder with the same shape as [MonitorCard].
class MonitorCardSkeleton extends StatelessWidget {
  const MonitorCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SoftCard(
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
