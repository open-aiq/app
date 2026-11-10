import 'package:app/api/api_client.dart';
import 'package:app/features/account/account.dart';
import 'package:app/features/account/account_screen.dart';
import 'package:app/features/account/settings_screen.dart';
import 'package:app/gallery/mock_account_actions.dart';
import 'package:app/theme.dart';
import 'package:app/widgets/aiq_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _delay = Duration(milliseconds: 300);

/// [home] under a signed-in account, with [actions] when they're available.
Widget _app(Widget home, {AccountActions? actions}) {
  return MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: AccountScope(
      account: const Account(name: 'Riley Review', email: 'riley@example.com'),
      onSignOut: (_) async {},
      actions: actions,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
    ),
  );
}

/// The gallery's in-memory account, recording the backend requests it makes.
MockAccountActions _actions([List<String>? requests]) => MockAccountActions(
  delay: _delay,
  api: ApiClient(
    baseUrl: 'https://api.test/api/v1',
    tokenProvider: () async => 'jwt',
    httpClient: MockClient((request) async {
      requests?.add('${request.method} ${request.url.path}');
      return http.Response('', 204);
    }),
  ),
);

Finder _inDialog(Finder finder) =>
    find.descendant(of: find.byType(AlertDialog), matching: finder);

FilledButton _button(WidgetTester tester, String label) =>
    tester.widget(_inDialog(find.widgetWithText(FilledButton, label)));

void main() {
  testWidgets('deleting the account waits for exactly "farewell"', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final requests = <String>[];
    final actions = _actions(requests);
    addTearDown(actions.dispose);

    await tester.pumpWidget(_app(const AccountScreen(), actions: actions));
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    expect(_inDialog(find.text('Delete your account?')), findsOneWidget);
    expect(_button(tester, 'Delete account').onPressed, isNull);

    final field = _inDialog(find.byType(TextField));
    for (final attempt in ['Farewell', 'farewel', 'farewell ', 'FAREWELL']) {
      await tester.enterText(field, attempt);
      await tester.pump();
      expect(
        _button(tester, 'Delete account').onPressed,
        isNull,
        reason: '"$attempt" should not unlock delete',
      );
    }

    await tester.enterText(field, 'farewell');
    await tester.pump();
    expect(_button(tester, 'Delete account').onPressed, isNotNull);

    await tester.tap(
      _inDialog(find.widgetWithText(FilledButton, 'Delete account')),
    );
    await tester.pump();
    expect(_inDialog(find.text('Deleting…')), findsOneWidget);

    await tester.pump(_delay);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(requests, ['DELETE /api/v1/account']);
  });

  testWidgets('the username dialog explains a rejected name, then saves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final actions = _actions();
    addTearDown(actions.dispose);

    await tester.pumpWidget(_app(const AccountScreen(), actions: actions));
    expect(find.text('riley'), findsOneWidget);

    await tester.tap(find.text('Username'));
    await tester.pumpAndSettle();
    expect(_inDialog(find.text('Change your username')), findsOneWidget);
    // Nothing to save until the name changes.
    expect(_button(tester, 'Save').onPressed, isNull);

    final field = _inDialog(find.byType(TextField));
    await tester.enterText(field, 'ab');
    await tester.pump();
    await tester.tap(_inDialog(find.widgetWithText(FilledButton, 'Save')));
    await tester.pump(_delay);
    await tester.pumpAndSettle();
    expect(
      _inDialog(
        find.text('Use 4 to 64 letters, numbers, dashes or underscores.'),
      ),
      findsOneWidget,
    );

    await tester.enterText(field, 'riley_air');
    await tester.pump();
    await tester.tap(_inDialog(find.widgetWithText(FilledButton, 'Save')));
    await tester.pump(_delay);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(actions.username, 'riley_air');
    expect(find.text('riley_air'), findsOneWidget);
    expect(find.text('Username saved'), findsOneWidget);
  });

  testWidgets('your last way to sign in stays connected', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final actions = _OnlyGitHub();
    addTearDown(actions.dispose);

    await tester.pumpWidget(_app(const AccountScreen(), actions: actions));

    expect(
      find.text('Your only way to sign in, so it stays connected'),
      findsOneWidget,
    );
    final disconnect = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Disconnect'),
    );
    expect(disconnect.onPressed, isNull);
  });

  testWidgets('Settings offers Manage account only when it can work', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const SettingsScreen()));
    expect(find.text('Manage account'), findsNothing);

    final actions = _actions();
    addTearDown(actions.dispose);
    await tester.pumpWidget(_app(const SettingsScreen(), actions: actions));
    expect(find.text('Manage account'), findsOneWidget);

    await tester.tap(find.text('Manage account'));
    await tester.pumpAndSettle();
    expect(find.text('Your account'), findsOneWidget);
  });
}

/// Signed up with GitHub and nothing else.
class _OnlyGitHub extends MockAccountActions {
  _OnlyGitHub()
    : super(
        api: ApiClient(baseUrl: '', tokenProvider: _none),
      );

  static Future<String?> _none() async => null;

  @override
  List<AccountEmail> get emails => const [
    AccountEmail(id: 'email-1', address: 'riley@example.com', isPrimary: true),
  ];

  @override
  bool get passwordEnabled => false;
}
