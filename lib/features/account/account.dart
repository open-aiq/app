import 'package:flutter/material.dart';

/// The signed-in person, as shown in the profile menu and on Settings.
///
/// Built from the Clerk user in `main.dart`, so screens don't depend on Clerk.
@immutable
class Account {
  const Account({required this.name, this.email, this.imageUrl});

  final String name;
  final String? email;
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
