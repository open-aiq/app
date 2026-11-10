import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../features/account/account.dart';

/// An in-memory account for the gallery and the hosted prototype: Riley, with
/// two email addresses, GitHub connected and a password. Every change works
/// and lasts until the page reloads. Nothing leaves the browser.
class MockAccountActions extends AccountActions {
  MockAccountActions({
    required this.api,
    this.messenger,
    this.delay = const Duration(milliseconds: 300),
  });

  /// The mock backend, for `DELETE /account`.
  final ApiClient api;

  /// Shows notes about what the prototype does differently.
  final GlobalKey<ScaffoldMessengerState>? messenger;

  /// How long each change takes, so pending states show.
  final Duration delay;

  String? _username = 'riley';
  final List<AccountEmail> _emails = [
    const AccountEmail(
      id: 'email-1',
      address: 'riley@example.com',
      isPrimary: true,
      isVerified: true,
    ),
    const AccountEmail(
      id: 'email-2',
      address: 'riley.home@example.com',
      isVerified: true,
    ),
  ];
  final List<ConnectedAccount> _connected = [
    const ConnectedAccount(
      id: 'ext-github',
      provider: 'github',
      identifier: 'riley@example.com',
    ),
  ];
  bool _password = true;
  int _nextId = 3;

  static final _usernamePattern = RegExp(r'^[a-zA-Z0-9_-]{4,64}$');

  @override
  String? get username => _username;

  @override
  List<AccountEmail> get emails => List.unmodifiable(_emails);

  @override
  List<ConnectedAccount> get connectedAccounts => List.unmodifiable(_connected);

  @override
  bool get passwordEnabled => _password;

  @override
  List<String> get providers => const ['google', 'github'];

  Future<void> _change(void Function() change) async {
    await Future<void>.delayed(delay);
    change();
    notifyListeners();
  }

  void _note(String message) =>
      messenger?.currentState?.showSnackBar(SnackBar(content: Text(message)));

  int _indexOf(String id) {
    final index = _emails.indexWhere((e) => e.id == id);
    if (index < 0) {
      throw const AccountActionException('That address is already gone.');
    }
    return index;
  }

  @override
  Future<void> updateUsername(String username) => _change(() {
    if (!_usernamePattern.hasMatch(username)) {
      throw const AccountActionException(
        'Use 4 to 64 letters, numbers, dashes or underscores.',
      );
    }
    _username = username;
  });

  @override
  Future<String> addEmail(String address) async {
    final email = address.trim().toLowerCase();
    late String id;
    await _change(() {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
        throw const AccountActionException(
          'That doesn’t look like an email address.',
        );
      }
      final existing = _emails.where((e) => e.address == email).firstOrNull;
      if (existing != null && existing.isVerified) {
        throw const AccountActionException(
          'That address is already on your account.',
        );
      }
      id = existing?.id ?? 'email-${_nextId++}';
      if (existing == null) _emails.add(AccountEmail(id: id, address: email));
    });
    _note('In the prototype, any 6 digits work as the code.');
    return id;
  }

  @override
  Future<void> verifyEmail(String id, String code) => _change(() {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const AccountActionException(
        'Enter the 6-digit code from the email.',
      );
    }
    final i = _indexOf(id);
    final email = _emails[i];
    _emails[i] = AccountEmail(
      id: email.id,
      address: email.address,
      isPrimary: email.isPrimary,
      isVerified: true,
    );
  });

  @override
  Future<void> removeEmail(String id) => _change(() {
    if (_emails[_indexOf(id)].isPrimary) {
      throw const AccountActionException('Make another address primary first.');
    }
    _emails.removeWhere((e) => e.id == id);
  });

  @override
  Future<void> makePrimary(String id) => _change(() {
    _indexOf(id);
    for (final (i, email) in _emails.indexed) {
      _emails[i] = AccountEmail(
        id: email.id,
        address: email.address,
        isPrimary: email.id == id,
        isVerified: email.isVerified,
      );
    }
  });

  @override
  Future<void> connect(BuildContext context, String provider) => _change(() {
    if (_connected.any((a) => a.provider == provider)) return;
    _connected.add(
      ConnectedAccount(
        id: 'ext-$provider',
        provider: provider,
        identifier: _emails.firstWhere((e) => e.isPrimary).address,
      ),
    );
  });

  @override
  Future<void> disconnect(String id) =>
      _change(() => _connected.removeWhere((a) => a.id == id));

  @override
  Future<void> setPassword({String? current, required String next}) =>
      _change(() {
        if (_password && (current == null || current.isEmpty)) {
          throw const AccountActionException('Enter your current password.');
        }
        if (next.length < 8) {
          throw const AccountActionException(
            'Use at least 8 characters for your new password.',
          );
        }
        _password = true;
      });

  @override
  Future<void> removePassword(String current) => _change(() {
    if (current.isEmpty) {
      throw const AccountActionException('Enter your current password.');
    }
    _password = false;
  });

  @override
  Future<void> deleteAccount() async {
    try {
      await api.deleteAccount();
    } on ApiException catch (e) {
      throw AccountActionException(e.message);
    }
    _note('The prototype keeps your account, so you can keep exploring.');
  }
}
