import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../models/expert_post.dart';
import '../../services/expert_subscription_service.dart';
import '../../utils/haptic_utils.dart';
import '../subscriptions/subscribe_modal.dart';
import 'social_tokens.dart';

/// Dedicated full-screen paywall for an expert.
///
/// Reached from:
///   * Tapping any [_LockedPostCard] anywhere it appears (today: the
///     expert profile's subscribers-only feed).
///   * Push notifications + universal links that resolve to a paid
///     post — the route bypasses the profile and lands here.
///
/// Renders the expert's pricing live (fetched on init), the lock copy,
/// the post title we were trying to reach, and a single big Subscribe
/// CTA. Tapping the CTA opens [SubscribeModal] which handles the
/// actual plan/payment-method selection + Apple IAP / cash / FIB.
class ExpertPaywallScreen extends StatefulWidget {
  final String expertId;
  final String expertName;
  /// Title of the post the user was trying to read, if any — surfaces
  /// in the body so the user knows what they're unlocking.
  final String? postTitle;
  final PostType? postType;

  const ExpertPaywallScreen({
    super.key,
    required this.expertId,
    required this.expertName,
    this.postTitle,
    this.postType,
  });

  /// Convenience push — replaces the boilerplate at call sites.
  static Future<void> show(
    BuildContext context, {
    required String expertId,
    required String expertName,
    String? postTitle,
    PostType? postType,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExpertPaywallScreen(
          expertId: expertId,
          expertName: expertName,
          postTitle: postTitle,
          postType: postType,
        ),
      ),
    );
  }

  @override
  State<ExpertPaywallScreen> createState() => _ExpertPaywallScreenState();
}

class _ExpertPaywallScreenState extends State<ExpertPaywallScreen> {
  ExpertPricing? _pricing;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  Future<void> _loadPricing() async {
    final res =
        await ExpertSubscriptionService.fetchExpertPricing(widget.expertId);
    if (!mounted) return;
    setState(() {
      _pricing = res;
      _loading = false;
    });
  }

  Future<void> _onSubscribe() async {
    HapticUtils.lightTap();
    final sub = await SubscribeModal.show(
      context,
      expertId: widget.expertId,
      expertName: widget.expertName,
    );
    if (sub != null && mounted) {
      // Subscription accepted (cash/FIB → admin approval) or active
      // (Apple IAP path). Either way, drop the paywall — the caller's
      // screen reloads from realtime events.
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    const accent = SocialTokens.cyan;
    final monthlyLabel = _pricing?.monthlyLabel ?? '—';
    final yearlyLabel = _pricing?.yearlyLabel ?? '—';
    final perMonthLabel = _pricing?.yearlyMonthlyEquivalent ?? '—';

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: palette.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'paywall.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),
              // Big circular lock icon.
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.18),
                        accent.withValues(alpha: 0.04),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.45),
                      width: 1.4,
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 44,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                widget.postTitle?.trim().isNotEmpty == true
                    ? widget.postTitle!
                    : 'paywall.subscribeToExpert'
                        .trParams({'name': widget.expertName}),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'paywall.bodyForSubscribers'.trParams({
                  'kind': _kindLabel(widget.postType),
                  'name': widget.expertName,
                }),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 13.5,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 28),
              // Pricing teaser. Renders a skeleton while the pricing
              // call is in flight so the layout doesn't jump.
              if (_loading)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                )
              else if (_pricing != null) ...[
                _PriceRow(
                  palette: palette,
                  label: 'paywall.monthly'.tr,
                  price: monthlyLabel,
                  sub: 'paywall.billedMonthly'.tr,
                ),
                const SizedBox(height: 10),
                _PriceRow(
                  palette: palette,
                  label: 'paywall.yearly'.tr,
                  price: yearlyLabel,
                  sub: 'paywall.worksOutTo'
                      .trParams({'price': perMonthLabel}),
                  highlight: true,
                ),
              ],
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: _onSubscribe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: const Color(0xFF0A1628),
                  elevation: 0,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.lock_open_rounded),
                label: Text(
                  'paywall.subscribeToUnlock'.tr,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'paywall.cancelAnytime'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _kindLabel(PostType? t) {
    switch (t) {
      case PostType.video:
        return 'paywall.kindVideo'.tr;
      case PostType.reel:
        return 'paywall.kindReel'.tr;
      case PostType.article:
      case null:
        return 'paywall.kindPost'.tr;
    }
  }
}

class _PriceRow extends StatelessWidget {
  final SocialPalette palette;
  final String label;
  final String price;
  final String sub;
  final bool highlight;
  const _PriceRow({
    required this.palette,
    required this.label,
    required this.price,
    required this.sub,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    const accent = SocialTokens.cyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight
              ? accent.withValues(alpha: 0.55)
              : palette.border,
          width: highlight ? 1.4 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (highlight) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          'paywall.bestValue'.tr,
                          style: const TextStyle(
                            color: accent,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(color: palette.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            price,
            style: TextStyle(
              color: highlight ? accent : palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}
