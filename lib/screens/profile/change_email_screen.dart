import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../services/account_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/auth/auth_widgets.dart';
import '../../widgets/dismiss_keyboard_on_tap.dart';
import '../social/social_tokens.dart';

/// Settings sub-screen — change email (two-step verification).
///
/// Step 1 — user enters a new email + current password. We POST
/// /me/change-email/request which sends a 6-digit code to the NEW
/// address. In dev mode the code comes back in the response so the
/// in-screen state can pre-fill it.
///
/// Step 2 — user types the code (or it's pre-filled in dev). We POST
/// /me/change-email/confirm. On success the backend flips users.email
/// and returns the refreshed User; we swap that into the AuthController
/// session and pop with a success snackbar.
class ChangeEmailScreen extends StatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  // Step machine.
  bool _step2 = false;

  // Step 1 inputs.
  final _newEmail = TextEditingController();
  final _password = TextEditingController();

  // Step 2 inputs.
  final _code = TextEditingController();
  String? _devCode;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_newEmail, _password, _code]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _newEmail.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  // ─── step 1 ─────────────────────────────────────────────────────────

  bool get _canRequest {
    if (_submitting) return false;
    if (!_newEmail.text.contains('@')) return false;
    if (_password.text.isEmpty) return false;
    return true;
  }

  Future<void> _requestCode() async {
    if (!_canRequest) return;
    HapticUtils.lightTap();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await AccountService.requestEmailChange(
      newEmail: _newEmail.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res.error != null) {
      setState(() => _error = res.error);
      return;
    }
    setState(() {
      _step2 = true;
      _devCode = res.devCode;
      if (_devCode != null) _code.text = _devCode!;
    });
  }

  // ─── step 2 ─────────────────────────────────────────────────────────

  bool get _canConfirm => !_submitting && _code.text.trim().length >= 4;

  Future<void> _confirmCode() async {
    if (!_canConfirm) return;
    HapticUtils.lightTap();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await AccountService.confirmEmailChange(_code.text.trim());
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res.error != null) {
      setState(() => _error = res.error);
      return;
    }
    final updated = res.user;
    if (updated != null) {
      // Swap the refreshed user into the session cache so the rest of
      // the app picks up the new email immediately.
      final auth = Get.find<AuthController>();
      await auth.replaceSessionUser(updated);
    }
    await HapticUtils.success();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('changeEmail.updated'.tr)),
    );
    Navigator.of(context).pop();
  }

  // ─── shared chrome ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final currentEmail = Get.find<AuthController>().user?.email ?? '';

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'changeEmail.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
      ),
      body: SafeArea(
        child: DismissKeyboardOnTap(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: _step2
                ? _buildStep2(palette)
                : _buildStep1(palette, currentEmail),
          ),
        ),
      ),
    );
  }

  Widget _buildStep1(SocialPalette palette, String currentEmail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          'changeEmail.step1Intro'.trParams({'email': currentEmail}),
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        if (_error != null) ...[
          AuthErrorBanner(message: _error!),
          const SizedBox(height: 14),
        ],
        AuthField(
          controller: _newEmail,
          label: 'changeEmail.newEmail'.tr,
          hint: 'auth.emailHint'.tr,
          icon: Icons.alternate_email_rounded,
          accent: SocialTokens.cyan,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        AuthField(
          controller: _password,
          label: 'changeEmail.currentPassword'.tr,
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          accent: SocialTokens.gold,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _requestCode(),
        ),
        const SizedBox(height: 22),
        GradientCTA(
          label: 'changeEmail.sendCode'.tr,
          trailingIcon: Icons.send_rounded,
          enabled: _canRequest,
          loading: _submitting,
          onPressed: _requestCode,
        ),
      ],
    );
  }

  Widget _buildStep2(SocialPalette palette) {
    final to = _newEmail.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          'changeEmail.step2Intro'.trParams({'email': to}),
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        if ((_devCode ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
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
                const Icon(Icons.flash_on_rounded,
                    size: 14, color: SocialTokens.cyan),
                const SizedBox(width: 6),
                Text(
                  'DEV · $_devCode',
                  style: const TextStyle(
                    color: SocialTokens.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        if (_error != null) ...[
          AuthErrorBanner(message: _error!),
          const SizedBox(height: 14),
        ],
        AuthField(
          controller: _code,
          label: 'changeEmail.code'.tr,
          hint: '123456',
          icon: Icons.vpn_key_rounded,
          accent: SocialTokens.cyan,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _confirmCode(),
        ),
        const SizedBox(height: 22),
        GradientCTA(
          label: 'changeEmail.confirm'.tr,
          trailingIcon: Icons.check_rounded,
          enabled: _canConfirm,
          loading: _submitting,
          onPressed: _confirmCode,
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _submitting
                ? null
                : () => setState(() {
                      _step2 = false;
                      _code.clear();
                      _devCode = null;
                      _error = null;
                    }),
            child: Text(
              'changeEmail.startOver'.tr,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
        ),
      ],
    );
  }
}
