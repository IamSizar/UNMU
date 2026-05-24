import 'package:flutter/material.dart';
import '../../widgets/directional_icon.dart';
import 'package:get/get.dart';

import '../../services/auth_service.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/responsive.dart';
import '../../widgets/auth/auth_widgets.dart';
import '../../widgets/dismiss_keyboard_on_tap.dart';
import '../social/social_tokens.dart';

/// =============================================================================
/// Reset-password screen — step 2 of the forgot-password flow.
///
/// User pastes the token from the email link (or it's pre-filled in dev
/// mode via [devToken]) plus a new password. We POST
/// /auth/password-reset/confirm and, on success, pop back to login with
/// a success snackbar.
///
/// Universal-link plumbing (Phase 2 deep-linking) will eventually push
/// this screen directly with the token already extracted from the URL
/// query string — for now users either paste it manually or land here
/// from ForgotPasswordScreen with the dev token surfaced as a chip.
/// =============================================================================
class ResetPasswordScreen extends StatefulWidget {
  final String email;
  final String? devToken;

  const ResetPasswordScreen({
    super.key,
    required this.email,
    this.devToken,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final TextEditingController _token;
  late final TextEditingController _password;
  late final TextEditingController _confirm;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _token = TextEditingController(text: widget.devToken ?? '');
    _password = TextEditingController();
    _confirm = TextEditingController();
    _token.addListener(_repaint);
    _password.addListener(_repaint);
    _confirm.addListener(_repaint);
  }

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  bool get _canSubmit {
    if (_submitting) return false;
    if (_token.text.trim().isEmpty) return false;
    if (_password.text.length < 6) return false;
    if (_password.text != _confirm.text) return false;
    return true;
  }

  // Accepts either a raw token or a full reset URL pasted from the email
  // (e.g. https://unmu.app/reset-password?token=abc123). When a URL is
  // detected we pull the `token` query param out so the user can just
  // copy the whole link from their inbox.
  String _extractToken(String raw) {
    final v = raw.trim();
    final uri = Uri.tryParse(v);
    final fromQuery = uri?.queryParameters['token'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    return v;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    HapticUtils.lightTap();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await AuthService.confirmPasswordReset(
      token: _extractToken(_token.text),
      newPassword: _password.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result['success'] != true) {
      setState(() =>
          _error = result['error']?.toString() ?? 'common.unknownError'.tr);
      return;
    }
    await HapticUtils.success();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('auth.reset.successSnack'.tr),
      ),
    );
    // Pop back through the forgot-password screen to land on login.
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final showDevChip = (widget.devToken ?? '').isNotEmpty;

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
            padding: EdgeInsets.fromLTRB(context.centeringHPad(),
                8, context.centeringHPad(), 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                const Center(child: AuthBrandMark()),
                const SizedBox(height: 24),
                Text(
                  'auth.reset.title'.tr,
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
                  widget.email.isEmpty
                      ? 'auth.reset.subtitleNoEmail'.tr
                      : 'auth.reset.subtitleEmail'
                          .trParams({'email': widget.email}),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                if (showDevChip) ...[
                  const SizedBox(height: 14),
                  Center(
                    child: _DevTokenChip(
                      token: widget.devToken!,
                      onTap: () => _token.text = widget.devToken!,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                if (_error != null) ...[
                  AuthErrorBanner(message: _error!),
                  const SizedBox(height: 14),
                ],
                AuthField(
                  controller: _token,
                  label: 'auth.reset.codeLabel'.tr,
                  hint: 'auth.reset.codeHint'.tr,
                  icon: Icons.vpn_key_rounded,
                  accent: SocialTokens.cyan,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                AuthField(
                  controller: _password,
                  label: 'auth.reset.newPassword'.tr,
                  hint: '••••••••',
                  icon: Icons.lock_outline_rounded,
                  accent: SocialTokens.gold,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                AuthField(
                  controller: _confirm,
                  label: 'auth.reset.confirm'.tr,
                  hint: '••••••••',
                  icon: Icons.lock_outline_rounded,
                  accent: SocialTokens.gold,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
                if (_password.text.isNotEmpty &&
                    _confirm.text.isNotEmpty &&
                    _password.text != _confirm.text) ...[
                  const SizedBox(height: 8),
                  Text(
                    'auth.passwordsDontMatch'.tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: SocialTokens.down,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                GradientCTA(
                  label: 'auth.reset.cta'.tr,
                  trailingIcon: Icons.check_rounded,
                  enabled: _canSubmit,
                  loading: _submitting,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DevTokenChip extends StatelessWidget {
  final String token;
  final VoidCallback onTap;
  const _DevTokenChip({required this.token, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SocialTokens.cyan.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: SocialTokens.cyan.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.flash_on_rounded,
              size: 14,
              color: SocialTokens.cyan,
            ),
            const SizedBox(width: 6),
            const Text(
              'DEV · TAP TO FILL',
              style: TextStyle(
                color: SocialTokens.cyan,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                token,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SocialTokens.cyan,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
