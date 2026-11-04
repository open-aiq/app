// Turns the backend's bucketed history into a continuous chart series.
//
// The API returns only buckets that contain readings, each with an RFC 3339
// `timestamp` (the UTC start of the bucket, from Postgres date_trunc) and a
// server-formatted `label` in the server's time zone. buildHistorySeries
// ignores that label: it lays out every expected bucket for the timeline, so
// hours or days without readings become explicit gaps instead of being
// skipped, and it formats times in the viewer's own time zone.
//
// Keep in step with the web dashboard (frontend/src/lib/history.js).

import 'package:intl/intl.dart';

import '../../api/models.dart';

enum _Unit { hour, day, month }

/// One expected bucket of a history timeline.
class HistorySlot {
  const HistorySlot({
    required this.start,
    required this.axisLabel,
    required this.tooltipLabel,
    this.point,
  });

  /// UTC start of the bucket.
  final DateTime start;

  /// Short label for the chart axis.
  final String axisLabel;

  /// Full date (and local time, for hourly buckets) for the tooltip.
  final String tooltipLabel;

  /// The reading for this bucket, or null when the device sent no data.
  final HistoricalPoint? point;

  int? get aqi => point?.metrics.aqi;
}

// Mirrors the ranges in backend/internal/airquality/service.go.
_Unit? _unitFor(String timeline) => switch (timeline) {
  'daily' => _Unit.hour,
  'weekly' || 'monthly' => _Unit.day,
  'yearly' => _Unit.month,
  _ => null,
};

DateTime _rangeStart(String timeline, DateTime now) => switch (timeline) {
  'daily' => now.subtract(const Duration(hours: 24)),
  'weekly' => _addUtc(now, days: -7),
  'monthly' => _addUtc(now, days: -30),
  _ => _addUtc(now, months: -12),
};

DateTime _addUtc(DateTime d, {int days = 0, int months = 0}) => DateTime.utc(
  d.year,
  d.month + months,
  d.day + days,
  d.hour,
  d.minute,
  d.second,
  d.millisecond,
);

DateTime _floor(DateTime d, _Unit unit) => switch (unit) {
  _Unit.hour => DateTime.utc(d.year, d.month, d.day, d.hour),
  _Unit.day => DateTime.utc(d.year, d.month, d.day),
  _Unit.month => DateTime.utc(d.year, d.month),
};

DateTime _step(DateTime d, _Unit unit) => switch (unit) {
  _Unit.hour => d.add(const Duration(hours: 1)),
  _Unit.day => DateTime.utc(d.year, d.month, d.day + 1),
  _Unit.month => DateTime.utc(d.year, d.month + 1),
};

DateTime _defaultToLocal(DateTime d) => d.toLocal();

/// Returns one slot per expected bucket of [timeline], oldest first. Buckets
/// without data have a null [HistorySlot.point]. Unknown timelines keep only
/// the returned points, labelled in local time.
///
/// Hourly buckets are labelled in the viewer's local time. Day and month
/// buckets are UTC calendar days/months, so they are named in UTC; converting
/// them would shift the date for viewers west of UTC.
///
/// [now] and [toLocal] are overridable for tests.
List<HistorySlot> buildHistorySeries(
  List<HistoricalPoint> points,
  String timeline, {
  DateTime? now,
  DateTime Function(DateTime utc) toLocal = _defaultToLocal,
}) {
  final nowUtc = (now ?? DateTime.now()).toUtc();
  final sorted = [...points]
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  String Function(DateTime) axis;
  String Function(DateTime) full;
  final unit = _unitFor(timeline);
  switch (unit) {
    case _Unit.hour || null:
      axis = (d) => DateFormat.Hm().format(toLocal(d));
      full = (d) => DateFormat('EEE d MMM, HH:mm').format(toLocal(d));
    case _Unit.day:
      axis = timeline == 'weekly'
          ? (d) => DateFormat.E().format(d)
          : (d) => DateFormat('d MMM').format(d);
      full = (d) => DateFormat('EEE d MMM y').format(d);
    case _Unit.month:
      axis = (d) => DateFormat.MMM().format(d);
      full = (d) => DateFormat.yMMMM().format(d);
  }

  HistorySlot slot(DateTime start, HistoricalPoint? point) => HistorySlot(
    start: start,
    axisLabel: axis(start),
    tooltipLabel: full(start),
    point: point,
  );

  if (unit == null) {
    return [for (final p in sorted) slot(p.timestamp.toUtc(), p)];
  }

  final byBucket = {
    for (final p in sorted) _floor(p.timestamp.toUtc(), unit): p,
  };
  final last = _floor(nowUtc, unit);
  return [
    for (
      var d = _floor(_rangeStart(timeline, nowUtc), unit);
      !d.isAfter(last);
      d = _step(d, unit)
    )
      slot(d, byBucket[d]),
  ];
}
