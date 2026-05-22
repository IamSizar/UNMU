import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../screens/social/social_tokens.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/auth/auth_widgets.dart';
import '../../widgets/dismiss_keyboard_on_tap.dart';

/// =============================================================================
/// Onboarding Screen — shown once, right after a first-time Google/Apple
/// sign-in (when the account has no local password yet).
///
/// The user is ALREADY authenticated (the OAuth sign-in minted a JWT and
/// AuthController set the session). Here they set a display name + a
/// password, which:
///   • lets them later sign in with email + password too, and
///   • flips AuthController.needsOnboarding → false, so _AppEntry swaps
///     this screen for the main app (no manual navigation needed).
///
/// There's no "back" — they're committed — but a "Sign out" action in the
/// app bar lets them bail to the login screen instead of being trapped.
/// =============================================================================
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill the name from the OAuth profile (Google/Apple usually
    // provide a display name) so the user can just confirm it.
    final existing = Get.find<AuthController>().user?.name ?? '';
    _name.text = existing;
    _name.addListener(_recompute);
    _password.addListener(_recompute);
    _confirm.addListener(_recompute);
    _recompute();
  }

  void _recompute() {
    final next = _name.text.trim().isNotEmpty &&
        _password.text.length >= 6 &&
        _password.text == _confirm.text;
    if (next != _canSubmit) setState(() => _canSubmit = next);
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validationHint() {
    if (_password.text.isNotEmpty && _password.text.length < 6) {
      return 'auth.passwordTooShort'.tr;
    }
    if (_confirm.text.isNotEmpty && _confirm.text != _password.text) {
      return 'auth.passwordsDontMatch'.tr;
    }
    return null;
  }

  Future<void> _handleSubmit() async {
    if (!_canSubmit) return;
    HapticUtils.lightTap();
    FocusScope.of(context).unfocus();
    final auth = Get.find<AuthController>();

    final result = await auth.completeOnboarding(_name.text.trim(), _password.text);
    if (!mounted) return;
    if (result.authenticated) {
      await HapticUtils.success();
      // needsOnboarding is now false — _AppEntry rebuilds into the main
      // app automatically. Nothing to navigate.
      return;
    }
    await HapticUtils.error();
  }

  Future<void> _signOut() async {
    HapticUtils.lightTap();
    await Get.find<AuthController>().logout();
    // logout clears the session — _AppEntry swaps to the login screen.
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final auth = Get.find<AuthController>();
    final email = auth.user?.email ?? '';
    final hint = _validationHint();

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: auth.isLoading ? null : _signOut,
            style: TextButton.styleFrom(foregroundColor: palette.textMuted),
            child: Text(
              'auth.signOut'.tr,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
        ],
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
                          'auth.onboarding.title'.tr,
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
                          'auth.onboarding.subtitle'.trParams({'email': email}),
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 26),
                        if (auth.error != null) ...[
                          AuthErrorBanner(message: auth.error!),
                          const SizedBox(height: 14),
                        ],
                        AuthField(
                          controller: _name,
                          label: 'auth.name'.tr,
                          hint: 'auth.nameHint'.tr,
                          icon: Icons.person_outline_rounded,
                          accent: SocialTokens.cyan,
                          keyboardType: TextInputType.name,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        AuthField(
                          controller: _password,
                          label: 'auth.createPassword'.tr,
                          hint: '••••••••',
                          icon: Icons.lock_outline_rounded,
                          accent: SocialTokens.gold,
                          obscureText: true,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        AuthField(
                          controller: _confirm,
                          label: 'auth.confirmPassword'.tr,
                          hint: '••••••••',
                          icon: Icons.lock_person_outlined,
                          accent: SocialTokens.gold,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _handleSubmit(),
                        ),
                        if (hint != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                color: SocialTokens.down,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  hint,
                                  style: const TextStyle(
                                    color: SocialTokens.down,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 18),
                        GradientCTA(
                          label: 'auth.onboarding.cta'.tr,
                          trailingIcon: Icons.arrow_forward_rounded,
                          enabled: _canSubmit,
                          loading: auth.isLoading,
                          onPressed: _handleSubmit,
                        ),
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
