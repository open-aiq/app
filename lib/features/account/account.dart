import 'package:flutter/material.dart';

/// The signed-in person, as shown in the profile menu and on Settings.
///
/// Built from the Clerk user in `main.dart`, so screens don't depend on Clerk.
@immutable
class Account {
  const Account({required this.name, this.email, this.username, this.imageUrl});

  final String name;
  final String? email;
  final String? username;
  final String? imageUrl;

  String get initials {
    final source = name.trim().isNotEmpty ? name : (email ?? '');
    final parts = source
        .split(RegExp(r'[\s@._-]+'))
        .where((p) => p.isNotEmpty)
        .take(2);
    final letters = parts.map((p) => p[0].toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }
}

/// One email address on the account.
@immutable
class AccountEmail {
  const AccountEmail({
    required this.id,
    required this.address,
    this.isPrimary = false,
    this.isVerified = false,
  });

  final String id;
  final String address;

  /// Where we send account emails. It can't be removed until another
  /// address takes its place.
  final bool isPrimary;
  final bool isVerified;
}

/// A Google or GitHub account you can sign in with.
@immutable
class ConnectedAccount {
  const ConnectedAccount({
    required this.id,
    required this.provider,
    this.identifier,
  });

  final String id;

  /// The OAuth provider key, such as `google` or `github`.
  final String provider;

  /// The email address or username on that account, when it has one.
  final String? identifier;

  String get label => providerLabel(provider);
}

/// The display name for an OAuth provider key.
String providerLabel(String provider) => switch (provider) {
  'google' => 'Google',
  'github' => 'GitHub',
  '' => 'Account',
  _ => provider[0].toUpperCase() + provider.substring(1),
};

/// A friendly message for an account change that didn't go through.
class AccountActionException implements Exception {
  const AccountActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Everything the account screen can read and change. The app implements it
/// over Clerk (`clerk_account_actions.dart`) and the gallery in memory, so
/// screens don't depend on Clerk.
///
/// Listeners hear about every change. Failed actions throw
/// [AccountActionException].
abstract class AccountActions extends ChangeNotifier {
  String? get username;
  List<AccountEmail> get emails;
  List<ConnectedAccount> get connectedAccounts;
  bool get passwordEnabled;

  /// OAuth providers you can connect, such as `google` and `github`.
  List<String> get providers;

  Future<void> updateUsername(String username);

  /// Adds an address and emails it a code. Returns the new address's id.
  Future<String> addEmail(String address);
  Future<void> verifyEmail(String id, String code);
  Future<void> removeEmail(String id);
  Future<void> makePrimary(String id);

  /// Signs in to [provider] (a key from [providers]) and links it.
  Future<void> connect(BuildContext context, String provider);
  Future<void> disconnect(String id);

  /// Sets a password, or changes it when [current] is given.
  Future<void> setPassword({String? current, required String next});
  Future<void> removePassword(String current);

  /// Deletes every monitor and its data, then the account, and signs out.
  Future<void> deleteAccount();
}

/// App-wide appearance preference. It lasts for the session; storing it on
/// disk would need a new dependency, so that's left for later.
final themeModePreference = ValueNotifier<ThemeMode>(ThemeMode.system);

/// A round avatar with the profile photo, or initials when there isn't one.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.account, this.radius = 16});

  final Account? account;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = account?.imageUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      foregroundImage: url == null || url.isEmpty ? null : NetworkImage(url),
      child: account == null
          ? Icon(Icons.person_outline, size: radius)
          : Text(account!.initials, style: TextStyle(fontSize: radius * 0.8)),
    );
  }
}
