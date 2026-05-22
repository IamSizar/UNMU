import 'package:flutter/material.dart';

import '../../screens/social/mock_social_data.dart';
import '../../screens/social/social_tokens.dart';

/// Two-tier verification badge:
///   - cyan circle  -> Verified (standard)
///   - gold star    -> Shariah Scholar (premium tier)
class VerifiedBadge extends StatelessWidget {
  final ExpertTier tier;
  final double size;

  const VerifiedBadge({super.key, required this.tier, this.size = 16});

  @override
  Widget build(BuildContext context) {
    if (tier == ExpertTier.none) return const SizedBox.shrink();

    // SCHOLAR was retired (migration 0013). Verified badge always
    // renders the cyan-checkmark variant now.
    const color = SocialTokens.cyan;
    const icon = Icons.verified;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.20),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: size * 0.6,
            spreadRadius: -1,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.85, color: color),
    );
  }
}
