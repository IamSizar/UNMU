import 'package:flutter/material.dart';
import '../directional_icon.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../screens/social/social_tokens.dart';

/// =============================================================================
/// Banner / Sponsored card.
///
/// Cyan-accented insight card. The previous gold treatment looked washed out
/// on light backgrounds (yellow-on-near-white) and disappeared in dark mode
/// behind the gradient — cyan reads cleanly in both themes and matches the
/// rest of the app's brand language.
/// =============================================================================
class BannerAdWidget extends StatelessWidget {
  const BannerAdWidget({super.key});

  // Single accent used throughout this card. Easy to swap if you ever
  // want to A/B-test a different color.
  static const Color _accent = SocialTokens.cyan;

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: palette.cardShadow(accent: _accent),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            // Hook up real ad URL when ready.
          },
          borderRadius: BorderRadius.circular(20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                gradient: palette.cardGradient(),
                borderRadius: BorderRadius.circular(20),
                border: palette.highlightedBorder(accent: _accent),
              ),
              child: Stack(
                children: [
                  // Decorative cyan orb in the corner — fades into the card
                  Positioned(
                    right: -32,
                    top: -32,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _accent.withValues(
                              alpha: palette.isDark ? 0.20 : 0.12,
                            ),
                            _accent.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // SPONSORED pill row
                      Row(
                        children: [
                          _SponsoredPill(
                            palette: palette,
                            accent: _accent,
                            label: 'ad.sponsored'.tr,
                          ),
                          const Spacer(),
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: palette.surfaceElevated,
                              shape: BoxShape.circle,
                              border: Border.all(color: palette.border),
                            ),
                            child: Icon(
                              Icons.arrow_outward_rounded,
                              size: 14,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Cyan icon tile
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  SocialTokens.cyan,
                                  SocialTokens.cyanSoft,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: _accent.withValues(alpha: 0.40),
                                  blurRadius: 14,
                                  spreadRadius: -2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.insights_rounded,
                              color: Color(0xFF0A1628),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ad.headline'.tr,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    letterSpacing: -0.3,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'ad.subtitle'.tr,
                                  style: TextStyle(
                                    color: palette.textMuted,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          // Solid cyan-gradient CTA — strong contrast in both modes
                          Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  SocialTokens.cyan,
                                  SocialTokens.cyanSoft,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: _accent.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  spreadRadius: -2,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'ad.learnMore'.tr,
                                  style: const TextStyle(
                                    color: Color(0xFF0A1628),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const DirectionalIcon(
                                  Icons.arrow_forward_rounded,
                                  color: Color(0xFF0A1628),
                                  size: 13,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Trust badge — neutral chip, distinct from the CTA
                          _trustBadge(
                            palette,
                            icon: Icons.shield_outlined,
                            label: 'ad.trusted'.tr,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _trustBadge(
    SocialPalette palette, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.subtleDivider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: palette.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: palette.textMuted,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// SPONSORED pill — outlined cyan capsule with sparkle icon.
class _SponsoredPill extends StatelessWidget {
  final SocialPalette palette;
  final Color accent;
  final String label;
  const _SponsoredPill({
    required this.palette,
    required this.accent,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: palette.isDark ? 0.20 : 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: accent.withValues(alpha: palette.isDark ? 0.55 : 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 11, color: accent),
          const SizedBox(width: 4),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 9.5,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
