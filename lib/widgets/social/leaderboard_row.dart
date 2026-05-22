import 'package:flutter/material.dart';

import '../../screens/social/mock_social_data.dart';
import '../../screens/social/social_strings.dart';
import '../../screens/social/social_tokens.dart';
import 'shariah_grade_chip.dart';
import 'verified_badge.dart';

/// Magazine-style ranked row used inside the "Top experts this week"
/// leaderboard. Big condensed rank number on the left, expert info in the
/// middle, sparkline + performance % on the right.
class LeaderboardRow extends StatelessWidget {
  final int rank;
  final Expert expert;
  final bool isArabic;
  final VoidCallback? onTap;

  const LeaderboardRow({
    super.key,
    required this.rank,
    required this.expert,
    required this.isArabic,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    // SCHOLAR retired (mig 0013) — every leaderboard row uses cyan now.
    const accent = SocialTokens.cyan;
    final isPodium = rank <= 3;
    final subscribersLabel = isArabic
        ? SocialStrings.subscribersAr
        : SocialStrings.subscribers;

    return Container(
      // Outer Container provides the soft drop-shadow.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: palette.cardShadow(accent: isPodium ? accent : null),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
            decoration: BoxDecoration(
              gradient: palette.cardGradient(),
              borderRadius: BorderRadius.circular(16),
              border: palette.highlightedBorder(
                accent: isPodium ? accent : null,
              ),
            ),
          child: Row(
            children: [
              // Big rank number
              SizedBox(
                width: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isPodium)
                      Positioned.fill(
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                accent.withValues(alpha: 0.20),
                                accent.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Text(
                      rank.toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: isPodium ? accent : palette.textMuted,
                        fontWeight: FontWeight.w900,
                        fontSize: 36,
                        height: 1,
                        letterSpacing: -2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Avatar tile (squared)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.85),
                      accent.withValues(alpha: 0.55),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(expert.name),
                  style: const TextStyle(
                    color: Color(0xFF0A1628),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Name + meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            expert.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        VerifiedBadge(tier: expert.tier, size: 13),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        // ShariahGradeChip is mock-derived (no real source
                        // for per-expert Shariah grade yet) — hide unless
                        // a non-empty grade exists. Real backend data
                        // doesn't populate this, so it stays hidden.
                        if (expert.shariahGrade.isNotEmpty) ...[
                          ShariahGradeChip(grade: expert.shariahGrade, size: 12),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            // The mock-data row used to also prefix the
                            // current ticker the expert was "trading"
                            // (e.g. "ARAMCO · 48K subscribers"). That
                            // ticker is fake; we now show subscribers
                            // only, which is real DB data.
                            '${_compact(expert.subscriberCount)} '
                            '$subscribersLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // (Right-rail sparkline + pctChange was removed — those
              // fields were synthesized from MockSocialData. Once we have
              // real per-expert performance tracking we can re-introduce.)
            ],
          ),
        ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String _compact(int n) {
    if (n < 1000) return n.toString();
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}
