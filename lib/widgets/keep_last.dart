import 'package:flutter/foundation.dart';

/// Loads a value and keeps the last good one on screen while refreshing.
///
/// A refresh never clears [data]: on success it is replaced, on failure the
/// old value stays and [error] is set so the screen can show a quiet note.
/// Only the most recent request wins, so a slow, stale response (for example
/// after switching the history range) never overwrites a newer one.
class KeepLast<T> extends ChangeNotifier {
  T? _data;
  bool _hasData = false;
  Object? _error;
  DateTime? _updatedAt;
  bool _loading = false;
  int _generation = 0;
  bool _disposed = false;

  T? get data => _data;
  bool get hasData => _hasData;
  Object? get error => _error;

  /// When [data] was last loaded successfully.
  DateTime? get updatedAt => _updatedAt;
  bool get loading => _loading;

  /// Nothing to show yet: render a skeleton.
  bool get isFirstLoad => !_hasData && _error == null;

  /// Fetches a new value. Completes once the request settles; never throws.
  Future<void> load(Future<T> Function() fetch) async {
    final generation = ++_generation;
    _loading = true;
    _notify();
    try {
      final value = await fetch();
      if (generation != _generation) return;
      _data = value;
      _hasData = true;
      _error = null;
      _updatedAt = DateTime.now();
    } catch (e) {
      if (generation != _generation) return;
      _error = e;
    } finally {
      if (generation == _generation) {
        _loading = false;
        _notify();
      }
    }
  }

  /// Drops the current value, e.g. when the thing being shown changes.
  void reset() {
    _generation++;
    _data = null;
    _hasData = false;
    _error = null;
    _updatedAt = null;
    _loading = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
