import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services.dart';
import '../../widgets/states.dart';

/// Important events uploaded by the monitor (errors, WiFi, OTA, boots).
/// Shown as the Logs tab of the monitor screen.
class LogsView extends StatefulWidget {
  const LogsView({super.key, required this.device});

  final Device device;

  @override
  State<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends State<LogsView> {
  static const _filters = {null: 'All', 'warn': 'Warnings', 'error': 'Errors'};

  String? _minLevel;
  final List<DeviceLogEntry> _entries = [];
  int? _nextBefore;
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  /// Whether [_error] came from loading the next page rather than a refresh.
  bool _pagingError = false;
  DateTime? _updatedAt;

  /// Ignores responses to requests that a newer one has replaced.
  int _generation = 0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        _loadMore();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded && !_loading) _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Loads the newest page. Entries already on screen stay until it arrives.
  Future<void> _reload() => _fetch();

  /// A different filter is a different list, so start from a skeleton.
  void _changeFilter(String? minLevel) {
    setState(() {
      _minLevel = minLevel;
      _entries.clear();
      _nextBefore = null;
      _loaded = false;
      _error = null;
    });
    _fetch();
  }

  Future<void> _loadMore() async {
    if (_loading || !_loaded || _nextBefore == null) return;
    await _fetch(before: _nextBefore);
  }

  Future<void> _fetch({int? before}) async {
    final generation = ++_generation;
    setState(() => _loading = true);
    String? error;
    try {
      final page = await AppServices.of(
        context,
      ).api.logs(widget.device.id, minLevel: _minLevel, before: before);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (before == null) _entries.clear();
        _entries.addAll(page.entries);
        _nextBefore = page.nextBefore;
        _loaded = true;
        _error = null;
        if (before == null) _updatedAt = DateTime.now();
      });
      return;
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not load logs. Check your connection.';
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _error = error;
      _pagingError = before != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<String?>(
                segments: [
                  for (final e in _filters.entries)
                    ButtonSegment(value: e.key, label: Text(e.value)),
                ],
                selected: {_minLevel},
                onSelectionChanged: (selection) =>
                    _changeFilter(selection.first),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (!_loaded && _error == null) {
      return const _LogsSkeleton();
    }
    if (!_loaded) {
      return ErrorView(message: _error!, onRetry: _reload);
    }
    final refreshNote = _error != null && !_pagingError
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: QuietNote(updatedAt: _updatedAt, onRetry: _reload),
          )
        : null;
    if (_entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          children: [
            ?refreshNote,
            const SizedBox(height: 80),
            const EmptyView(
              icon: Icons.receipt_long,
              title: 'No log entries',
              message:
                  'The monitor uploads warnings, errors and important events after each reading.',
            ),
          ],
        ),
      );
    }
    final lead = refreshNote == null ? 0 : 1;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scroll,
        itemCount: lead + _entries.length + 1,
        itemBuilder: (context, index) {
          if (index < lead) return refreshNote!;
          final i = index - lead;
          if (i == _entries.length) {
            if (_error != null && _pagingError) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: QuietNote(
                  message: "Couldn't load older entries. Tap to try again.",
                  onRetry: _loadMore,
                ),
              );
            }
            return _nextBefore == null
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('End of logs')),
                  )
                : const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
          }
          return _LogTile(entry: _entries[i]);
        },
      ),
    );
  }
}

/// First-load placeholder shaped like a few log rows.
class _LogsSkeleton extends StatelessWidget {
  const _LogsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      label: 'Loading logs',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (var i = 0; i < 6; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBlock(width: 24, height: 24, radius: 12),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBlock(height: 14),
                        SizedBox(height: 8),
                        SkeletonBlock(width: 120, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final DeviceLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (entry.level) {
      'error' => (Icons.error, scheme.error),
      'warn' => (Icons.warning_amber, Colors.orange.shade800),
      _ => (Icons.info_outline, scheme.primary),
    };
    final time = DateFormat.yMMMd().add_Hms().format(entry.time);
    return ListTile(
      leading: Icon(icon, color: color, semanticLabel: entry.level),
      title: Text(entry.message),
      subtitle: Text(
        '${entry.tag.isEmpty ? '' : '${entry.tag} · '}$time · boot #${entry.bootCount}'
        '${entry.deviceTs == null ? ' (received)' : ''}',
      ),
    );
  }
}
