import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Returns the current Clerk session JWT, or null when signed out.
typedef TokenProvider = Future<String?> Function();

/// An RFC 7807 problem returned by the backend (internal/platform/problem).
class ApiException implements Exception {
  ApiException(
    this.status, {
    this.type,
    this.title,
    this.detail,
    this.errors = const [],
  });

  factory ApiException.fromResponse(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        return ApiException(
          response.statusCode,
          type: body['type'] as String?,
          title: body['title'] as String?,
          detail: body['detail'] as String?,
          errors:
              (body['errors'] as List?)?.cast<Map<String, dynamic>>() ??
              const [],
        );
      }
    } on FormatException {
      // Not a problem document; fall through.
    }
    return ApiException(response.statusCode);
  }

  final int status;
  final String? type;
  final String? title;
  final String? detail;
  final List<Map<String, dynamic>> errors;

  bool get isNoReadings => type?.endsWith('#no-readings') ?? false;
  bool get isNotFound => status == 404 && !isNoReadings;
  bool get isUnauthorized => status == 401;
  bool get isConflict => status == 409;

  /// Message suitable for showing to the user.
  String get message => detail ?? title ?? 'Request failed ($status).';

  @override
  String toString() => 'ApiException($status, $message)';
}

/// Typed client for the Clerk-authenticated backend API (same as the web dashboard).
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.tokenProvider,
    http.Client? httpClient,
  }) : _base = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _http = httpClient ?? http.Client();

  final String _base;
  final TokenProvider tokenProvider;
  final http.Client _http;

  Future<Object?> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final token = await tokenProvider();
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final request = http.Request(method, uri);
    request.headers['Accept'] = 'application/json';
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(
      await _http.send(request).timeout(const Duration(seconds: 20)),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException.fromResponse(response);
    }
    if (response.statusCode == 204 || response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  Map<String, dynamic> _data(Object? body) =>
      ((body as Map<String, dynamic>)['data'] as Map).cast<String, dynamic>();

  List<Map<String, dynamic>> _list(Object? body) =>
      (((body as Map<String, dynamic>)['data'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  Future<List<Device>> listDevices() async =>
      _list(await _request('GET', '/devices')).map(Device.fromJson).toList();

  Future<CreatedDevice> registerDevice({
    required String name,
    bool isOutdoor = false,
    bool isPublic = false,
    bool isLocationPublic = false,
  }) async => CreatedDevice.fromJson(
    _data(
      await _request(
        'POST',
        '/devices',
        body: {
          'name': name,
          'is_outdoor': isOutdoor,
          'is_public': isPublic,
          'is_location_public': isPublic && isLocationPublic,
        },
      ),
    ),
  );

  /// Partial update; only non-null fields are sent.
  Future<Device> updateDevice(
    String id, {
    String? name,
    bool? isOutdoor,
    bool? isPublic,
    bool? isLocationPublic,
  }) async {
    final patch = <String, Object>{
      'name': ?name,
      'is_outdoor': ?isOutdoor,
      'is_public': ?isPublic,
      'is_location_public': ?isLocationPublic,
    };
    return Device.fromJson(
      _data(await _request('PATCH', '/devices/$id', body: patch)),
    );
  }

  Future<CreatedDevice> rotateKey(String id) async => CreatedDevice.fromJson(
    _data(await _request('POST', '/devices/$id/rotate-key')),
  );

  Future<void> deleteDevice(String id) => _request('DELETE', '/devices/$id');

  /// Deletes every monitor you own (with its readings, logs and update
  /// history), then your sign-in. `DELETE /account` answers 204.
  Future<void> deleteAccount() => _request('DELETE', '/account');

  Future<CurrentReading> current(String id) async => CurrentReading.fromJson(
    _data(await _request('GET', '/devices/$id/current')),
  );

  /// [timeline] is daily, weekly, monthly or yearly.
  Future<List<HistoricalPoint>> historical(String id, String timeline) async =>
      _list(
        await _request(
          'GET',
          '/devices/$id/historical',
          query: {'timeline': timeline},
        ),
      ).map(HistoricalPoint.fromJson).toList();

  Future<DeviceOta> ota(String id) async =>
      DeviceOta.fromJson(_data(await _request('GET', '/devices/$id/ota')));

  Future<OtaJob> approveOta(String id, String releaseId) async =>
      OtaJob.fromJson(
        _data(
          await _request(
            'POST',
            '/devices/$id/ota/approve',
            body: {'release_id': releaseId},
          ),
        ),
      );

  Future<OtaJob> cancelOta(String id) async =>
      OtaJob.fromJson(_data(await _request('POST', '/devices/$id/ota/cancel')));

  /// [minLevel] is debug, info, warn or error (null = all).
  Future<LogPage> logs(
    String id, {
    String? minLevel,
    int? before,
    int limit = 50,
  }) async {
    final body = await _request(
      'GET',
      '/devices/$id/logs',
      query: {
        'limit': '$limit',
        'level': ?minLevel,
        if (before != null) 'before': '$before',
      },
    );
    return LogPage(
      entries: _list(body).map(DeviceLogEntry.fromJson).toList(),
      nextBefore: ((body as Map<String, dynamic>)['next_before'] as num?)
          ?.toInt(),
    );
  }
}
