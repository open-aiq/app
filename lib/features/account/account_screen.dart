import 'package:flutter/material.dart';

import '../../widgets/aiq_app_bar.dart';
import '../../widgets/sections.dart';
import '../../widgets/states.dart';
import 'account.dart';

/// Your profile, the ways you sign in, and deleting your account. It reads
/// and changes everything through [AccountScope.actions], so it works the
/// same over Clerk and in the gallery.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  /// What's running right now, for the progress bar and to pause other rows.
  String? _pending;
  String? _error;

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  /// Runs a one-tap change with a progress bar and a calm inline error.
  Future<bool> _run(
    String label,
    Future<void> Function() action, {
    String? done,
  }) async {
    if (_pending != null) return false;
    setState(() {
      _pending = label;
      _error = null;
    });
    try {
      await action();
      if (mounted && done != null) _snack(done);
      return true;
    } on AccountActionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = _fallbackError);
    } finally {
      if (mounted) setState(() => _pending = null);
    }
    return false;
  }

  Future<void> _editUsername(AccountActions actions) async {
    final current = actions.username;
    final saved = await showActionDialog(
      context,
      title: current == null ? 'Choose a username' : 'Change your username',
      fields: [AccountField('Username', initial: current ?? '')],
      submitLabel: 'Save',
      pendingLabel: 'Saving…',
      ready: (values) {
        final next = values.single.trim();
        return next.isNotEmpty && next != current;
      },
      onSubmit: (values) => actions.updateUsername(values.single.trim()),
    );
    if (saved && mounted) _snack('Username saved');
  }

  Future<void> _addEmail(AccountActions actions) async {
    String? id;
    String? address;
    final sent = await showActionDialog(
      context,
      title: 'Add an email address',
      content: const Text('We’ll email you a code to check it’s yours.'),
      fields: const [
        AccountField(
          'Email address',
          keyboardType: TextInputType.emailAddress,
          autofillHints: [AutofillHints.email],
        ),
      ],
      submitLabel: 'Send code',
      pendingLabel: 'Sending…',
      ready: (values) => values.single.contains('@'),
      onSubmit: (values) async {
        address = values.single.trim();
        id = await actions.addEmail(address!);
      },
    );
    if (sent && mounted) await _verifyEmail(actions, id!, address!);
  }

  /// Sends a fresh code to an address that was added but never verified.
  Future<void> _resendCode(AccountActions actions, AccountEmail email) async {
    String? id;
    final sent = await _run(
      'Sending a code',
      () async => id = await actions.addEmail(email.address),
    );
    if (sent && mounted) await _verifyEmail(actions, id!, email.address);
  }

  Future<void> _verifyEmail(
    AccountActions actions,
    String id,
    String address,
  ) async {
    final verified = await showActionDialog(
      context,
      title: 'Check your email',
      content: Text('Enter the 6-digit code we sent to $address.'),
      fields: const [
        AccountField(
          'Code',
          keyboardType: TextInputType.number,
          autofillHints: [AutofillHints.oneTimeCode],
        ),
      ],
      submitLabel: 'Verify',
      pendingLabel: 'Checking…',
      ready: (values) => RegExp(r'^\d{6}$').hasMatch(values.single.trim()),
      onSubmit: (values) => actions.verifyEmail(id, values.single.trim()),
    );
    if (verified && mounted) _snack('$address is verified');
  }

  Future<void> _removeEmail(AccountActions actions, AccountEmail email) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Remove ${email.address}?',
      message: 'You won’t be able to sign in with it any more.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      'Removing ${email.address}',
      () => actions.removeEmail(email.id),
      done: 'Address removed',
    );
  }

  Future<void> _connect(AccountActions actions, String provider) async {
    final label = providerLabel(provider);
    await _run('Connecting $label', () async {
      await actions.connect(context, provider);
      // Closing the sign-in page without finishing changes nothing.
      if (mounted &&
          actions.connectedAccounts.any((a) => a.provider == provider)) {
        _snack('$label connected');
      }
    });
  }

  Future<void> _disconnect(
    AccountActions actions,
    ConnectedAccount account,
  ) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Disconnect ${account.label}?',
      message:
          'You won’t be able to sign in with ${account.label} until you '
          'connect it again.',
      confirmLabel: 'Disconnect',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      'Disconnecting ${account.label}',
      () => actions.disconnect(account.id),
      done: '${account.label} disconnected',
    );
  }

  Future<void> _setPassword(AccountActions actions) async {
    final change = actions.passwordEnabled;
    final saved = await showActionDialog(
      context,
      title: change ? 'Change your password' : 'Set a password',
      content: change
          ? const Text('We’ll sign you out on your other devices.')
          : const Text('Then you can sign in with your email and password.'),
      fields: [
        if (change)
          const AccountField(
            'Current password',
            obscure: true,
            autofillHints: [AutofillHints.password],
          ),
        const AccountField(
          'New password',
          obscure: true,
          autofillHints: [AutofillHints.newPassword],
        ),
      ],
      submitLabel: 'Save',
      pendingLabel: 'Saving…',
      onSubmit: (values) => actions.setPassword(
        current: change ? values.first : null,
        next: values.last,
      ),
    );
    if (saved && mounted) _snack(change ? 'Password changed' : 'Password set');
  }

  Future<void> _removePassword(AccountActions actions) async {
    final removed = await showActionDialog(
      context,
      title: 'Remove your password?',
      content: const Text(
        'You can still sign in with your email address or a connected '
        'account.',
      ),
      fields: const [
        AccountField(
          'Current password',
          obscure: true,
          autofillHints: [AutofillHints.password],
        ),
      ],
      submitLabel: 'Remove',
      pendingLabel: 'Removing…',
      destructive: true,
      onSubmit: (values) => actions.removePassword(values.single),
    );
    if (removed && mounted) _snack('Password removed');
  }

  Future<void> _deleteAccount(AccountActions actions) async {
    final theme = Theme.of(context);
    await showActionDialog(
      context,
      title: 'Delete your account?',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes every monitor in your account, with its '
            'readings, logs and update history, and then your sign-in. It '
            'can’t be undone.',
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'To confirm, type '),
                TextSpan(
                  text: _farewell,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: ' below.'),
              ],
            ),
          ),
        ],
      ),
      fields: const [AccountField('Confirmation', hint: _farewell)],
      submitLabel: 'Delete account',
      pendingLabel: 'Deleting…',
      destructive: true,
      ready: (values) => values.single == _farewell,
      // Signing out afterwards takes you back to the sign-in screen.
      onSubmit: (_) => actions.deleteAccount(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AccountScope.maybeOf(context);
    final actions = scope?.actions;
    return Scaffold(
      appBar: const AiqAppBar(title: 'Your account'),
      // Actions disappear the moment you sign out, just before this screen
      // closes.
      body: actions == null
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: actions,
              builder: (context, _) =>
                  _content(context, scope!.account, actions),
            ),
    );
  }

  Widget _content(
    BuildContext context,
    Account? account,
    AccountActions actions,
  ) {
    final theme = Theme.of(context);
    final idle = _pending == null;
    final emails = actions.emails;
    final connected = actions.connectedAccounts;
    // Verified addresses and connected accounts are the ways back in. A
    // password needs an address too, so it doesn't count on its own.
    final methods = emails.where((e) => e.isVerified).length + connected.length;
    final lastMethod = methods <= 1;
    final providers = {
      ...actions.providers,
      ...connected.map((a) => a.provider),
    };

    return ListView(
      padding: pagePadding,
      children: [
        const SectionLabel('Profile'),
        SectionCard(
          children: [
            _ProfileRow(account: account),
            SectionRow(
              icon: const Icon(Icons.alternate_email),
              title: 'Username',
              subtitle: actions.username ?? 'Not set yet',
              trailing: Icon(
                Icons.edit_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onTap: () => _editUsername(actions),
              enabled: idle,
            ),
          ],
        ),
        const SectionLabel('Sign-in methods'),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: Text(
            'The ways you can sign in, here and on the web.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_pending != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: LinearProgressIndicator(
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
              semanticsLabel: _pending,
            ),
          ),
        InlineError(_error),
        SectionCard(
          children: [
            for (final email in emails)
              _EmailRow(
                email: email,
                enabled: idle,
                // Removing an unverified address never locks you out.
                removeBlockedBy: email.isPrimary
                    ? 'Make another address primary first'
                    : email.isVerified && lastMethod
                    ? 'It’s your only way to sign in'
                    : null,
                onVerify: () => _resendCode(actions, email),
                onMakePrimary: () => _run(
                  'Updating your primary address',
                  () => actions.makePrimary(email.id),
                  done: '${email.address} is now your primary address',
                ),
                onRemove: () => _removeEmail(actions, email),
              ),
            SectionRow(
              icon: const Icon(Icons.add),
              title: 'Add an email address',
              onTap: () => _addEmail(actions),
              enabled: idle,
            ),
          ],
        ),
        if (providers.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionCard(
            children: [
              for (final provider in providers)
                _ProviderRow(
                  provider: provider,
                  account: connected
                      .where((a) => a.provider == provider)
                      .firstOrNull,
                  lastMethod: lastMethod,
                  enabled: idle,
                  onConnect: () => _connect(actions, provider),
                  onDisconnect: (account) => _disconnect(actions, account),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        SectionCard(
          children: [
            SectionRow(
              icon: const Icon(Icons.password),
              title: actions.passwordEnabled
                  ? 'Change password'
                  : 'Set a password',
              subtitle: actions.passwordEnabled ? null : 'You don’t have one',
              onTap: () => _setPassword(actions),
              enabled: idle,
            ),
            if (actions.passwordEnabled)
              SectionRow(
                icon: const Icon(Icons.no_encryption_outlined),
                title: 'Remove password',
                subtitle: methods == 0
                    ? 'It’s your only way to sign in'
                    : 'Sign in with your email or a connected account',
                onTap: () => _removePassword(actions),
                enabled: idle && methods > 0,
              ),
          ],
        ),
        SectionLabel('Danger zone', color: theme.colorScheme.error),
        SectionCard(
          children: [
            SectionRow(
              icon: const Icon(Icons.delete_outline),
              title: 'Delete account',
              subtitle: 'Removes your monitors, their data and your sign-in',
              destructive: true,
              onTap: () => _deleteAccount(actions),
              enabled: idle,
            ),
          ],
        ),
      ],
    );
  }
}

const _farewell = 'farewell';
const _fallbackError =
    'That didn’t go through. Check your connection and try again.';

/// Your photo, name and primary email at the top of the Profile card.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.account});

  final Account? account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = this.account;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          AccountAvatar(account: account, radius: 18),
          const SizedBox(width: 14),
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
                if (account?.email != null && account!.email != account.name)
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
    );
  }
}

