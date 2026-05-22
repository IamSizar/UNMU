import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:get/get.dart';

import '../social/social_tokens.dart';

/// Celebratory full-screen dialog shown the instant the user's expert
/// application is approved (driven by the realtime `application_approved`
/// event from `RealtimeController`).
///
/// REDESIGN NOTES (May 2026)
///   Previous version had three problems:
///     1. A multi-stop gold→primary→surface gradient on the card body
///        tinted everything yellow and made the upper-left feel muddy.
///     2. Flutter's default Dialog barrier (~32% black, no blur) let the
///        profile screen content (watchlist / network / upgrade banner)
///        leak through behind the dialog with poor contrast.
///     3. A green default-themed CTA fought with the gold burst above it.
///
///   The new version:
///     • Custom backdrop using `BackdropFilter` (sigma 24) + 72% dark scrim
///       so the page behind goes genuinely out of focus.
///     • Solid dark navy card with a SHORT gold→transparent gradient only
///       at the top 30%, so the gold feels emanating from the burst rather
///       than soaking the whole card.
///     • Crisp 1.2px gold border + subtle inner hairline.
///     • Single gold-gradient CTA (no more green-vs-gold clash).
///     • "APPLICATION APPROVED" micro-label + 2-line headline (no emoji).
///     • New capability checklist showing what unlocked (Articles, Videos,
///       Earnings, Community).
///     • Entrance: 280ms fade + scale 0.92→1.0 ease-out + burst pulse.
class ExpertWelcomeDialog extends StatelessWidget {
  /// Call this from anywhere — typically from `RealtimeController` when an
  /// application_approved event arrives. Idempotent: if a welcome dialog is
  /// already on top of the navigator stack, this becomes a no-op.
  static void show() {
    if (Get.isDialogOpen ?? false) return;
    Get.dialog(
      const ExpertWelcomeDialog(),
      barrierDismissible: false,
      // Transparent — we draw our own blurred barrier inside the dialog
      // body so we have full control over the dim + blur amount.
      barrierColor: Colors.transparent,
    );
  }

  const ExpertWelcomeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      elevation: 0,
      // Full-screen Stack so we can layer: blur → scrim → centered card.
      child: Stack(
        children: [
          // Layer 1 — strong blur over the entire page behind us.
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: const SizedBox.shrink(),
            ),
          ),
          // Layer 2 — dark scrim. 72% black so the page is recognizable
          // but visibly de-emphasized.
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.72)),
          ),
          // Layer 3 — the actual card, entrance-animated.
          Center(
            child: _EntranceAnimator(child: _WelcomeCard()),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Entrance animation — 280ms fade + slight scale-up. Curves.easeOutBack
// gives a tiny "pop" at the end without being childish.
// ============================================================================
class _EntranceAnimator extends StatelessWidget {
  final Widget child;
  const _EntranceAnimator({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (_, t, c) {
        // Two derived values: opacity (linear) and scale (0.92 → 1.0).
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: 0.92 + (0.08 * t),
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}

// ============================================================================
// The card itself — solid dark surface, top gold accent, capability list,
// gold CTA.
// ============================================================================
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  // Same dark navy used elsewhere in the social tab so the dialog feels
  // continuous with the rest of the app. Slightly elevated from the page
  // background so it sits on top visually.
  static const Color _cardSurface = Color(0xFF0E1B2E);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            color: _cardSurface,
            borderRadius: BorderRadius.circular(24),
            // Outer gold border — crisp, not soft.
            border: Border.all(
              color: SocialTokens.gold.withValues(alpha: 0.60),
              width: 1.2,
            ),
            // Single soft glow underneath so the card lifts off the
            // blurred background without bleeding everywhere.
            boxShadow: [
              BoxShadow(
                color: SocialTokens.gold.withValues(alpha: 0.20),
                blurRadius: 40,
                spreadRadius: -8,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          // Inner Stack so we can paint the top gold "halo" gradient and
          // an inner hairline without nesting another Container.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                // Top halo — gold→transparent fades out by 40% height.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 200,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            SocialTokens.gold.withValues(alpha: 0.16),
                            SocialTokens.gold.withValues(alpha: 0.04),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.4, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                // Card content.
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: _Burst()),
                      const SizedBox(height: 24),
                      const _MicroLabel(),
                      const SizedBox(height: 6),
                      const _Headline(),
                      const SizedBox(height: 12),
                      const _Subtitle(),
                      const SizedBox(height: 22),
                      const _CapabilityChecklist(),
                      const SizedBox(height: 24),
                      _GoldCTA(),
                      const SizedBox(height: 10),
                      const _Footer(),
                    ],
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

// ============================================================================
// "APPLICATION APPROVED" — gold micro-label above the headline.
// ============================================================================
class _MicroLabel extends StatelessWidget {
  const _MicroLabel();

  @override
  Widget build(BuildContext context) {
    // Letter-spacing on Arabic glyphs can break ligatures — only apply the
    // expanded tracking in LTR (English). The app flips to RTL in Arabic.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Text(
      'expertWelcome.microLabel'.tr,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: SocialTokens.gold,
        fontWeight: FontWeight.w900,
        fontSize: 10.5,
        letterSpacing: isRtl ? 0 : 2.2,
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline();

  @override
  Widget build(BuildContext context) {
    return Text(
      'expertWelcome.headline'.tr,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w900,
        fontSize: 30,
        height: 1.1,
        letterSpacing: -0.7,
      ),
    );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle();

  @override
  Widget build(BuildContext context) {
    return Text(
      'expertWelcome.subtitle'.tr,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.70),
        fontSize: 14,
        height: 1.5,
      ),
    );
  }
}

// ============================================================================
// Capability checklist — concrete list of what unlocked. Each row has a
// gold tick + subtle hairline divider between them.
// ============================================================================
class _CapabilityChecklist extends StatelessWidget {
  const _CapabilityChecklist();

  // Same 4 capabilities. Kept tuple-shaped to mirror the original list —
  // the build method resolves each translation key via `.tr`.
  static const List<(IconData, String)> _items = [
    (Icons.article_outlined,            'expertWelcome.capArticles'),
    (Icons.play_circle_outline_rounded, 'expertWelcome.capVideos'),
    (Icons.diamond_outlined,            'expertWelcome.capEarn'),
    (Icons.forum_outlined,              'expertWelcome.capCommunity'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _items.length; i++) ...[
            _CapRow(
              icon: _items[i].$1,
              label: _items[i].$2.tr,
            ),
            if (i < _items.length - 1)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.white.withValues(alpha: 0.05),
              ),
          ],
        ],
      ),
    );
  }
}

