import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../services/account_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/auth/auth_widgets.dart';
import '../../widgets/dismiss_keyboard_on_tap.dart';
import '../social/social_tokens.dart';

/// Settings sub-screen — permanently delete the signed-in account.
///
/// Two-input gate: the user re-enters their password AND types the
/// literal word "DELETE" so accidental triggers (e.g. an old Postman
/// tab, a child poking around in the app) don't take effect. Backend
/// soft-deletes the row with PII anonymized and immediately revokes
/// future logins; we sign the user out locally and return them to
/// the auth flow.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_password, _confirm]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_submitting) return false;
    // For password accounts the field must be filled. For OAuth-only
    // accounts the backend accepts an empty password — the JWT itself
    // is the proof of identity. We can't reliably detect "OAuth-only"
    // on the client (the User model doesn't carry password_hash), so
    // we keep the password optional here and let the server reject if
    // it's required.
    if (_confirm.text.trim().toUpperCase() != 'DELETE') return false;
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    // One more confirmation dialog — there's no undo and the soft-
    // delete tombstone can't be re-claimed under the original email
    // until the user re-registers.
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('deleteAccount.confirmTitle'.tr),
        content: Text('deleteAccount.confirmBody'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SocialTokens.down,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('deleteAccount.deletePermanently'.tr),
          ),
        ],
      ),
    );
    if (go != true) return;

    HapticUtils.errorBuzz();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await AccountService.deleteAccount(
      password: _password.text,
      confirm: 'DELETE',
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res.error != null) {
      setState(() => _error = res.error);
      return;
    }
    // Sign out + bounce to the auth flow. The AuthController's logout()
    // clears local token + user; the app's root Obx switches back to
    // the unauthed routes automatically.
    await Get.find<AuthController>().logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('deleteAccount.deleted'.tr)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final email = Get.find<AuthController>().user?.email ?? '';

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'deleteAccount.title'.tr,
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
                // Warning banner — destructive action.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SocialTokens.down.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: SocialTokens.down.withValues(alpha: 0.40),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: SocialTokens.down,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'deleteAccount.warning'.trParams({'email': email}),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                if (_error != null) ...[
                  AuthErrorBanner(message: _error!),
                  const SizedBox(height: 14),
                ],
                AuthField(
                  controller: _password,
                  label: 'deleteAccount.password'.tr,
                  hint: 'deleteAccount.passwordHint'.tr,
                  icon: Icons.lock_outline_rounded,
                  accent: SocialTokens.down,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                AuthField(
                  controller: _confirm,
                  label: 'deleteAccount.typeToConfirm'.tr,
                  hint: 'DELETE',
                  icon: Icons.delete_outline_rounded,
                  accent: SocialTokens.down,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _canSubmit ? _submit : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: SocialTokens.down,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        SocialTokens.down.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.delete_forever_rounded),
                  label: Text(
                    'deleteAccount.deleteForever'.tr,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
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
