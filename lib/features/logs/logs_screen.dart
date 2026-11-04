import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services.dart';
import '../../widgets/states.dart';

/// Important events uploaded by the monitor (errors, WiFi, OTA, boots).
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, required this.device});

  final Device device;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  static const _filters = {null: 'All', 'warn': 'Warnings', 'error': 'Errors'};

  String? _minLevel;
  final List<DeviceLogEntry> _entries = [];
  int? _nextBefore;
  bool _loading = false;
  bool _loaded = false;
  String? _error;
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

  Future<void> _reload() async {
    _entries.clear();
    _nextBefore = null;
    _loaded = false;
    await _fetch();
  }

  Future<void> _loadMore() async {
    if (_loading || !_loaded || _nextBefore == null) return;
    await _fetch(before: _nextBefore);
  }

  Future<void> _fetch({int? before}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await AppServices.of(
        context,
      ).api.logs(widget.device.id, minLevel: _minLevel, before: before);
      setState(() {
        _entries.addAll(page.entries);
        _nextBefore = page.nextBefore;
        _loaded = true;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not load logs. Check your connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device logs')),
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
                onSelectionChanged: (selection) {
                  setState(() => _minLevel = selection.first);
                  _reload();
                },
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (!_loaded && _loading) {
      return const LoadingView(message: 'Loading logs…');
    }
    if (!_loaded && _error != null) {
      return ErrorView(message: _error!, onRetry: _reload);
    }
    if (_entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            EmptyView(
              icon: Icons.receipt_long,
              title: 'No log entries',
              message:
                  'The monitor uploads warnings, errors and important events after each reading.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scroll,
        itemCount: _entries.length + 1,
        itemBuilder: (context, index) {
          if (index == _entries.length) {
            if (_error != null) return InlineError(_error);
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
          return _LogTile(entry: _entries[index]);
        },
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
