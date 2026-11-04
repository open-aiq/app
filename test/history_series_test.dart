import 'package:app/api/models.dart';
import 'package:app/features/device_detail/history_series.dart';
import 'package:flutter_test/flutter_test.dart';

HistoricalPoint _point(String timestamp, int aqi) => HistoricalPoint.fromJson({
  'timestamp': timestamp,
  'label': 'server label',
  'metrics': {'aqi': aqi},
});

// Sydney in November is UTC+11.
DateTime _sydney(DateTime utc) => utc.add(const Duration(hours: 11));

void main() {
  final now = DateTime.utc(2026, 11, 4, 9, 30);

  test('daily fills every hour and leaves gaps for missing data', () {
    final slots = buildHistorySeries(
      [_point('2026-11-04T08:00:00Z', 42), _point('2026-11-04T05:00:00Z', 30)],
      'daily',
      now: now,
      toLocal: _sydney,
    );
    // 09:00Z yesterday up to and including the current hour, 09:00Z today.
    expect(slots, hasLength(25));
    expect(slots.first.start, DateTime.utc(2026, 11, 3, 9));
    expect(slots.last.start, DateTime.utc(2026, 11, 4, 9));
    expect(slots.where((s) => s.aqi != null), hasLength(2));
    expect(slots[20].aqi, 30); // 05:00Z
    expect(slots[23].aqi, 42); // 08:00Z
    expect(slots[24].aqi, isNull);
    expect(slots[24].point, isNull);
  });

  test('hourly labels use the local time zone, not the server label', () {
    final slots = buildHistorySeries(
      [_point('2026-11-04T08:00:00Z', 42)],
      'daily',
      now: now,
      toLocal: _sydney,
    );
    final slot = slots.firstWhere((s) => s.aqi != null);
    expect(slot.axisLabel, '19:00');
    expect(slot.tooltipLabel, 'Wed 4 Nov, 19:00');
  });

  test('matches points by timestamp even when they are local DateTimes', () {
    // HistoricalPoint.fromJson converts to local time; matching must not care.
    final slots = buildHistorySeries(
      [_point('2026-11-04T19:00:00+11:00', 7)],
      'daily',
      now: now,
    );
    expect(slots[23].aqi, 7);
  });

  test('a range with no data is all gaps', () {
    final slots = buildHistorySeries(const [], 'weekly', now: now);
    expect(slots, hasLength(8));
    expect(slots.every((s) => s.point == null), isTrue);
  });

  test('day and month buckets are named in UTC so the date does not shift', () {
    final monthly = buildHistorySeries(
      [_point('2026-11-04T00:00:00Z', 12)],
      'monthly',
      now: now,
      toLocal: (d) => d.subtract(const Duration(hours: 8)),
    );
    expect(monthly, hasLength(31));
    expect(monthly.last.axisLabel, '4 Nov');
    expect(monthly.last.tooltipLabel, 'Wed 4 Nov 2026');

    final weekly = buildHistorySeries(const [], 'weekly', now: now);
    expect(weekly.last.axisLabel, 'Wed');

    final yearly = buildHistorySeries(
      [_point('2026-01-01T00:00:00Z', 5)],
      'yearly',
      now: now,
    );
    expect(yearly, hasLength(13));
    expect(yearly.first.start, DateTime.utc(2025, 11));
    expect(yearly[2].axisLabel, 'Jan');
    expect(yearly[2].aqi, 5);
    expect(yearly.last.tooltipLabel, 'November 2026');
  });
}
