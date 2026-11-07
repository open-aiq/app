import 'package:clerk_auth/clerk_auth.dart' as clerk;
import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'ble/connection_manager.dart';
import 'config.dart';
import 'features/account/account.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/devices/device_list_screen.dart';
import 'services.dart';

void main() {
  runApp(const OpenAiqApp());
}

final _navigatorKey = GlobalKey<NavigatorState>();

class OpenAiqApp extends StatelessWidget {
  const OpenAiqApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = _buildTheme(Brightness.light);
    if (AppConfig.clerkPublishableKey.isEmpty) {
      return MaterialApp(
        title: 'Open AIQ',
        theme: theme,
        home: const _MissingConfigScreen(),
      );
    }
    return ClerkAuth(
      config: ClerkAuthConfig(publishableKey: AppConfig.clerkPublishableKey),
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModePreference,
        builder: (context, themeMode, _) =>
            _buildApp(context, theme, themeMode),
      ),
    );
  }

  Widget _buildApp(BuildContext context, ThemeData theme, ThemeMode themeMode) {
    return MaterialApp(
      title: 'Open AIQ',
      theme: theme,
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: themeMode,
      // Cross-fade between light and dark only when motion is welcome.
      themeAnimationDuration:
          MediaQueryData.fromView(View.of(context)).disableAnimations
          ? Duration.zero
          : kThemeAnimationDuration,
      navigatorKey: _navigatorKey,
      // AppServices must wrap the Navigator, not `home`: pushed routes are
      // siblings of `home` and could not otherwise look it up.
      builder: (context, child) => _DismissKeyboardOnTap(
        child: ClerkAuthBuilder(
          signedInBuilder: (context, authState) =>
              _SignedIn(authState: authState, child: child!),
          signedOutBuilder: (context, authState) => child!,
        ),
      ),
      home: ClerkErrorListener(
        child: ClerkAuthBuilder(
          signedInBuilder: (context, authState) => DeviceListScreen(
            onSignOut: authState.signOut,
            account: _account(authState.user),
          ),
          signedOutBuilder: (context, authState) => const SignInScreen(),
        ),
      ),
    );
  }
}

Account? _account(clerk.User? user) {
  if (user == null) return null;
  final name = user.name.trim();
  return Account(
    name: name.isNotEmpty ? name : (user.email ?? 'Your account'),
    email: user.email,
    imageUrl: user.hasImage == true ? user.imageUrl : null,
  );
}

ThemeData _buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2E7D5B),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    extensions: [
      // Match Clerk's sign-in widgets to the app instead of Clerk's default
      // black/purple palette. `background` equals the page colour and
      // `altBackground` (Clerk's card shadow) does too, so the card blends into
      // the page. Clerk paints primary button text in `background`, so it must
      // contrast with `accent`.
      ClerkThemeExtension(
        colors: ClerkThemeColors(
          background: scheme.surface,
          altBackground: scheme.surface,
          borderSide: scheme.outlineVariant,
          text: scheme.onSurface,
          icon: scheme.onSurfaceVariant,
          lightweightText: scheme.onSurfaceVariant,
          error: scheme.error,
          accent: scheme.primary,
        ),
      ),
    ],
  );
}

/// Closes the keyboard when the user taps outside a text field. iOS has no
/// system gesture for this, so without it the keyboard can only be closed from
/// a field's submit action.
class _DismissKeyboardOnTap extends StatelessWidget {
  const _DismissKeyboardOnTap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}

/// Creates the API client and BLE manager for the signed-in user and provides
/// them to every route.
class _SignedIn extends StatefulWidget {
  const _SignedIn({required this.authState, required this.child});

  final ClerkAuthState authState;
  final Widget child;

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
    // Signed out (or the session ended) while a pushed route may be open; those
    // routes need AppServices, so return to the sign-in screen.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _navigatorKey.currentState?.popUntil((route) => route.isFirst),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppServices(api: _api, ble: _ble, child: widget.child);
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
