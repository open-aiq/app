import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Build-time configuration, supplied with `--dart-define` (see README.md).
class AppConfig {
  AppConfig._();

  /// Backend base URL including `/api/v1`, without a trailing slash.
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://api.air-iq.net/api/v1',
  );

  /// The Open AIQ docs, linked from the avatar menu.
  static const docsUrl = 'https://docs.air-iq.net';

  /// The web dashboard, whose public map is linked from the avatar menu.
  static const webUrl = 'https://open-airiq.web.app';

  /// Clerk publishable key of the same Clerk instance the web dashboard uses.
  static const clerkPublishableKey = String.fromEnvironment(
    'CLERK_PUBLISHABLE_KEY',
  );

  /// Shown on the Settings screen. `make release` keeps it in step with pubspec.yaml.
  static const appVersion = '0.4.2';

  /// FlutterBluePlus 2.x requires declaring a license on connect. `nonprofit`
  /// covers personal, nonprofit and educational use; a for-profit organization
  /// must buy a commercial license and switch this to [License.commercial].
  static const bleLicense = License.nonprofit;
}