enum _EmailAction { verify, makePrimary, remove }

/// One email address, its Primary or Unverified tag, and a menu of what you
/// can do with it.
class _EmailRow extends StatelessWidget {
  const _EmailRow({
    required this.email,
    required this.enabled,
    required this.removeBlockedBy,
    required this.onVerify,
    required this.onMakePrimary,
    required this.onRemove,
  });

  final AccountEmail email;
  final bool enabled;

  /// Why it can't be removed right now, or null when it can.
  final String? removeBlockedBy;
  final VoidCallback onVerify;
  final VoidCallback onMakePrimary;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SectionRow(
      icon: const Icon(Icons.mail_outline),
      title: email.address,
      enabled: enabled,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (email.isPrimary) const _Tag('Primary'),
          if (!email.isVerified) const _Tag('Unverified', muted: true),
          PopupMenuButton<_EmailAction>(
            tooltip: 'Options for ${email.address}',
            enabled: enabled,
            onSelected: (action) {
              switch (action) {
                case _EmailAction.verify:
                  onVerify();
                case _EmailAction.makePrimary:
                  onMakePrimary();
                case _EmailAction.remove:
                  onRemove();
              }
            },
            itemBuilder: (context) => [
              if (!email.isVerified)
                const PopupMenuItem(
                  value: _EmailAction.verify,
                  child: Text('Verify'),
                ),
              if (email.isVerified && !email.isPrimary)
                const PopupMenuItem(
                  value: _EmailAction.makePrimary,
                  child: Text('Make primary'),
                ),
              PopupMenuItem(
                value: _EmailAction.remove,
                enabled: removeBlockedBy == null,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Remove'),
                  subtitle: removeBlockedBy == null
                      ? null
                      : Text(removeBlockedBy!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Google or GitHub: connected (with the account it uses) or ready to connect.
class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.account,
    required this.lastMethod,
    required this.enabled,
    required this.onConnect,
    required this.onDisconnect,
  });

  final String provider;
  final ConnectedAccount? account;
  final bool lastMethod;
  final bool enabled;
  final VoidCallback onConnect;
  final ValueChanged<ConnectedAccount> onDisconnect;

  @override
  Widget build(BuildContext context) {
    final account = this.account;
    final label = providerLabel(provider);
    if (account == null) {
      return SectionRow(
        icon: const Icon(Icons.link_off),
        title: label,
        subtitle: 'Not connected',
        enabled: enabled,
        trailing: TextButton(
          onPressed: enabled ? onConnect : null,
          child: const Text('Connect'),
        ),
      );
    }
    return SectionRow(
      icon: const Icon(Icons.link),
      title: label,
      subtitle: lastMethod
          ? 'Your only way to sign in, so it stays connected'
          : account.identifier ?? 'Connected',
      enabled: enabled,
      trailing: TextButton(
        onPressed: enabled && !lastMethod ? () => onDisconnect(account) : null,
        child: const Text('Disconnect'),
      ),
    );
  }
}

/// A small rounded tag beside an email address.
class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: muted ? scheme.surfaceContainerHigh : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: muted ? scheme.onSurfaceVariant : scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// One text field in an [showActionDialog].
@immutable
class AccountField {
  const AccountField(
    this.label, {
    this.initial = '',
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
  });

  final String label;
  final String initial;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<String>? autofillHints;
}

/// A small form in a dialog: a few fields, a button that waits for
/// [onSubmit], and its error shown calmly inside the dialog. Resolves to true
/// once [onSubmit] succeeds.
Future<bool> showActionDialog(
  BuildContext context, {
  required String title,
  Widget? content,
  required List<AccountField> fields,
  required String submitLabel,
  required String pendingLabel,
  required Future<void> Function(List<String> values) onSubmit,
  bool Function(List<String> values)? ready,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _ActionDialog(
      title: title,
      content: content,
      fields: fields,
      submitLabel: submitLabel,
      pendingLabel: pendingLabel,
      onSubmit: onSubmit,
      ready: ready,
      destructive: destructive,
    ),
  );
  return result ?? false;
}

class _ActionDialog extends StatefulWidget {
  const _ActionDialog({
    required this.title,
    required this.content,
    required this.fields,
    required this.submitLabel,
    required this.pendingLabel,
    required this.onSubmit,
    required this.ready,
    required this.destructive,
  });

  final String title;
  final Widget? content;
  final List<AccountField> fields;
  final String submitLabel;
  final String pendingLabel;
  final Future<void> Function(List<String> values) onSubmit;
  final bool Function(List<String> values)? ready;
  final bool destructive;

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  late final _controllers = [
    for (final field in widget.fields)
      TextEditingController(text: field.initial),
  ];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> get _values => [for (final c in _controllers) c.text];

  bool get _ready =>
      widget.ready?.call(_values) ?? _values.every((v) => v.isNotEmpty);

  Future<void> _submit() async {
    if (_busy || !_ready) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_values);
      if (mounted) Navigator.of(context).pop(true);
      return;
    } on AccountActionException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = _fallbackError;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.content != null) ...[
                widget.content!,
                const SizedBox(height: 12),
              ],
              for (final (i, field) in widget.fields.indexed)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                  child: TextField(
                    controller: _controllers[i],
                    autofocus: i == 0,
                    enabled: !_busy,
                    obscureText: field.obscure,
                    keyboardType: field.keyboardType,
                    autofillHints: field.autofillHints,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: i == widget.fields.length - 1
                        ? TextInputAction.done
                        : TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: field.label,
                      hintText: field.hint,
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: i == widget.fields.length - 1
                        ? (_) => _submit()
                        : null,
                  ),
                ),
              InlineError(_error),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: widget.destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: !_busy && _ready ? _submit : null,
            child: Text(_busy ? widget.pendingLabel : widget.submitLabel),
          ),
        ],
      ),
    );
  }
}
