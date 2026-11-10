import 'dart:math' as math;

import '../api/models.dart';

// Mock data for `make gallery` and the hosted prototype. It mirrors the web's
// `frontend/src/review/fixtures.js`: the same monitors, one per AQI band plus
// one that hasn't reported yet. Shapes match the backend JSON that
// `lib/api/models.dart` parses, and timestamps are relative to now so charts
// and "last seen" labels look current.

class _Seed {
  const _Seed(
    this.id,
    this.name, {
    required this.aqi,
    required this.outdoor,
    required this.public,
    required this.location,
    this.lat,
    this.lon,
    this.offline = false,
  });

  final String id;
  final String name;
  final int? aqi;
  final bool outdoor;
  final bool public;
  final bool location;
  final double? lat;
  final double? lon;
  final bool offline;
}

const _seeds = [
  _Seed(
    'dev-garden',
    'Back garden',
    aqi: 32,
    outdoor: true,
    public: true,
    location: true,
    lat: -33.8688,
    lon: 151.2093,
  ),
  _Seed(
    'dev-kitchen',
    'Kitchen',
    aqi: 78,
    outdoor: false,
    public: false,
    location: false,
  ),
  _Seed(
    'dev-balcony',
    'Balcony',
    aqi: 128,
    outdoor: true,
    public: true,
    location: true,
    lat: -33.8915,
    lon: 151.2767,
  ),
  _Seed(
    'dev-school',
    'School gate',
    aqi: 172,
    outdoor: true,
    public: true,
    location: true,
    lat: -33.8523,
    lon: 151.1802,
  ),
  _Seed(
    'dev-workshop',
    'Workshop',
    aqi: 240,
    outdoor: false,
    public: true,
    location: false,
  ),
  _Seed(
    'dev-bushfire',
    'Ridge lookout',
    aqi: 340,
    outdoor: true,
    public: true,
    location: true,
    lat: -33.7969,
    lon: 151.2878,
    offline: true,
  ),
  _Seed(
    'dev-new',
    'New sensor',
    aqi: null,
    outdoor: false,
    public: false,
    location: false,
  ),
];

_Seed? _seed(String id) {
  for (final seed in _seeds) {
    if (seed.id == id) return seed;
  }
  return null;
}

String _iso(DateTime time) => time.toUtc().toIso8601String();

/// The firmware release waiting for "New sensor", so the update badge and the
/// approve flow have something to show.
const _release = {
  'id': 'rel-0-6-3',
  'version': '0.6.3',
  'size': 1376256,
  'notes': 'Steadier WiFi reconnects and a calmer status light at night.',
};

/// Roughly inverts the US EPA PM2.5 breakpoints, close enough for mock data.
double pm25ForAqi(int aqi) {
  if (aqi <= 50) return aqi / 50 * 9;
  if (aqi <= 100) return 9 + (aqi - 50) / 50 * 26.4;
  if (aqi <= 150) return 35.5 + (aqi - 100) / 50 * 20;
  if (aqi <= 200) return 55.5 + (aqi - 150) / 50 * 69.9;
  if (aqi <= 300) return 125.5 + (aqi - 200) / 100 * 99.9;
  return 225.5 + (aqi - 300) / 200 * 99.9;
}

/// `GET /devices`: every mock monitor, as the backend returns it.
List<Map<String, dynamic>> devicesJson() {
  final now = DateTime.now();
  final created = now.subtract(const Duration(days: 90));
  return [
    for (final (index, seed) in _seeds.indexed)
      {
        'id': seed.id,
        'device_id':
            'dev_${seed.id.replaceFirst('dev-', '').padRight(12, '0')}'
            'a1b2c3d4e5f6',
        'name': seed.name,
        'is_public': seed.public,
        'is_outdoor': seed.outdoor,
        'is_location_public': seed.location,
        'firmware_version': index % 3 == 0 ? '0.6.2' : '0.6.1',
        'ota': seed.id == 'dev-new'
            ? {'status': 'update_available', 'version': _release['version']}
            : {'status': 'up_to_date'},
        'created_at': _iso(created.add(Duration(days: index))),
        'updated_at': _iso(now.subtract(Duration(hours: index))),
      },
  ];
}

/// `GET /devices/{id}/current`, or null when the monitor has no readings.
Map<String, dynamic>? currentJson(String id) {
  final seed = _seed(id);
  final aqi = seed?.aqi;
  if (seed == null || aqi == null) return null;
  final pm25 = pm25ForAqi(aqi);
  final temperature = seed.outdoor ? 18.4 + aqi % 7 : 22.1;
  final humidity = seed.outdoor ? 64 : 46;
  final seen = DateTime.now().subtract(
    seed.offline
        ? const Duration(hours: 3, minutes: 12)
        : const Duration(minutes: 2),
  );
  return {
    'aqi': aqi,
    'pm1_0': pm25 * 0.68,
    'pm2_5': pm25,
    'pm10_0': pm25 * 1.42,
    'temperature': temperature,
    'humidity': humidity,
    'heat_index': temperature + 0.6,
    'status': seed.offline ? 'offline' : 'online',
    'last_seen': _iso(seen),
    'sample_count': seed.offline ? 4 : 58,
    'location': seed.location
        ? {'lat': seed.lat, 'lon': seed.lon, 'provider': 'phone'}
        : null,
  };
}

