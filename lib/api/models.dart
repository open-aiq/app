// JSON models for the Open AIQ backend (backend/internal/*/model.go).

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

double _double(Object? value) => value is num ? value.toDouble() : 0;

int _int(Object? value) => value is num ? value.toInt() : 0;

/// Firmware-update badge state from `GET /devices` (`ota`).
class OtaSummary {
  const OtaSummary({required this.status, this.version, this.progress});

  factory OtaSummary.fromJson(Map<String, dynamic> json) => OtaSummary(
    status: json['status'] as String? ?? 'up_to_date',
    version: json['version'] as String?,
    progress: json['progress'] as int?,
  );

  /// up_to_date, update_available, approved, downloading, installing, failed.
  final String status;
  final String? version;
  final int? progress;

  bool get needsAttention => status != 'up_to_date';
  bool get inProgress =>
      status == 'approved' || status == 'downloading' || status == 'installing';
}

class Device {
  const Device({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.isOutdoor,
    required this.isPublic,
    required this.isLocationPublic,
    this.firmwareVersion,
    this.ota,
    this.createdAt,
  });

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    id: json['id'] as String,
    deviceId: json['device_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    isOutdoor: json['is_outdoor'] as bool? ?? false,
    isPublic: json['is_public'] as bool? ?? false,
    isLocationPublic: json['is_location_public'] as bool? ?? false,
    firmwareVersion: json['firmware_version'] as String?,
    ota: json['ota'] is Map<String, dynamic>
        ? OtaSummary.fromJson(json['ota'] as Map<String, dynamic>)
        : null,
    createdAt: _date(json['created_at']),
  );

  /// Internal UUID used in API paths.
  final String id;

  /// Public `dev_…` identifier stored on the device.
  final String deviceId;
  final String name;
  final bool isOutdoor;
  final bool isPublic;
  final bool isLocationPublic;
  final String? firmwareVersion;
  final OtaSummary? ota;
  final DateTime? createdAt;
}

/// Returned once by `POST /devices` and `POST /devices/{id}/rotate-key`.
class CreatedDevice {
  const CreatedDevice({required this.device, required this.deviceKey});

  factory CreatedDevice.fromJson(Map<String, dynamic> json) => CreatedDevice(
    device: Device.fromJson(json),
    deviceKey: json['device_key'] as String,
  );

  final Device device;

  /// Secret `sk_…` key; never returned again by the API.
  final String deviceKey;
}

class Metrics {
  const Metrics({
    this.pm1 = 0,
    this.pm25 = 0,
    this.pm10 = 0,
    this.aqi = 0,
    this.temperature = 0,
    this.humidity = 0,
    this.heatIndex = 0,
  });

  factory Metrics.fromJson(Map<String, dynamic> json) => Metrics(
    pm1: _double(json['pm1_0']),
    pm25: _double(json['pm2_5']),
    pm10: _double(json['pm10_0']),
    aqi: _int(json['aqi']),
    temperature: _double(json['temperature']),
    humidity: _double(json['humidity']),
    heatIndex: _double(json['heat_index']),
  );

  final double pm1;
  final double pm25;
  final double pm10;
  final int aqi;
  final double temperature;
  final double humidity;
  final double heatIndex;
}

/// `GET /devices/{id}/current`: last-hour average plus online status.
class CurrentReading {
  const CurrentReading({
    required this.online,
    required this.metrics,
    required this.sampleCount,
    this.lastSeen,
    this.lat,
    this.lon,
  });

  factory CurrentReading.fromJson(Map<String, dynamic> json) {
    final location = json['location'];
    return CurrentReading(
      online: json['status'] == 'online',
      lastSeen: _date(json['last_seen']),
      metrics: Metrics.fromJson(json),
      sampleCount: _int(json['sample_count']),
      lat: location is Map ? _double(location['lat']) : null,
      lon: location is Map ? _double(location['lon']) : null,
    );
  }

  final bool online;
  final DateTime? lastSeen;
  final Metrics metrics;

  /// 0 when the device has been offline longer than the averaging window.
  final int sampleCount;
  final double? lat;
  final double? lon;
}

class HistoricalPoint {
  const HistoricalPoint({
    required this.timestamp,
    required this.label,
    required this.metrics,
  });

  factory HistoricalPoint.fromJson(Map<String, dynamic> json) =>
      HistoricalPoint(
        timestamp: _date(json['timestamp']) ?? DateTime.now(),
        label: json['label'] as String? ?? '',
        metrics: Metrics.fromJson(
          (json['metrics'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );

  final DateTime timestamp;
  final String label;
  final Metrics metrics;
}

class FirmwareRelease {
  const FirmwareRelease({
    required this.id,
    required this.version,
    required this.size,
    required this.notes,
  });

  factory FirmwareRelease.fromJson(Map<String, dynamic> json) =>
      FirmwareRelease(
        id: json['id'] as String,
        version: json['version'] as String,
        size: _int(json['size']),
        notes: json['notes'] as String? ?? '',
      );

  final String id;
  final String version;
  final int size;
  final String notes;
}

class OtaJob {
  const OtaJob({
    required this.id,
    required this.version,
    required this.status,
    required this.progress,
    this.error,
    this.updatedAt,
  });

  factory OtaJob.fromJson(Map<String, dynamic> json) => OtaJob(
    id: json['id'] as String,
    version: json['version'] as String? ?? '',
    status: json['status'] as String,
    progress: _int(json['progress']),
    error: json['error'] as String?,
    updatedAt: _date(json['updated_at']),
  );

  final String id;
  final String version;

  /// approved, downloading, installing, succeeded, failed, cancelled.
  final String status;
  final int progress;
  final String? error;
  final DateTime? updatedAt;

  bool get active =>
      status == 'approved' || status == 'downloading' || status == 'installing';
}

/// `GET /devices/{id}/ota`.
class DeviceOta {
  const DeviceOta({this.currentVersion, this.available, this.job});

  factory DeviceOta.fromJson(Map<String, dynamic> json) => DeviceOta(
    currentVersion: json['current_version'] as String?,
    available: json['available'] is Map<String, dynamic>
        ? FirmwareRelease.fromJson(json['available'] as Map<String, dynamic>)
        : null,
    job: json['job'] is Map<String, dynamic>
        ? OtaJob.fromJson(json['job'] as Map<String, dynamic>)
        : null,
  );

  final String? currentVersion;
  final FirmwareRelease? available;
  final OtaJob? job;
}

class DeviceLogEntry {
  const DeviceLogEntry({
    required this.id,
    required this.level,
    required this.tag,
    required this.message,
    required this.bootCount,
    required this.createdAt,
    this.deviceTs,
  });

  factory DeviceLogEntry.fromJson(Map<String, dynamic> json) => DeviceLogEntry(
    id: _int(json['id']),
    level: json['level'] as String? ?? 'info',
    tag: json['tag'] as String? ?? '',
    message: json['message'] as String? ?? '',
    bootCount: _int(json['boot_count']),
    deviceTs: _date(json['device_ts']),
    createdAt: _date(json['created_at']) ?? DateTime.now(),
  );

  final int id;
  final String level;
  final String tag;
  final String message;
  final int bootCount;
  final DateTime? deviceTs;
  final DateTime createdAt;

  /// Device wall-clock time when synced, otherwise when the backend received it.
  DateTime get time => deviceTs ?? createdAt;
}

class LogPage {
  const LogPage({required this.entries, this.nextBefore});

  final List<DeviceLogEntry> entries;

  /// Cursor for the next (older) page, or null at the end.
  final int? nextBefore;
}
