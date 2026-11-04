import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Build-time configuration, supplied with `--dart-define` (see README.md).
class AppConfig {
  AppConfig._();

  /// Backend base URL including `/api/v1`, without a trailing slash.
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.air-iq.net/api/v1',
  );

  /// Clerk publishable key of the same Clerk instance the web dashboard uses.
  static const clerkPublishableKey = String.fromEnvironment(
    'CLERK_PUBLISHABLE_KEY',
  );

  /// FlutterBluePlus 2.x requires declaring a license on connect. `nonprofit`
  /// covers personal, nonprofit and educational use; a for-profit organization
  /// must buy a commercial license and switch this to [License.commercial].
  static const bleLicense = License.nonprofit;
}
