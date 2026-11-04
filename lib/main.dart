import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'ble/connection_manager.dart';
import 'config.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/devices/device_list_screen.dart';
import 'services.dart';

void main() {
  runApp(const OpenAiqApp());
}

class OpenAiqApp extends StatelessWidget {
  const OpenAiqApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorSchemeSeed: const Color(0xFF2E7D5B),
      useMaterial3: true,
    );
    if (AppConfig.clerkPublishableKey.isEmpty) {
      return MaterialApp(
        title: 'Open AIQ',
        theme: theme,
        home: const _MissingConfigScreen(),
      );
    }
    return ClerkAuth(
      config: ClerkAuthConfig(publishableKey: AppConfig.clerkPublishableKey),
      child: MaterialApp(
        title: 'Open AIQ',
        theme: theme,
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF2E7D5B),
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: ClerkErrorListener(
          child: ClerkAuthBuilder(
            signedInBuilder: (context, authState) =>
                _SignedIn(authState: authState),
            signedOutBuilder: (context, authState) => const SignInScreen(),
          ),
        ),
      ),
    );
  }
}

/// Creates the API client and BLE manager for the signed-in user.
class _SignedIn extends StatefulWidget {
  const _SignedIn({required this.authState});

  final ClerkAuthState authState;

  @override
  State<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends State<_SignedIn> {
  late final ApiClient _api = ApiClient(
    baseUrl: AppConfig.apiUrl,
    tokenProvider: () async => (await widget.authState.sessionToken()).jwt,
  );
  final BleConnectionManager _ble = BleConnectionManager();

  @override
  void dispose() {
    _ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppServices(
      api: _api,
      ble: _ble,
      child: DeviceListScreen(onSignOut: widget.authState.signOut),
    );
  }
}

class _MissingConfigScreen extends StatelessWidget {
  const _MissingConfigScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'CLERK_PUBLISHABLE_KEY is not set.\n\n'
              'Run with --dart-define=CLERK_PUBLISHABLE_KEY=pk_... '
              '(see app/README.md).',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