typedef _Timeline = ({Duration step, int count, String Function(String) label});

final Map<String, _Timeline> _timelines = {
  'daily': (
    step: const Duration(hours: 1),
    count: 24,
    label: (iso) => iso.substring(11, 16),
  ),
  'weekly': (
    step: const Duration(days: 1),
    count: 7,
    label: (iso) => iso.substring(5, 10),
  ),
  'monthly': (
    step: const Duration(days: 1),
    count: 30,
    label: (iso) => iso.substring(5, 10),
  ),
  'yearly': (
    step: const Duration(days: 30),
    count: 12,
    label: (iso) => iso.substring(0, 7),
  ),
};

/// `GET /devices/{id}/historical`: a gentle wave around the monitor's AQI,
/// with a short gap so the chart's missing-data drawing shows.
List<Map<String, dynamic>> historyJson(String id, String timeline) {
  final seed = _seed(id);
  final base = seed?.aqi;
  if (seed == null || base == null) return const [];
  final config = _timelines[timeline] ?? _timelines['daily']!;
  final step = config.step.inMilliseconds;
  final end = DateTime.now().millisecondsSinceEpoch ~/ step * step;
  final gap = config.count ~/ 3;
  return [
    for (var i = config.count - 1; i >= 0; i--)
      if (i != gap && i != gap + 1) _point(base, i, config, end - i * step),
  ];
}

Map<String, dynamic> _point(int base, int i, _Timeline config, int startMs) {
  final iso = _iso(DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true));
  final wave = math.sin((config.count - i) / 3) * 0.25 + math.cos(i / 5) * 0.1;
  final aqi = math.max(1, (base * (1 + wave)).round());
  final pm25 = pm25ForAqi(aqi);
  final temperature = 17 + math.sin(i / 4) * 5;
  return {
    'timestamp': iso,
    'label': config.label(iso),
    'metrics': {
      'aqi': aqi,
      'pm1_0': pm25 * 0.68,
      'pm2_5': pm25,
      'pm10_0': pm25 * 1.42,
      'temperature': temperature,
      'humidity': 55 + math.cos(i / 3) * 12,
      'heat_index': temperature + 0.5,
    },
  };
}

/// `GET /devices/{id}/ota` before anything has been approved.
Map<String, dynamic> otaJson(String id) {
  final device = devicesJson().where((d) => d['id'] == id).firstOrNull;
  return {
    'current_version': device?['firmware_version'],
    'available': id == 'dev-new' ? _release : null,
    'job': null,
  };
}

/// A firmware update job for `POST /devices/{id}/ota/approve` and `/cancel`.
Map<String, dynamic> otaJobJson(String status) => {
  'id': 'job-prototype',
  'version': _release['version'],
  'status': status,
  'progress': 0,
  'error': null,
  'updated_at': _iso(DateTime.now()),
};

/// `GET /devices/{id}/logs`, newest first. A new monitor has none yet.
List<Map<String, dynamic>> logsJson(String id) {
  if (_seed(id)?.aqi == null) return const [];
  final now = DateTime.now();
  const entries = [
    (5, 'info', 'upload', 'Uploaded 6 readings'),
    (38, 'warn', 'wifi', 'WiFi signal is weak (-81 dBm)'),
    (52, 'info', 'wifi', 'Reconnected to WiFi'),
    (54, 'error', 'upload', 'Upload failed: connection timed out'),
    (190, 'info', 'ota', 'Firmware is up to date'),
    (195, 'info', 'boot', 'Started firmware 0.6.2'),
    (196, 'warn', 'sensor', 'Particle sensor took 3 tries to wake up'),
  ];
  return [
    for (final (i, (minutes, level, tag, message)) in entries.indexed)
      {
        'id': 900 - i,
        'level': level,
        'tag': tag,
        'message': message,
        'boot_count': i < 6 ? 12 : 11,
        'device_ts': _iso(now.subtract(Duration(minutes: minutes))),
        'created_at': _iso(now.subtract(Duration(minutes: minutes))),
      },
  ];
}

/// A mock monitor, parsed the way the app parses the API.
Device fixtureDevice(String id) =>
    Device.fromJson(devicesJson().firstWhere((d) => d['id'] == id));

/// A mock monitor's latest reading, or null when it has none.
CurrentReading? fixtureReading(String id) {
  final json = currentJson(id);
  return json == null ? null : CurrentReading.fromJson(json);
}
