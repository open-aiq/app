import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services.dart';
import '../../widgets/monitor_illustration.dart';
import '../../widgets/sections.dart';
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String?>(
                segments: [
                  for (final e in _filters.entries)
                    ButtonSegment(value: e.key, label: Text(e.value)),
                ],
                selected: {_minLevel},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    _changeFilter(selection.first),
              ),
            ),
          ),
          Expanded(child: SoftSwitcher(child: _body())),
        ],
      ),
    );
  }

  Widget _body() {
    if (!_loaded && _error == null) {
      return const _LogsSkeleton(key: ValueKey('loading'));
    }
    if (!_loaded) {
      return KeyedSubtree(
        key: const ValueKey('error'),
        child: ErrorView(message: _error!, onRetry: _reload),
      );
    }
    final refreshNote = _error != null && !_pagingError
        ? QuietNote(updatedAt: _updatedAt, onRetry: _reload)
        : null;
    if (_entries.isEmpty) {
      return RefreshIndicator(
        key: ValueKey('empty-$_minLevel'),
        onRefresh: _reload,
        child: ListView(
          padding: pagePadding,
          children: [
            ?refreshNote,
            const SizedBox(height: 48),
            const EmptyView(
              illustration: MonitorIllustration(size: 110),
              title: 'All quiet',
              message:
                  'Warnings, errors and important events from the monitor will show up here.',
            ),
          ],
        ),
      );
    }
    final theme = Theme.of(context);
    return RefreshIndicator(
      key: ValueKey('logs-$_minLevel'),
      onRefresh: _reload,
      child: ListView(
        controller: _scroll,
        padding: pagePadding,
        children: [
          ?refreshNote,
          for (final day in _byDay(_entries)) ...[
            SectionLabel(day.label),
            SectionCard(
              children: [for (final entry in day.entries) _LogRow(entry)],
            ),
          ],
          Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: _error != null && _pagingError
                  ? QuietNote(
                      message: "Couldn't load older entries. Tap to try again.",
                      onRetry: _loadMore,
                    )
                  : Text(
                      _nextBefore == null
                          ? "That's everything"
                          : 'Loading older entries…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Entries for one calendar day, newest first.
typedef _Day = ({String label, List<DeviceLogEntry> entries});

List<_Day> _byDay(List<DeviceLogEntry> entries) {
  final days = <_Day>[];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  for (final entry in entries) {
    final local = entry.time.toLocal();
    final date = DateTime(local.year, local.month, local.day);
    final age = today.difference(date).inDays;
    final label = switch (age) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => DateFormat.yMMMEd().format(date),
    };
    if (days.isEmpty || days.last.label != label) {
      days.add((label: label, entries: [entry]));
    } else {
      days.last.entries.add(entry);
    }
  }
  return days;
}

/// First-load placeholder: the same rows as the real list, as soft shapes.
class _LogsSkeleton extends StatelessWidget {
  const _LogsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      label: 'Loading logs',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: pagePadding,
        children: [
          const SectionLabel('Today'),
          SectionCard(
            children: [
              for (var i = 0; i < 5; i++)
                const SkeletonShape(
                  child: _LogRowLayout(
                    level: 'info',
                    message: 'WiFi connected to the home network',
                    meta: '12:00:00 · wifi · boot #1',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow(this.entry);

  final DeviceLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.Hms().format(entry.time.toLocal());
    return _LogRowLayout(
      level: entry.level,
      message: entry.message,
      meta:
          '$time${entry.tag.isEmpty ? '' : ' · ${entry.tag}'} · boot #${entry.bootCount}'
          '${entry.deviceTs == null ? ' · received' : ''}',
    );
  }
}

/// A log line: a tinted level icon, the message and a quiet detail line.
class _LogRowLayout extends StatelessWidget {
  const _LogRowLayout({
    required this.level,
    required this.message,
    required this.meta,
  });

  final String level;
  final String message;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, background, foreground, name) = switch (level) {
      'error' => (
        Icons.error_outline,
        scheme.errorContainer,
        scheme.onErrorContainer,
        'Error',
      ),
      'warn' => (
        Icons.warning_amber_rounded,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        'Warning',
      ),
      _ => (
        Icons.info_outline,
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        'Info',
      ),
    };
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: name,
              child: IconBubble(
                icon: Icon(icon),
                background: background,
                foreground: foreground,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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
