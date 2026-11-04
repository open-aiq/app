import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

/// Sign in with the same Clerk account used on the web dashboard.
class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Icon(
              Icons.air,
              size: 56,
              color: theme.colorScheme.primary,
              semanticLabel: 'Open AIQ',
            ),
            const SizedBox(height: 12),
            Text(
              'Open AIQ',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in with your Open AIQ dashboard account to set up and manage your air monitors.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            const ClerkAuthentication(),
          ],
        ),
      ),
    );
  }
}
