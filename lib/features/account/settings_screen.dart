import 'package:flutter/material.dart';

import '../../config.dart';
import 'account.dart';

/// App-wide settings: who's signed in, how the app looks, and what version
/// is running. Per-monitor settings live on each monitor's own screen.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.account});

  final Account? account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _SectionTitle('Account'),
            ListTile(
              leading: AccountAvatar(account: account, radius: 22),
              title: Text(account?.name ?? 'Signed in'),
              subtitle: account?.email == null ? null : Text(account!.email!),
            ),
            const Divider(height: 32),
            _SectionTitle('Appearance'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: themeModePreference,
                builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) =>
                      themeModePreference.value = selection.first,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'System follows your phone’s light or dark setting.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 32),
            _SectionTitle('About'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Open AIQ'),
              subtitle: Text('Version ${AppConfig.appVersion}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
