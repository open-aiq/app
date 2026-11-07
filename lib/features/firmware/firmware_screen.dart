import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services.dart';
import '../../widgets/states.dart';

/// Firmware version, available update, owner approval and live update progress.
/// Shown as the Updates tab of the monitor screen.
class FirmwareView extends StatefulWidget {
  const FirmwareView({super.key, required this.device});

  final Device device;

  @override
  State<FirmwareView> createState() => _FirmwareViewState();
}

class _FirmwareViewState extends State<FirmwareView> {
  DeviceOta? _state;
  Object? _loadError;
  DateTime? _updatedAt;
  String? _actionError;
  bool _acting = false;
  Timer? _poll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_poll == null) {
      _load();
      _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final state = await AppServices.of(context).api.ota(widget.device.id);
      if (mounted) {
        setState(() {
          _state = state;
          _loadError = null;
          _updatedAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _approve(FirmwareRelease release) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Install firmware ${release.version}?',
      message:
          'The monitor downloads the update, restarts and checks itself. Keep it powered and on WiFi. '
          'If the new firmware fails, the monitor returns to the current version automatically.',
      confirmLabel: 'Install update',
    );
    if (!confirmed || !mounted) return;
    final services = AppServices.of(context);
    setState(() {
      _acting = true;
      _actionError = null;
    });
    try {
      await services.api.approveOta(widget.device.id, release.id);
      // When connected over BLE, start right away instead of at the next check-in.
      if (services.ble.isConnectedTo(widget.device.deviceId)) {
        await services.ble.session!.otaCheck().catchError((_) {});
      }
      await _load();
    } on ApiException catch (e) {
      setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _cancel() async {
    setState(() {
      _acting = true;
      _actionError = null;
    });
    try {
      await AppServices.of(context).api.cancelOta(widget.device.id);
      await _load();
    } on ApiException catch (e) {
      setState(
        () => _actionError = e.isConflict
            ? 'The monitor has already started updating.'
            : e.message,
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _state;
    return Scaffold(
      body: SafeArea(
        child: state == null
            ? (_loadError != null
                  ? ErrorView(
                      message: _loadError is ApiException
                          ? (_loadError as ApiException).message
                          : 'Could not load firmware status.',
                      onRetry: _load,
                    )
                  : const Skeleton(
                      label: 'Loading firmware status',
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBlock(width: 220, height: 40),
                            SizedBox(height: 24),
                            SkeletonBlock(height: 120, radius: 12),
                          ],
                        ),
                      ),
                    ))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_loadError != null)
                      QuietNote(updatedAt: _updatedAt, onRetry: _load),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.memory),
                      title: const Text('Installed firmware'),
                      subtitle: Text(
                        state.currentVersion ??
                            'Unknown (this firmware cannot update over the air)',
                      ),
                    ),
                    InlineError(_actionError),
                    if (state.job != null && state.job!.active)
                      _JobCard(
                        job: state.job!,
                        onCancel: _acting ? null : _cancel,
                      ),
                    if (state.job != null &&
                        !state.job!.active &&
                        state.job!.status == 'failed')
                      InlineError(
                        'The last update to ${state.job!.version} failed: ${state.job!.error ?? 'unknown error'}.',
                      ),
                    if (state.job != null &&
                        state.job!.status == 'succeeded' &&
                        state.available == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Updated to ${state.job!.version}.',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    if (state.available != null &&
                        !(state.job?.active ?? false))
                      Card.outlined(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Update available: ${state.available!.version}',
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                '${(state.available!.size / 1024).round()} KB',
                              ),
                              if (state.available!.notes.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(state.available!.notes),
                              ],
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _acting
                                    ? null
                                    : () => _approve(state.available!),
                                icon: const Icon(Icons.system_update),
                                label: const Text('Approve and install'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (state.available == null &&
                        !(state.job?.active ?? false) &&
                        state.currentVersion != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('The monitor is up to date.'),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.onCancel});

  final OtaJob job;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, detail) = switch (job.status) {
      'approved' => (
        'Update to ${job.version} approved',
        'The monitor starts downloading at its next check-in (within about 10 minutes), or right away if it is connected over Bluetooth.',
      ),
      'downloading' => (
        'Downloading ${job.version}',
        'Keep the monitor powered and on WiFi.',
      ),
      _ => (
        'Installing ${job.version}',
        'The monitor is restarting and verifying the new firmware.',
      ),
    };
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(detail),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: job.status == 'approved' ? null : job.progress / 100,
              semanticsLabel: 'Update progress',
              semanticsValue: '${job.progress}%',
            ),
            if (job.status == 'approved') ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onCancel,
                child: const Text('Cancel update'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