class _CapRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _CapRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.80)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SocialTokens.gold.withValues(alpha: 0.18),
              border: Border.all(
                color: SocialTokens.gold.withValues(alpha: 0.55),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 13,
              color: SocialTokens.gold,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Gold-gradient CTA — replaces the green default-themed FilledButton so
// the color story is cohesive (gold burst → gold checks → gold button).
// ============================================================================
class _GoldCTA extends StatelessWidget {
  const _GoldCTA();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (Get.isDialogOpen ?? false) Get.back();
            // Use the dialog's own context to grab the Phoenix ancestor —
            // Get.context might be the dialog overlay.
            Phoenix.rebirth(context);
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFFE680),
                  SocialTokens.gold,
                  Color(0xFFCFA300),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: SocialTokens.gold.withValues(alpha: 0.40),
                  blurRadius: 22,
                  spreadRadius: -4,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: Color(0xFF0A1628),
                ),
                const SizedBox(width: 8),
                Text(
                  'expertWelcome.cta'.tr,
                  style: const TextStyle(
                    color: Color(0xFF0A1628),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
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

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Text(
      'expertWelcome.footer'.tr,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.45),
        fontSize: 11.5,
        height: 1.4,
      ),
    );
  }
}

// ============================================================================
// Animated golden burst — concentric circles with a pulsing inner glow
// and 4 small "spark" dots that fade in around the center after the
// dialog finishes its entrance.
// ============================================================================
class _Burst extends StatefulWidget {
  const _Burst();

  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gold = SocialTokens.gold;
    return SizedBox(
      width: 130,
      height: 130,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) {
          // 0 .. 1 .. 0 ping-pong (because we repeat(reverse:true)).
          final t = _pulse.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer halo ring — barely visible, breathes with the pulse.
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: gold.withValues(alpha: 0.04 + (0.06 * t)),
                ),
              ),
              // Mid ring with a thin gold stroke.
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: gold.withValues(alpha: 0.10),
                  border: Border.all(
                    color: gold.withValues(alpha: 0.30 + (0.20 * t)),
                    width: 1.2,
                  ),
                ),
              ),
              // Inner solid gold gradient with the check.
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFFFFE680), Color(0xFFFFD700)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: gold.withValues(alpha: 0.45 + (0.20 * t)),
                      blurRadius: 24,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 38,
                  color: Color(0xFF0A1628),
                ),
              ),
              // 4 spark dots at NE, SE, SW, NW — pulse opposite to the
              // halo for a "breathing" feel.
              ..._sparkPositions.map(
                (pos) => Positioned(
                  left: pos.$1,
                  top: pos.$2,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: gold.withValues(alpha: 0.30 + (0.50 * (1 - t))),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Position offsets for the four spark dots, measured from the top-left of
  // the 130×130 SizedBox.
  static const List<(double, double)> _sparkPositions = [
    (12, 18),
    (113, 18),
    (12, 107),
    (113, 107),
  ];
}
