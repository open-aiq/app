import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../features/account/account.dart';
import '../features/account/settings_screen.dart';
import 'monitor_illustration.dart';

/// Who is signed in and how to sign out, for the avatar menu on every screen.
/// Provided once above the Navigator in `main.dart`.
class AccountScope extends InheritedWidget {
  const AccountScope({
    super.key,
    required this.account,
    required this.onSignOut,
    required super.child,
  });

  final Account? account;

  /// Asks for confirmation, then signs out.
  final Future<void> Function(BuildContext context) onSignOut;

  static AccountScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountScope>();

  @override
  bool updateShouldNotify(AccountScope old) =>
      account != old.account || onSignOut != old.onSignOut;
}

/// The one top bar used across the app: a round back button (or the monitor
/// mark on the first screen), a title with an optional subtitle, an optional
/// status chip, and the avatar menu at the far right.
class AiqAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AiqAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.chip,
    this.showSettingsItem = true,
  });

  final String title;
  final String? subtitle;

  /// A small status chip beside the avatar, such as the update badge.
  final Widget? chip;

  /// Hide the menu's Settings item on the Settings screen itself.
  final bool showSettingsItem;

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return AppBar(
      toolbarHeight: 68,
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: Row(
        children: [
          canPop ? const _BackButton() : const _Mark(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.appBarTheme.titleTextStyle,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (chip != null) ...[chip!, const SizedBox(width: 8)],
        AccountMenuButton(showSettingsItem: showSettingsItem),
        const SizedBox(width: 12),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        fixedSize: const Size.square(40),
        minimumSize: const Size.square(40),
      ),
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back, size: 20),
    );
  }
}

/// The app's monitor mark, in place of a back button on the first screen.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        shape: BoxShape.circle,
      ),
      child: MonitorGlyph(size: 22, color: scheme.onSecondaryContainer),
    );
  }
}

/// The avatar at the right of every top bar. Everything that isn't the screen
/// itself lives here: your profile, the theme, Settings, the docs and map,
/// and Sign out.
class AccountMenuButton extends StatelessWidget {
  const AccountMenuButton({super.key, this.showSettingsItem = true});

  final bool showSettingsItem;

  @override
  Widget build(BuildContext context) {
    final scope = AccountScope.maybeOf(context);
    final account = scope?.account;
    final theme = Theme.of(context);
    return MenuAnchor(
      alignmentOffset: const Offset(-220, 4),
      menuChildren: [
        if (account != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Row(
                children: [
                  AccountAvatar(account: account, radius: 18),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (account.email != null &&
                            account.email != account.name)
                          Text(
                            account.email!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 8),
        ],
        const _ThemeRow(),
        const Divider(height: 8),
        if (showSettingsItem)
          MenuItemButton(
            leadingIcon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            child: const Text('Settings'),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.menu_book_outlined),
          trailingIcon: const Icon(Icons.open_in_new, size: 16),
          onPressed: () => _open(AppConfig.docsUrl),
          child: const Text('Docs'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.map_outlined),
          trailingIcon: const Icon(Icons.open_in_new, size: 16),
          onPressed: () => _open('${AppConfig.webUrl}/map'),
          child: const Text('Public map'),
        ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: scope == null ? null : () => scope.onSignOut(context),
          child: const Text('Sign out'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Account and settings',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: AccountAvatar(account: account),
      ),
    );
  }
}

/// Opens a link in the browser, outside the app.
Future<void> _open(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// System, Light and Dark as a compact icon row inside the avatar menu. It
/// shares [themeModePreference] with the Settings screen, so both stay in step,
/// and picking one keeps the menu open.
class _ThemeRow extends StatelessWidget {
  const _ThemeRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      child: SizedBox(
        width: 240,
        child: Row(
          children: [
            Expanded(child: Text('Theme', style: theme.textTheme.bodyLarge)),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeModePreference,
              builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined, size: 18),
                    tooltip: 'System',
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined, size: 18),
                    tooltip: 'Light',
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined, size: 18),
                    tooltip: 'Dark',
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (selection) =>
                    themeModePreference.value = selection.first,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
