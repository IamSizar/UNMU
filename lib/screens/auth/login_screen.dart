import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import '../../widgets/directional_icon.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../screens/social/social_tokens.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/auth/auth_widgets.dart';
import '../../widgets/dismiss_keyboard_on_tap.dart';
import '../../widgets/social/test_account_switcher.dart';
import 'forgot_password_screen.dart';

/// =============================================================================
/// Login Screen — one screen: email + password + Apple/Google.
///
///   • Email + password "Log in" is LOGIN-ONLY. We checkEmail first: if the
///     address isn't registered we say so (registration happens via OAuth,
///     not here). If it is registered we verify the password.
///   • Google / Apple register a brand-new user the first time (then the
///     onboarding screen — gated in _AppEntry — collects name + password)
///     and log returning users straight in.
///   • Forgot-password link is kept. No "Sign up" link (OAuth is sign-up).
/// =============================================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _canSubmit = false;

  // Screen-local error (e.g. "not registered") shown in the banner above
  // the form. Distinct from AuthController.error (network / wrong password)
  // — the banner renders whichever is set.
  String? _formError;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    _email.addListener(_recompute);
    _password.addListener(_recompute);
  }

  void _recompute() {
    final next = _emailRe.hasMatch(_email.text.trim()) &&
        _password.text.trim().isNotEmpty;
    if (next != _canSubmit || _formError != null) {
      setState(() {
        _canSubmit = next;
        _formError = null; // clear stale error once the user edits
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // Email + password — LOGIN ONLY. checkEmail first so we can show the
  // precise "not registered" message instead of a generic 401.
  Future<void> _handleLogin() async {
    if (!_canSubmit) return;
    HapticUtils.lightTap();
    FocusScope.of(context).unfocus();
    final auth = Get.find<AuthController>();
    final email = _email.text.trim();
    setState(() => _formError = null);

    final exists = await auth.checkEmail(email);
    if (!mounted) return;
    if (exists == null) {
      // Network/server problem — auth.error is set; surface a haptic.
      await HapticUtils.error();
      return;
    }
    if (!exists) {
      setState(() {
        _formError = 'auth.login.notRegistered'.tr;
      });
      await HapticUtils.error();
      return;
    }

    final result = await auth.login(email, _password.text);
    if (!mounted) return;
    if (result.authenticated) {
      await HapticUtils.success();
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
      return;
    }
    await HapticUtils.error(); // auth.error (e.g. wrong password) shows in banner
  }

  // ── OAuth ──────────────────────────────────────────────────────────
  // On success the session is set; _AppEntry shows the onboarding screen
  // (new user) or the main app (returning). We just pop back to root so
  // the swap is visible when LoginScreen was pushed on top of _AppEntry.
  Future<void> _handleOAuth(
    Future<AuthFlowResult> Function() flow, {
    required String label,
  }) async {
    HapticUtils.lightTap();
    setState(() => _formError = null);
    final result = await flow();
    if (!mounted) return;

    if (result.authenticated) {
      await HapticUtils.success();
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
      return;
    }

    // Cancellation isn't an error — the user just closed the picker.
    final err = Get.find<AuthController>().error;
    if (err == AuthController.oauthCancelledSentinel) {
      Get.find<AuthController>().clearError();
      return;
    }

    await HapticUtils.error();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('auth.login.oauthFailed'.trParams({'label': label})),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleGoogle() {
    final auth = Get.find<AuthController>();
    _handleOAuth(auth.signInWithGoogle, label: 'Google');
  }

  void _handleApple() {
    final auth = Get.find<AuthController>();
    _handleOAuth(auth.signInWithApple, label: 'Apple');
  }

  Future<void> _openTestPicker() async {
    HapticUtils.lightTap();
    await TestAccountSwitcherSheet.show(context);
    if (!mounted) return;
    final auth = Get.find<AuthController>();
    if (auth.isAuthenticated && Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final auth = Get.find<AuthController>();
    final shownError = _formError ?? auth.error;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: DirectionalIcon(Icons.arrow_back_rounded, color: palette.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: SafeArea(
        child: DismissKeyboardOnTap(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        const AuthBrandMark(size: 56),
                        const SizedBox(height: 22),
                        Text(
                          'auth.login.welcomeBack'.tr,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 30,
                            letterSpacing: -0.8,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'auth.login.subtitle'.tr,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (shownError != null) ...[
                          AuthErrorBanner(message: shownError),
                          const SizedBox(height: 14),
                        ],
                        AuthField(
                          controller: _email,
                          label: 'auth.email'.tr,
                          hint: 'auth.emailHint'.tr,
                          icon: Icons.alternate_email_rounded,
                          accent: SocialTokens.cyan,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        AuthField(
                          controller: _password,
                          label: 'auth.password'.tr,
                          hint: '••••••••',
                          icon: Icons.lock_outline_rounded,
                          accent: SocialTokens.gold,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _handleLogin(),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            onPressed: () {
                              HapticUtils.lightTap();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ForgotPasswordScreen(
                                    initialEmail: _email.text.trim().isEmpty
                                        ? null
                                        : _email.text.trim(),
                                  ),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: SocialTokens.cyan,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'auth.forgotPassword'.tr,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        GradientCTA(
                          label: 'auth.login.cta'.tr,
                          trailingIcon: Icons.arrow_forward_rounded,
                          enabled: _canSubmit,
                          loading: auth.isLoading,
                          onPressed: () => _handleLogin(),
                        ),
                        const SizedBox(height: 22),
                        OrDivider(
                          label: 'auth.orContinueWith'.tr,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            if (Platform.isIOS) ...[
                              SocialAuthButton(
                                icon: Icons.apple_rounded,
                                label: 'Apple',
                                onPressed: auth.isLoading
                                    ? null
                                    : () => _handleApple(),
                              ),
                              const SizedBox(width: 10),
                            ],
                            SocialAuthButton(
                              icon: Icons.g_mobiledata_rounded,
                              label: 'Google',
                              iconColor: const Color(0xFFEA4335),
                              onPressed: auth.isLoading
                                  ? null
                                  : () => _handleGoogle(),
                            ),
                          ],
                        ),
                        if (kDebugMode) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              SocialAuthButton(
                                icon: Icons.science_rounded,
                                label: 'auth.testAccount'.tr,
                                iconColor: SocialTokens.gold,
                                onPressed:
                                    auth.isLoading ? null : _openTestPicker,
                              ),
                            ],
                          ),
                        ],
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
