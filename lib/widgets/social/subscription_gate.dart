import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../screens/social/social_tokens.dart';

/// Wraps an expert's post (or list of posts) with a subscription paywall.
///
/// When the current user is NOT subscribed to [expertId], the wrapped
/// content is rendered behind a frosted-blur overlay with a "Subscribe to
/// view" CTA. Tapping the CTA toggles [AuthController.toggleSubscription] —
/// the underlying content reveals immediately.
///
/// The expert/scholar account viewing their own profile bypasses the gate
/// (handled by `AuthController.isSubscribedTo` returning true for `self`).
class SubscriptionGate extends StatelessWidget {
  final String expertId;
  final String expertName;
  final Color accent;
  final Widget child;

  const SubscriptionGate({
    super.key,
    required this.expertId,
    required this.expertName,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final palette = SocialTheme.of(context);
    final unlocked = auth.isSubscribedTo(expertId);

    if (unlocked) return child;

    return Stack(
      children: [
        // Original content rendered behind the blur — keeps the layout
        // height consistent before/after subscribing.
        IgnorePointer(child: child),
        // Blur + scrim overlay
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                color: palette.background.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
        // Centered subscribe card
        Positioned.fill(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _SubscribeCta(
                palette: palette,
                expertId: expertId,
                expertName: expertName,
                accent: accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SubscribeCta extends StatelessWidget {
  final SocialPalette palette;
  final String expertId;
  final String expertName;
  final Color accent;

  const _SubscribeCta({
    required this.palette,
    required this.expertId,
    required this.expertName,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        gradient: palette.heroGradient(),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accent.withValues(alpha: palette.isDark ? 0.55 : 0.35),
          width: 1.4,
        ),
        boxShadow: palette.cardShadow(accent: accent),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Lock icon in a circle
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.18),
              border: Border.all(
                color: accent.withValues(alpha: 0.5),
                width: 1.4,
              ),
            ),
            child: Icon(Icons.lock_rounded, color: accent, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            'subGate.subscribeToView'.tr,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'subGate.accessBody'.trParams({'name': expertName}),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              Get.find<AuthController>().toggleSubscription(expertId);
            },
            icon: const Icon(Icons.bolt_rounded, size: 18),
            label: Text(
              'subGate.subscribe'.tr,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: const Color(0xFF0A1628),
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
