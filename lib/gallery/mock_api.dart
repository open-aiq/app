import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../api/api_client.dart';
import 'fixtures.dart';

/// An in-memory backend for the gallery and the hosted prototype. It answers
/// the same routes as the real API with the mock monitors in `fixtures.dart`,
/// after a short pause so loading states show. Changes (rename, delete,
/// approve an update) last until the page reloads.
class MockApi {
  MockApi({this.delay = const Duration(milliseconds: 300)});

  /// How long each request takes, so skeletons and pending states show.
  final Duration delay;

  late final ApiClient client = ApiClient(
    baseUrl: 'https://prototype.invalid/api/v1',
    tokenProvider: () async => null,
    httpClient: MockClient(_handle),
  );

  final List<Map<String, dynamic>> _devices = devicesJson();
  final Map<String, Map<String, dynamic>> _jobs = {};

  Future<http.Response> _handle(http.Request request) async {
    await Future<void>.delayed(delay);
    final path = request.url.path.replaceFirst('/api/v1', '');
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final method = request.method;

    if (path == '/account' && method == 'DELETE') return _empty();
    if (segments.isEmpty || segments.first != 'devices') return _notFound();
    if (segments.length == 1 && method == 'GET') {
      return _json({'data': _devices});
    }

    final device = _devices.where((d) => d['id'] == segments[1]).firstOrNull;
    if (device == null) return _notFound();
    final id = device['id'] as String;
    final action = segments.length > 2 ? segments.sublist(2).join('/') : '';

    switch ((method, action)) {
      case ('PATCH', ''):
        final patch = (jsonDecode(request.body) as Map).cast<String, Object?>();
        device.addAll(patch);
        return _json({'data': device});
      case ('DELETE', ''):
        _devices.remove(device);
        return _empty();
      case ('GET', 'current'):
        final current = currentJson(id);
        if (current == null) {
          return _problem(
            404,
            'No readings yet',
            type: 'https://docs.air-iq.net/reference/errors/#no-readings',
          );
        }
        return _json({'data': current});
      case ('GET', 'historical'):
        final timeline = request.url.queryParameters['timeline'] ?? 'daily';
        return _json({'data': historyJson(id, timeline)});
      case ('GET', 'ota'):
        return _json({
          'data': {...otaJson(id), 'job': _jobs[id]},
        });
      case ('POST', 'ota/approve'):
        final job = _jobs[id] = otaJobJson('approved');
        device['ota'] = {
          'status': 'approved',
          'version': job['version'],
          'progress': 0,
        };
        return _json({'data': job});
      case ('POST', 'ota/cancel'):
        final job = _jobs.remove(id);
        if (job == null) return _problem(409, 'No update to cancel');
        device['ota'] = {
          'status': 'update_available',
          'version': job['version'],
        };
        return _json({
          'data': {...job, 'status': 'cancelled'},
        });
      case ('GET', 'logs'):
        return _json({
          'data': _filterLogs(logsJson(id), request.url.queryParameters),
          'next_before': null,
        });
    }
    return _notFound();
  }

  static const _levels = ['debug', 'info', 'warn', 'error'];

  /// Applies the `level` filter (that level and above), like the backend.
  List<Map<String, dynamic>> _filterLogs(
    List<Map<String, dynamic>> entries,
    Map<String, String> query,
  ) {
    final min = _levels.indexOf(query['level'] ?? 'debug');
    return [
      for (final entry in entries)
        if (_levels.indexOf(entry['level'] as String) >= min) entry,
    ];
  }

  static const _headers = {'content-type': 'application/json; charset=utf-8'};

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: _headers);

  http.Response _empty() => http.Response('', 204);

  http.Response _notFound() => _problem(404, 'Not found');

  http.Response _problem(int status, String title, {String? type}) => _json({
    'type': type ?? 'about:blank',
    'title': title,
    'status': status,
  }, status);
}
