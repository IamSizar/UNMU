import 'package:flutter/material.dart';
import '../../widgets/directional_icon.dart';
import 'package:get/get.dart';

import '../../services/auth_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/auth/auth_widgets.dart';
import '../../widgets/dismiss_keyboard_on_tap.dart';
import '../social/social_tokens.dart';
import 'reset_password_screen.dart';

/// =============================================================================
/// Forgot-password screen — step 1 of the reset flow.
///
/// User types their email; we POST /auth/password-reset/request. The
/// backend returns a generic 200 either way (account-enumeration
/// protection) — in dev mode we get a `resetToken` in the response so
/// testers can skip the email inbox. Either way we transition to the
/// reset screen with the email pre-filled and the dev token (if any)
/// surfaced as a "tap to fill" chip there.
/// =============================================================================
class ForgotPasswordScreen extends StatefulWidget {
  /// Pre-fills the email field when navigated from the login screen.
  final String? initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail ?? '');
    // Repaint when the email changes so the submit-button enabled-state
    // updates live. (AuthField doesn't expose an onChanged hook.)
    _email.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  bool get _canSubmit => _email.text.trim().contains('@') && !_submitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    HapticUtils.lightTap();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await AuthService.requestPasswordReset(_email.text.trim());
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result['success'] != true) {
      setState(() =>
          _error = result['error']?.toString() ?? 'common.unknownError'.tr);
      return;
    }
    await HapticUtils.success();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(
          email: _email.text.trim(),
          devToken: result['devCode'] as String?,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        leading: IconButton(
          icon: DirectionalIcon(Icons.arrow_back_rounded, color: palette.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: DismissKeyboardOnTap(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                const Center(child: AuthBrandMark()),
                const SizedBox(height: 24),
                Text(
                  'auth.forgot.title'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'auth.forgot.subtitle'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),
                if (_error != null) ...[
                  AuthErrorBanner(message: _error!),
                  const SizedBox(height: 14),
                ],
                AuthField(
                  controller: _email,
                  label: 'auth.email'.tr,
                  hint: 'auth.emailHint'.tr,
                  icon: Icons.alternate_email_rounded,
                  accent: SocialTokens.cyan,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 22),
                GradientCTA(
                  label: 'auth.forgot.cta'.tr,
                  trailingIcon: Icons.send_rounded,
                  enabled: _canSubmit,
                  loading: _submitting,
                  onPressed: _submit,
                ),
                const SizedBox(height: 14),
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      // Lets users who already have a token (from an
                      // email link, paste, etc.) skip step 1.
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ResetPasswordScreen(
                            email: _email.text.trim(),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.vpn_key_rounded, size: 16),
                    label: Text(
                      'auth.forgot.haveCode'.tr,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: SocialTokens.cyan,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
