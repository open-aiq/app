import 'package:flutter/material.dart';

import '../../config.dart';
import '../../widgets/aiq_app_bar.dart';
import '../../widgets/sections.dart';
import '../../widgets/soft_card.dart';
import 'account.dart';
import 'account_screen.dart';

/// App-wide settings: who's signed in, how the app looks, and what version
/// is running. Per-monitor settings live on each monitor's own screen.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = AccountScope.maybeOf(context);
    final account = scope?.account;
    return Scaffold(
      appBar: const AiqAppBar(title: 'Settings', showSettingsItem: false),
      body: ListView(
        padding: pagePadding,
        children: [
          const SectionLabel('Account'),
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    AccountAvatar(account: account, radius: 26),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account?.name ?? 'Signed in',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (account?.email != null &&
                              account!.email != account.name)
                            Text(
                              account.email!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (scope?.actions != null)
                SectionRow(
                  icon: const Icon(Icons.manage_accounts_outlined),
                  title: 'Manage account',
                  subtitle: 'Username, sign-in methods and more',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountScreen(),
                    ),
                  ),
                ),
            ],
          ),
          const SectionLabel('Appearance'),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeModePreference,
                  builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
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
                const SizedBox(height: 10),
                Text(
                  'System follows your phone’s light or dark setting.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SectionLabel('About'),
          const SectionCard(
            children: [
              SectionRow(
                icon: Icon(Icons.info_outline),
                title: 'Open AIQ',
                subtitle: 'Version ${AppConfig.appVersion}',
              ),
            ],
          ),
          if (scope != null) ...[
            const SizedBox(height: 24),
            SectionCard(
              children: [
                SectionRow(
                  icon: const Icon(Icons.logout),
                  title: 'Sign out',
                  destructive: true,
                  onTap: () => scope.onSignOut(context),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
