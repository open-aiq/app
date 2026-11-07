import 'package:clerk_auth/clerk_auth.dart' as clerk;
import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

/// Sign in or sign up with the same Clerk account used on the web dashboard.
///
/// Clerk's prebuilt `ClerkAuthentication` widget has fixed sizes and ordering,
/// so this screen drives `ClerkAuthState` directly. It covers what the Clerk
/// instances enable: email + password, email codes, Google/GitHub, sign-up with
/// email verification, password reset, and optional second factors / new-device
/// verification. Errors surface through the app's `ClerkErrorListener`.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

enum _Mode { signIn, signUp, resetPassword }

/// Height shared by text fields and the primary button.
const double _controlHeight = 48;
const double _gap = 16;

/// Very large accessibility text sizes overflow the fixed control heights.
/// Text still scales, up to this factor.
const double _maxTextScale = 1.3;

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();

  _Mode _mode = _Mode.signIn;

  /// The factor the user is currently completing during sign-in.
  clerk.Strategy _strategy = clerk.Strategy.password;
  bool _resetCodeSent = false;
  bool _obscurePassword = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions

  Future<void> _run(ClerkAuthState auth, Future<void> Function() fn) async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    try {
      await auth.safelyCall(context, fn);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _oauth(ClerkAuthState auth, clerk.Strategy strategy) async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    try {
      // ssoSignIn handles its own errors and the in-app browser.
      await auth.ssoSignIn(context, strategy);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitEmail(ClerkAuthState auth) {
    final email = _email.text.trim();
    if (email.isEmpty) return Future.value();
    return _run(auth, () async {
      await auth.attemptSignIn(
        strategy: clerk.Strategy.password,
        identifier: email,
      );
      final signIn = auth.signIn;
      if (signIn != null && signIn.needsFirstFactor) {
        final strategy = signIn.canUsePassword
            ? clerk.Strategy.password
            : _preferred(signIn.factorsFor(clerk.Stage.first), const [
                clerk.Strategy.emailCode,
              ]);
        await _switchTo(auth, strategy);
      }
    });
  }

  Future<void> _submitPassword(ClerkAuthState auth) {
    if (_password.text.isEmpty) return Future.value();
    return _run(auth, () async {
      await auth.attemptSignIn(
        strategy: clerk.Strategy.password,
        password: _password.text,
      );
      await _prepareSecondStage(auth);
    });
  }

  Future<void> _submitCode(ClerkAuthState auth) {
    final code = _code.text.trim();
    if (!_strategy.mightAccept(code)) return Future.value();
    return _run(auth, () async {
      await auth.attemptSignIn(strategy: _strategy, code: code);
      _code.clear();
      await _prepareSecondStage(auth);
    });
  }

  /// After a first factor, Clerk may ask for a second factor or to verify a new
  /// device. Pick the most convenient factor and send its code if needed.
  Future<void> _prepareSecondStage(ClerkAuthState auth) async {
    final signIn = auth.signIn;
    if (signIn == null) return;
    if (signIn.needsSecondFactor || signIn.needsClientTrust) {
      final strategy = _preferred(signIn.factorsFor(clerk.Stage.second), const [
        clerk.Strategy.totp,
        clerk.Strategy.emailCode,
        clerk.Strategy.phoneCode,
        clerk.Strategy.backupCode,
      ]);
      await _switchTo(auth, strategy);
    }
  }

  /// Make [strategy] the active factor, sending a code when it needs one.
  Future<void> _switchTo(ClerkAuthState auth, clerk.Strategy strategy) async {
    _code.clear();
    setState(() => _strategy = strategy);
    var signIn = auth.signIn;
    if (signIn == null || !strategy.requiresPreparation) return;

    // Clerk only prepares a factor when no verification is in progress. If the
    // user already tried another first factor (e.g. a wrong password), start a
    // fresh sign-in for the same email so the code is actually sent.
    if (signIn.needsFirstFactor &&
        signIn.verification != null &&
        signIn.verification!.strategy != strategy) {
      final identifier = signIn.identifier ?? _email.text.trim();
      await auth.resetClient();
      await auth.attemptSignIn(
        strategy: clerk.Strategy.password,
        identifier: identifier,
      );
      signIn = auth.signIn;
    }
    if (signIn != null && signIn.requiresPreparationFor(strategy)) {
      await auth.attemptSignIn(strategy: strategy);
    }
  }

  Future<void> _resendCode(ClerkAuthState auth) => _run(auth, () async {
    await auth.resendCode(_strategy);
  });

  Future<void> _startOver(ClerkAuthState auth, {_Mode? mode}) =>
      _run(auth, () async {
        _password.clear();
        _code.clear();
        _strategy = clerk.Strategy.password;
        _resetCodeSent = false;
        _mode = mode ?? _Mode.signIn;
        if (auth.signIn != null || auth.signUp != null) {
          await auth.resetClient();
        }
      });

  Future<void> _submitSignUp(ClerkAuthState auth) {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) return Future.value();
    return _run(auth, () async {
      await auth.attemptSignUp(
        strategy: clerk.Strategy.password,
        emailAddress: email,
        password: password,
        passwordConfirmation: password,
      );
      final signUp = auth.signUp;
      if (signUp == null) return; // Signed in already.
      if (signUp.unverified(clerk.Field.emailAddress)) {
        // Sends the verification email.
        await auth.attemptSignUp(strategy: clerk.Strategy.emailCode);
      } else if (signUp.missingFields.isNotEmpty) {
        auth.handleError(
          clerk.ClerkError.clientAppError(
            message:
                'Your account needs more details. Finish signing up on the '
                'web dashboard.',
          ),
        );
      }
    });
  }

  Future<void> _submitSignUpCode(ClerkAuthState auth) {
    final code = _code.text.trim();
    if (!clerk.Strategy.emailCode.mightAccept(code)) return Future.value();
    return _run(auth, () async {
      await auth.attemptSignUp(strategy: clerk.Strategy.emailCode, code: code);
    });
  }

  Future<void> _sendResetCode(ClerkAuthState auth) {
    final email = _email.text.trim();
    if (email.isEmpty) return Future.value();
    return _run(auth, () async {
      await auth.initiatePasswordReset(
        identifier: email,
        strategy: clerk.Strategy.resetPasswordEmailCode,
      );
      if (auth.signIn?.needsFirstFactor == true) {
        _code.clear();
        _password.clear();
        setState(() => _resetCodeSent = true);
      }
    });
  }

  Future<void> _submitReset(ClerkAuthState auth) {
    final code = _code.text.trim();
    if (_password.text.isEmpty ||
        !clerk.Strategy.resetPasswordEmailCode.mightAccept(code)) {
      return Future.value();
    }
    return _run(auth, () async {
      await auth.attemptSignIn(
        strategy: clerk.Strategy.resetPasswordEmailCode,
        identifier: _email.text.trim(),
        password: _password.text,
        code: code,
      );
      if (auth.isSignedIn) return;
      if (auth.signIn case final signIn?
          when signIn.needsSecondFactor || signIn.needsClientTrust) {
        _password.clear();
        setState(() => _mode = _Mode.signIn);
        await _prepareSecondStage(auth);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Build

  @override
  Widget build(BuildContext context) {
    final auth = ClerkAuth.of(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _maxTextScale,
      child: Scaffold(
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: auth.isNotAvailable
                  ? const Center(child: CircularProgressIndicator())
                  : AutofillGroup(
                      child: ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Icon(
                              Icons.air,
                              size: 40,
                              color: Theme.of(context).colorScheme.primary,
                              semanticLabel: 'Open AIQ',
                            ),
                          ),
                          const SizedBox(height: 24),
                          ..._buildStep(context, auth),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStep(BuildContext context, ClerkAuthState auth) {
    switch (_mode) {
      case _Mode.resetPassword:
        return _resetStep(context, auth);
      case _Mode.signUp:
        final signUp = auth.signUp;
        if (signUp != null && signUp.unverified(clerk.Field.emailAddress)) {
          return _signUpCodeStep(context, auth);
        }
        return _signUpStep(context, auth);
      case _Mode.signIn:
        final signIn = auth.signIn;
        if (signIn == null || signIn.status.isUnknown) {
          return _emailStep(context, auth);
        }
        if (signIn.needsFirstFactor) return _firstFactorStep(context, auth);
        if (signIn.needsSecondFactor || signIn.needsClientTrust) {
          return _secondFactorStep(context, auth, signIn);
        }
        return const [Center(child: CircularProgressIndicator())];
    }
  }

  List<Widget> _emailStep(BuildContext context, ClerkAuthState auth) => [
    const _Title('Sign in'),
    _AuthField(
      controller: _email,
      hint: 'Email address',
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email, AutofillHints.username],
      onSubmitted: (_) => _submitEmail(auth),
    ),
    const SizedBox(height: _gap),
    _PrimaryButton(
      label: 'Continue',
      busy: _busy,
      onPressed: () => _submitEmail(auth),
    ),
    ..._socialSection(auth),
    const SizedBox(height: 32),
    _SwitchLink(
      prompt: "Don't have an account?",
      action: 'Sign up',
      onTap: _busy ? null : () => _startOver(auth, mode: _Mode.signUp),
    ),
  ];

  List<Widget> _firstFactorStep(BuildContext context, ClerkAuthState auth) {
    final signIn = auth.signIn!;
    final identifier = signIn.identifier ?? _email.text.trim();
    final hasEmailCode =
        signIn.factorFor(clerk.Strategy.emailCode, stage: clerk.Stage.first) !=
        null;
    final canReset = auth.env.config.firstFactors.any(
      (s) => s.isPasswordResetter && !s.isPhone,
    );

    return [
      const _Title('Sign in'),
      _IdentifierChip(
        identifier: identifier,
        onChange: _busy ? null : () => _startOver(auth),
      ),
      const SizedBox(height: _gap),
      if (_strategy.isPassword) ...[
        _AuthField(
          controller: _password,
          hint: 'Password',
          obscureText: _obscurePassword,
          autofocus: true,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _submitPassword(auth),
          suffix: _ObscureToggle(
            obscured: _obscurePassword,
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: _gap),
        _PrimaryButton(
          label: 'Continue',
          busy: _busy,
          onPressed: () => _submitPassword(auth),
        ),
        const SizedBox(height: 8),
        if (canReset)
          _TextLink(
            'Forgot password?',
            onTap: _busy
                ? null
                : () => setState(() {
                    _mode = _Mode.resetPassword;
                    _resetCodeSent = false;
                    _email.text = identifier;
                  }),
          ),
        if (hasEmailCode)
          _TextLink(
            'Email me a sign-in code instead',
            onTap: _busy
                ? null
                : () => _run(
                    auth,
                    () => _switchTo(auth, clerk.Strategy.emailCode),
                  ),
          ),
      ] else ...[
        ..._codeEntry(
          auth,
          message: _codeMessage(signIn, _strategy),
          onSubmit: () => _submitCode(auth),
        ),
        if (signIn.canUsePassword)
          _TextLink(
            'Use password instead',
            onTap: _busy
                ? null
                : () => setState(() => _strategy = clerk.Strategy.password),
          ),
      ],
    ];
  }

  List<Widget> _secondFactorStep(
    BuildContext context,
    ClerkAuthState auth,
    clerk.SignIn signIn,
  ) {
    final others = signIn
        .factorsFor(clerk.Stage.second)
        .map((f) => f.strategy)
        .where((s) => s != _strategy && _factorLabel(s) != null)
        .toSet();
    return [
      _Title(
        signIn.needsClientTrust
            ? 'Verify this device'
            : 'Two-step verification',
      ),
      ..._codeEntry(
        auth,
        message: _codeMessage(signIn, _strategy),
        onSubmit: () => _submitCode(auth),
      ),
      for (final strategy in others)
        _TextLink(
          _factorLabel(strategy)!,
          onTap: _busy
              ? null
              : () => _run(auth, () => _switchTo(auth, strategy)),
        ),
      _TextLink('Start over', onTap: _busy ? null : () => _startOver(auth)),
    ];
  }

  /// Code field, Verify button and (for sent codes) a resend link.
  List<Widget> _codeEntry(
    ClerkAuthState auth, {
    required String message,
    required VoidCallback onSubmit,
    bool canResend = true,
  }) {
    final sentCode =
        _strategy == clerk.Strategy.emailCode ||
        _strategy == clerk.Strategy.phoneCode;
    return [
      _Message(message),
      const SizedBox(height: _gap),
      _AuthField(
        controller: _code,
        hint: _strategy == clerk.Strategy.backupCode ? 'Backup code' : 'Code',
        autofocus: true,
        keyboardType: _strategy == clerk.Strategy.backupCode
            ? TextInputType.text
            : TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        onSubmitted: (_) => onSubmit(),
      ),
      const SizedBox(height: _gap),
      _PrimaryButton(label: 'Verify', busy: _busy, onPressed: onSubmit),
      const SizedBox(height: 8),
      if (sentCode && canResend)
        _TextLink('Resend code', onTap: _busy ? null : () => _resendCode(auth)),
    ];
  }

  List<Widget> _signUpStep(BuildContext context, ClerkAuthState auth) => [
    const _Title('Create account'),
    _AuthField(
      controller: _email,
      hint: 'Email address',
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      textInputAction: TextInputAction.next,
    ),
    const SizedBox(height: _gap),
    _AuthField(
      controller: _password,
      hint: 'Password',
      obscureText: _obscurePassword,
      autofillHints: const [AutofillHints.newPassword],
      onSubmitted: (_) => _submitSignUp(auth),
      suffix: _ObscureToggle(
        obscured: _obscurePassword,
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
      ),
    ),
    const SizedBox(height: _gap),
    _PrimaryButton(
      label: 'Continue',
      busy: _busy,
      onPressed: () => _submitSignUp(auth),
    ),
    ..._socialSection(auth),
    const SizedBox(height: 32),
    _SwitchLink(
      prompt: 'Already have an account?',
      action: 'Sign in',
      onTap: _busy ? null : () => _startOver(auth),
    ),
  ];

  List<Widget> _signUpCodeStep(BuildContext context, ClerkAuthState auth) {
    final email = auth.signUp?.emailAddress ?? _email.text.trim();
    return [
      const _Title('Verify your email'),
      _Message('Enter the 6-digit code sent to $email.'),
      const SizedBox(height: _gap),
      _AuthField(
        controller: _code,
        hint: 'Code',
        autofocus: true,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        onSubmitted: (_) => _submitSignUpCode(auth),
      ),
      const SizedBox(height: _gap),
      _PrimaryButton(
        label: 'Verify',
        busy: _busy,
        onPressed: () => _submitSignUpCode(auth),
      ),
      const SizedBox(height: 8),
      _TextLink(
        'Resend code',
        onTap: _busy
            ? null
            : () => _run(auth, () async {
                await auth.resendCode(clerk.Strategy.emailCode);
              }),
      ),
      _TextLink(
        'Start over',
        onTap: _busy ? null : () => _startOver(auth, mode: _Mode.signUp),
      ),
    ];
  }

  List<Widget> _resetStep(BuildContext context, ClerkAuthState auth) {
    if (!_resetCodeSent) {
      return [
        const _Title('Reset password'),
        const _Message("We'll email you a code to set a new password."),
        const SizedBox(height: _gap),
        _AuthField(
          controller: _email,
          hint: 'Email address',
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          onSubmitted: (_) => _sendResetCode(auth),
        ),
        const SizedBox(height: _gap),
        _PrimaryButton(
          label: 'Send code',
          busy: _busy,
          onPressed: () => _sendResetCode(auth),
        ),
        const SizedBox(height: 8),
        _TextLink(
          'Back to sign in',
          onTap: _busy ? null : () => _startOver(auth),
        ),
      ];
    }
    return [
      const _Title('Reset password'),
      _Message('Enter the code sent to ${_email.text.trim()}.'),
      const SizedBox(height: _gap),
      _AuthField(
        controller: _code,
        hint: 'Code',
        autofocus: true,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: _gap),
      _AuthField(
        controller: _password,
        hint: 'New password',
        obscureText: _obscurePassword,
        autofillHints: const [AutofillHints.newPassword],
        onSubmitted: (_) => _submitReset(auth),
        suffix: _ObscureToggle(
          obscured: _obscurePassword,
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      const SizedBox(height: _gap),
      _PrimaryButton(
        label: 'Reset password',
        busy: _busy,
        onPressed: () => _submitReset(auth),
      ),
      const SizedBox(height: 8),
      _TextLink(
        'Resend code',
        onTap: _busy ? null : () => _sendResetCode(auth),
      ),
      _TextLink(
        'Back to sign in',
        onTap: _busy ? null : () => _startOver(auth),
      ),
    ];
  }

  List<Widget> _socialSection(ClerkAuthState auth) {
    final connections = auth.env.socialConnections;
    if (connections.isEmpty) return const [];
    return [
      const SizedBox(height: 24),
      const _OrDivider(),
      const SizedBox(height: 24),
      Row(
        children: [
          for (final (i, connection) in connections.indexed) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: _SocialButton(
                connection: connection,
                onPressed: _busy
                    ? null
                    : () => _oauth(auth, connection.strategy),
              ),
            ),
          ],
        ],
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Helpers

  static clerk.Strategy _preferred(
    List<clerk.Factor> factors,
    List<clerk.Strategy> order,
  ) {
    final available = factors.map((f) => f.strategy).toSet();
    for (final strategy in order) {
      if (available.contains(strategy)) return strategy;
    }
    return factors.isEmpty ? clerk.Strategy.password : factors.first.strategy;
  }

  static String _codeMessage(clerk.SignIn signIn, clerk.Strategy strategy) {
    final target = signIn.factorFor(strategy)?.safeIdentifier;
    return switch (strategy) {
      clerk.Strategy.totp => 'Enter the code from your authenticator app.',
      clerk.Strategy.backupCode => 'Enter one of your backup codes.',
      _ when target != null => 'Enter the 6-digit code sent to $target.',
      _ => 'Enter the 6-digit code we sent you.',
    };
  }

  static String? _factorLabel(clerk.Strategy strategy) => switch (strategy) {
    clerk.Strategy.totp => 'Use authenticator app',
    clerk.Strategy.emailCode => 'Email me a code',
    clerk.Strategy.phoneCode => 'Text me a code',
    clerk.Strategy.backupCode => 'Use a backup code',
    _ => null,
  };
}

// -----------------------------------------------------------------------------
// Widgets

const _radius = BorderRadius.all(Radius.circular(12));

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Text(text, style: Theme.of(context).textTheme.headlineMedium),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.autofillHints,
    this.obscureText = false,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: _radius,
          borderSide: BorderSide(color: color, width: width),
        );
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      obscureText: obscureText,
      autofocus: autofocus,
      autocorrect: false,
      enableSuggestions: !obscureText && keyboardType != TextInputType.number,
      textInputAction: textInputAction ?? TextInputAction.done,
      onSubmitted: onSubmitted,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: hint,
        constraints: const BoxConstraints.tightFor(height: _controlHeight),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: border(scheme.outlineVariant),
        enabledBorder: border(scheme.outlineVariant),
        focusedBorder: border(scheme.primary, 2),
        suffixIcon: suffix,
      ),
    );
  }
}

class _ObscureToggle extends StatelessWidget {
  const _ObscureToggle({required this.obscured, required this.onPressed});

  final bool obscured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: obscured ? 'Show password' : 'Hide password',
      icon: Icon(obscured ? Icons.visibility : Icons.visibility_off),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(_controlHeight),
        shape: const RoundedRectangleBorder(borderRadius: _radius),
        textStyle: Theme.of(context).textTheme.titleMedium,
      ),
      child: busy
          ? SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onSurface,
                semanticsLabel: 'Loading',
              ),
            )
          : Text(label),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.connection, required this.onPressed});

  final clerk.SocialConnection connection;
  final VoidCallback? onPressed;

  /// Monochrome logos that are black and need inverting on dark backgrounds.
  static const _invertInDark = {
    clerk.Strategy.oauthGithub,
    clerk.Strategy.oauthApple,
    clerk.Strategy.oauthX,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invert =
        theme.brightness == Brightness.dark &&
        _invertInDark.contains(connection.strategy);
    Widget logo = connection.logoUrl.isEmpty
        ? const Icon(Icons.login, size: 28)
        : Image.network(
            connection.logoUrl,
            width: 28,
            height: 28,
            errorBuilder: (_, _, _) => const Icon(Icons.login, size: 28),
          );
    if (invert) {
      logo = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1, 0, 0, 0, 255, //
          0, -1, 0, 0, 255, //
          0, 0, -1, 0, 255, //
          0, 0, 0, 1, 0, //
        ]),
        child: logo,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        shape: const RoundedRectangleBorder(borderRadius: _radius),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        foregroundColor: theme.colorScheme.onSurface,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          logo,
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              connection.name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class _IdentifierChip extends StatelessWidget {
  const _IdentifierChip({required this.identifier, required this.onChange});

  final String identifier;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            identifier,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(onPressed: onChange, child: const Text('Change')),
      ],
    );
  }
}

class _TextLink extends StatelessWidget {
  const _TextLink(this.label, {required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        child: Text(label),
      ),
    );
  }
}

class _SwitchLink extends StatelessWidget {
  const _SwitchLink({
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  final String prompt;
  final String action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          prompt,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    );
  }
}
