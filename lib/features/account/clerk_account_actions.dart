import 'dart:async';

import 'package:clerk_auth/clerk_auth.dart' as clerk;
import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/widgets.dart';

import '../../api/api_client.dart';
import 'account.dart';

/// [AccountActions] for the signed-in Clerk user, plus our backend for
/// deleting the account. Built in `main.dart`.
///
/// While the app's `ClerkErrorListener` is listening, Clerk reports failures
/// on its error stream instead of throwing. Each call listens to that stream
/// and turns what it hears into an [AccountActionException], so the account
/// screen knows the change didn't go through.
class ClerkAccountActions extends AccountActions {
  ClerkAccountActions({required this.auth, required this.api}) {
    auth.addListener(notifyListeners);
  }

  final ClerkAuthState auth;
  final ApiClient api;

  /// The providers the account screen knows how to show.
  static const _supported = ['google', 'github'];

  clerk.User? get _user => auth.user;

  @override
  void dispose() {
    auth.removeListener(notifyListeners);
    super.dispose();
  }

  @override
  String? get username => _user?.username;

  @override
  List<AccountEmail> get emails {
    final user = _user;
    return [
      for (final email in user?.emailAddresses ?? const <clerk.Email>[])
        AccountEmail(
          id: email.id,
          address: email.emailAddress,
          isPrimary: email.id == user?.primaryEmailAddressId,
          isVerified: email.isVerified,
        ),
    ];
  }

  @override
  List<ConnectedAccount> get connectedAccounts => [
    for (final account
        in _user?.externalAccounts ?? const <clerk.ExternalAccount>[])
      // An unverified one is a connection that was started but not finished.
      if (account.isVerified)
        ConnectedAccount(
          id: account.id,
          provider:
              account.verification.strategy.provider ??
              account.provider.replaceFirst('oauth_', ''),
          identifier: account.emailAddress.isNotEmpty
              ? account.emailAddress
              : account.username,
        ),
  ];

  @override
  bool get passwordEnabled => _user?.passwordEnabled ?? false;

  @override
  List<String> get providers => [
    for (final connection in auth.env.socialConnections)
      if (connection.strategy.provider case final provider?
          when _supported.contains(provider))
        provider,
  ];

  @override
  Future<void> updateUsername(String username) async {
    // Clerk quietly skips the change when usernames are off for the instance.
    if (!auth.env.config.allowsUsername) {
      throw const AccountActionException(
        'Usernames aren’t turned on for Open AIQ yet.',
      );
    }
    await _call(() => auth.updateUser(username: username));
  }

  @override
  Future<String> addEmail(String address) async {
    final email = address.trim().toLowerCase();
    final existing = _user?.identifierFrom(email);
    if (existing != null && existing.isUnverified) {
      // Already added but never verified: send a fresh code instead.
      await _call(
        () => auth.fetchApiResponse(
          '/me/${existing.type.urlSegment}/${existing.id}/prepare_verification',
          params: {'strategy': existing.type.verificationStrategy},
          withSession: true,
        ),
      );
      return existing.id;
    }
    await _call(
      () => auth.addIdentifyingData(email, clerk.IdentifierType.emailAddress),
    );
    final added = _user?.identifierFrom(email);
    if (added == null) {
      throw const AccountActionException(
        'We couldn’t add that address. Check it and try again.',
      );
    }
    return added.id;
  }

  @override
  Future<void> verifyEmail(String id, String code) =>
      _call(() => auth.verifyIdentifyingData(_email(id), code.trim()));

  @override
  Future<void> removeEmail(String id) =>
      _call(() => auth.deleteIdentifyingData(_email(id)));

  @override
  Future<void> makePrimary(String id) =>
      _call(() => auth.updateUser(primaryEmailAddressId: id));

  @override
  Future<void> connect(BuildContext context, String provider) async {
    final strategy = clerk.Strategy.named('oauth_$provider');
    if (strategy == null || !strategy.isOauth) {
      throw AccountActionException(
        'We can’t connect ${providerLabel(provider)} yet.',
      );
    }
    // ssoConnect opens the provider in an in-app browser and links the
    // account when you come back.
    await _call(() => auth.ssoConnect(context, strategy));
  }

  @override
  Future<void> disconnect(String id) async {
    final account = _user?.externalAccounts?.where((a) => a.id == id);
    if (account == null || account.isEmpty) {
      throw const AccountActionException('That account is already gone.');
    }
    await _call(() => auth.deleteExternalAccount(account: account.first));
  }

  @override
  Future<void> setPassword({String? current, required String next}) =>
      _call(() async {
        if (current == null || current.isEmpty) {
          // Clerk only asks for the current password once there is one, and
          // updateUserPassword always sends it, so set the first one directly.
          await auth.fetchApiResponse(
            '/me/change_password',
            params: {'new_password': next, 'sign_out_of_other_sessions': true},
            withSession: true,
          );
          await auth.refreshClient();
        } else {
          await auth.updateUserPassword(current, next);
        }
      });

  @override
  Future<void> removePassword(String current) =>
      _call(() => auth.deleteUserPassword(current));

  @override
  Future<void> deleteAccount() async {
    try {
      await api.deleteAccount();
    } on ApiException catch (e) {
      throw AccountActionException(e.message);
    } catch (_) {
      throw const AccountActionException(
        'We couldn’t reach Open AIQ. Check your connection and try again.',
      );
    }
    // The backend has already removed the Clerk user, so this clears the
    // session on this phone. If Clerk can't be reached, a refresh notices
    // the session is gone.
    try {
      await auth.signOut();
    } catch (_) {
      await auth.refreshClient().catchError((_) {});
    }
  }

  clerk.UserIdentifyingData _email(String id) {
    final email = _user?.emailAddresses?.where((e) => e.id == id);
    if (email == null || email.isEmpty) {
      throw const AccountActionException('That address is already gone.');
    }
    return email.first;
  }

  /// Runs a Clerk call and throws [AccountActionException] if it failed,
  /// whether Clerk threw or only reported it on the error stream.
  Future<T> _call<T>(Future<T> Function() fn) async {
    clerk.ClerkError? reported;
    final errors = auth.errorStream.listen((error) => reported ??= error);
    try {
      final result = await fn();
      // The error stream delivers asynchronously; let it catch up.
      await Future<void>.delayed(Duration.zero);
      if (reported case final error?) {
        throw AccountActionException(_message(error));
      }
      return result;
    } on clerk.ClerkError catch (error) {
      throw AccountActionException(_message(error));
    } finally {
      await errors.cancel();
    }
  }

  static String _message(clerk.ClerkError error) {
    final text = switch (error.code) {
      clerk.ClerkErrorCode.serverErrorResponse => error.argument,
      clerk.ClerkErrorCode.externalError => null,
      _ => error.toString(),
    };
    return text == null || text.isEmpty
        ? 'That didn’t go through. Check your connection and try again.'
        : text;
  }
}
