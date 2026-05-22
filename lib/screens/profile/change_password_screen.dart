import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/account_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/auth/auth_widgets.dart';
import '../../widgets/dismiss_keyboard_on_tap.dart';
import '../social/social_tokens.dart';

/// Settings sub-screen — change the signed-in user's password.
///
/// Hits POST /api/me/change-password which verifies the *current*
/// password before writing the new bcrypt hash. The user's existing JWT
/// stays valid afterwards (no auto-logout) so the UX is: change →
/// success snackbar → back to settings.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_current, _next, _confirm]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_submitting) return false;
    if (_current.text.isEmpty) return false;
    if (_next.text.length < 6) return false;
    if (_next.text != _confirm.text) return false;
    if (_next.text == _current.text) return false;
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    HapticUtils.lightTap();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await AccountService.changePassword(
      currentPassword: _current.text,
      newPassword: _next.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res.error != null) {
      setState(() => _error = res.error);
      return;
    }
    await HapticUtils.success();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('changePassword.updated'.tr)),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'changePassword.title'.tr,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Text(
                  'changePassword.intro'.tr,
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
                  controller: _current,
                  label: 'changePassword.current'.tr,
                  hint: '••••••••',
                  icon: Icons.lock_outline_rounded,
                  accent: SocialTokens.gold,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                AuthField(
                  controller: _next,
                  label: 'changePassword.new'.tr,
                  hint: '••••••••',
                  icon: Icons.lock_outline_rounded,
                  accent: SocialTokens.cyan,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                AuthField(
                  controller: _confirm,
                  label: 'changePassword.confirm'.tr,
                  hint: '••••••••',
                  icon: Icons.lock_outline_rounded,
                  accent: SocialTokens.cyan,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
                if (_next.text.isNotEmpty &&
                    _confirm.text.isNotEmpty &&
                    _next.text != _confirm.text) ...[
                  const SizedBox(height: 8),
                  Text(
                    'changePassword.mismatch'.tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: SocialTokens.down,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                GradientCTA(
                  label: 'changePassword.update'.tr,
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
