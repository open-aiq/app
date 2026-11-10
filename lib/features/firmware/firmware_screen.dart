import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../services.dart';
import '../../widgets/sections.dart';
import '../../widgets/states.dart';

/// Firmware version, available update, owner approval and live update progress.
/// Shown as a section of the monitor's Settings tab.
class FirmwareSection extends StatefulWidget {
  const FirmwareSection({super.key, required this.device});

  final Device device;

  @override
  State<FirmwareSection> createState() => _FirmwareSectionState();
}

class _FirmwareSectionState extends State<FirmwareSection> {
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
    } catch (e) {
      if (mounted) setState(() => _actionError = friendlyError(e));
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
    } catch (e) {
      if (mounted) {
        setState(
          () => _actionError = e is ApiException && e.isConflict
              ? 'The monitor has already started updating.'
              : friendlyError(e),
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final Widget body;
    if (state == null && _loadError == null) {
      body = const Skeleton(
        key: ValueKey('loading'),
        label: 'Loading firmware status',
        child: SectionCard(
          children: [
            SkeletonShape(
              child: SectionRow(
                icon: Icon(Icons.memory),
                title: 'Installed firmware',
                subtitle: '0.0.0',
              ),
            ),
          ],
        ),
      );
    } else if (state == null) {
      body = KeyedSubtree(
        key: const ValueKey('error'),
        child: QuietNote(
          message: _loadError is ApiException
              ? (_loadError as ApiException).message
              : "Couldn't load firmware status. Tap to try again.",
          onRetry: _load,
        ),
      );
    } else {
      body = KeyedSubtree(
        key: const ValueKey('firmware'),
        child: _content(context, state),
      );
    }
    return SoftSwitcher(child: body);
  }

  Widget _content(BuildContext context, DeviceOta state) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final job = state.job;
    final active = job?.active ?? false;
    final available = state.available;
    final upToDate =
        available == null && !active && state.currentVersion != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loadError != null)
          QuietNote(updatedAt: _updatedAt, onRetry: _load),
        SectionCard(
          children: [
            SectionRow(
              icon: const Icon(Icons.memory),
              title: state.currentVersion == null
                  ? 'Installed firmware'
                  : 'Firmware ${state.currentVersion}',
              subtitle: state.currentVersion == null
                  ? "This firmware can't update over the air"
                  : upToDate
                  ? 'Up to date'
                  : null,
              trailing: upToDate
                  ? Icon(Icons.check_circle, color: scheme.secondary)
                  : null,
            ),
            if (job != null && !active && job.status == 'failed')
              SectionRow(
                icon: const Icon(Icons.error_outline),
                destructive: true,
                title: 'Update to ${job.version} failed',
                subtitle: job.error ?? 'Unknown error',
              ),
            if (job != null && job.status == 'succeeded' && available == null)
              SectionRow(
                icon: const Icon(Icons.celebration_outlined),
                title: 'Updated to ${job.version}',
              ),
            if (active) _JobCard(job: job!, onCancel: _acting ? null : _cancel),
            if (available != null && !active)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconBubble(
                          icon: const Icon(Icons.system_update),
                          background: scheme.tertiaryContainer,
                          foreground: scheme.onTertiaryContainer,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Version ${available.version} is ready',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${(available.size / 1024).round()} KB',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (available.notes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(available.notes),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _acting ? null : () => _approve(available),
                        icon: const Icon(Icons.system_update),
                        label: const Text('Install update'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        InlineError(_actionError),
      ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            value: job.status == 'approved' ? null : job.progress / 100,
            semanticsLabel: 'Update progress',
            semanticsValue: '${job.progress}%',
          ),
          if (job.status == 'approved') ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onCancel, child: const Text('Cancel update')),
          ],
        ],
      ),
    );
  }
}
