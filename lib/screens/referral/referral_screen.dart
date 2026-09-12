import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../controllers/auth_controller.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/api_service.dart';
import '../../utils/haptic_utils.dart';

/// Referral screen — a user's personal referral code (share it) plus a
/// field to redeem someone else's code (once, per the backend's
/// UNIQUE(referred_user_id) constraint). Backend: backend/internal/
/// handlers/referral.go, added earlier this session with no UI until now.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  String? _myCode;
  String? _shareMessage;
  int? _rewardPercent;
  int? _referralCount;
  bool _loading = true;
  bool _loadFailed = false;

  final _redeemController = TextEditingController();
  bool _redeeming = false;
  String? _redeemMessage;
  bool _redeemSucceeded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _redeemController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = Get.find<AuthController>();
    if (!auth.isAuthenticated) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final results = await Future.wait([
      ApiService.getMyReferralCode(auth.token!),
      ApiService.getReferralCount(auth.token!),
    ]);
    if (!mounted) return;
    final codeData = results[0] as Map<String, dynamic>?;
    final count = results[1] as int?;
    setState(() {
      _loading = false;
      if (codeData == null) {
        _loadFailed = true;
        return;
      }
      _myCode = codeData['code']?.toString();
      _shareMessage = codeData['shareMessage']?.toString();
      _rewardPercent = (codeData['rewardPercent'] as num?)?.toInt();
      _referralCount = count;
    });
  }

  Future<void> _share() async {
    if (_shareMessage == null || _shareMessage!.isEmpty) return;
    HapticUtils.lightTap();
    await Share.share(_shareMessage!);
  }

  Future<void> _copyCode() async {
    if (_myCode == null) return;
    await Clipboard.setData(ClipboardData(text: _myCode!));
    HapticUtils.lightTap();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('referral.copied'.tr)),
      );
    }
  }

  Future<void> _redeem() async {
    final code = _redeemController.text.trim();
    if (code.isEmpty) return;
    final auth = Get.find<AuthController>();
    if (!auth.isAuthenticated) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _redeeming = true;
      _redeemMessage = null;
    });
    final (success, message) = await ApiService.redeemReferralCode(auth.token!, code);
    if (!mounted) return;
    setState(() {
      _redeeming = false;
      _redeemSucceeded = success;
      _redeemMessage = message;
    });
    if (success) {
      HapticUtils.success();
      _redeemController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final auth = Get.find<AuthController>();

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'referral.title'.tr,
          style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w800),
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
      ),
      body: !auth.isAuthenticated
          ? _SignInPrompt(palette: palette)
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadFailed
                  ? _ErrorState(palette: palette, onRetry: _load)
                  : GestureDetector(
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _MyCodeCard(
                            palette: palette,
                            code: _myCode ?? '',
                            rewardPercent: _rewardPercent ?? 0,
                            referralCount: _referralCount ?? 0,
                            onCopy: _copyCode,
                            onShare: _share,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'referral.redeemTitle'.tr,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'referral.redeemSubtitle'.tr,
                            style: TextStyle(color: palette.textSecondary, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _redeemController,
                                  textCapitalization: TextCapitalization.characters,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _redeem(),
                                  style: TextStyle(color: palette.textPrimary),
                                  decoration: InputDecoration(
                                    hintText: 'referral.codeHint'.tr,
                                    filled: true,
                                    fillColor: palette.surface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide(color: palette.border),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton(
                                onPressed: _redeeming ? null : _redeem,
                                child: _redeeming
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Text('referral.apply'.tr),
                              ),
                            ],
                          ),
                          if (_redeemMessage != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _redeemMessage!,
                              style: TextStyle(
                                color: _redeemSucceeded ? SocialTokens.up : SocialTokens.down,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

class _MyCodeCard extends StatelessWidget {
  const _MyCodeCard({
    required this.palette,
    required this.code,
    required this.rewardPercent,
    required this.referralCount,
    required this.onCopy,
    required this.onShare,
  });

  final SocialPalette palette;
  final String code;
  final int rewardPercent;
  final int referralCount;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [SocialTokens.violet.withValues(alpha: 0.18), palette.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'referral.giveGetTitle'.trParams({'percent': '$rewardPercent'}),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'referral.giveGetSubtitle'.tr,
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: onCopy,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: palette.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: SocialTokens.violet.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      code.isEmpty ? '——————' : code,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  Icon(Icons.copy_rounded, color: SocialTokens.violet, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.group_rounded, size: 16, color: palette.textSecondary),
              const SizedBox(width: 6),
              Text(
                'referral.countLabel'.trParams({'count': '$referralCount'}),
                style: TextStyle(color: palette.textSecondary, fontSize: 13),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.ios_share_rounded, size: 16),
                label: Text('referral.share'.tr),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.palette});
  final SocialPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'referral.signInSubtitle'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
              child: Text('watchlist.signIn'.tr),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.palette, required this.onRetry});
  final SocialPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: SocialTokens.down),
            const SizedBox(height: 16),
            Text(
              'referral.errorLoading'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: Text('common.refresh'.tr)),
          ],
        ),
      ),
    );
  }
}
