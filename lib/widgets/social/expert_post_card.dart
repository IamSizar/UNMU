import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../screens/social/mock_social_data.dart';
import '../../screens/social/social_tokens.dart';

/// Magazine-style post card used in the Expert Profile "Posts" tab.
///
///   ┌────────────────────────────────────────┐
///   │ ┃ ┌──┐  Author Name           · 2h    │
///   │ ┃ │AB│  Halal ETFs · GCC               │
///   │ ┃ └──┘                                 │
///   │ ┃                                       │
///   │ ┃ Body text goes here, with the         │
///   │ ┃ first line standing out as headline.  │
///   │ ┃                                       │
///   │ ┃ [$SABIC]  [$MAADEN]                  │
///   │ ┃ ──────────────────────────────       │
///   │ ┃ ♡ 412   💬 38   ↗ Share              │
///   └────────────────────────────────────────┘
class ExpertPostCard extends StatelessWidget {
  final ExpertPost post;
  final Color accent; // typically cyan, gold for scholar context
  const ExpertPostCard({
    super.key,
    required this.post,
    this.accent = SocialTokens.cyan,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Container(
      // Outer Container holds the drop-shadow stack so it can render outside
      // the rounded clip below.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: palette.cardShadow(accent: accent),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            gradient: palette.cardGradient(),
            borderRadius: BorderRadius.circular(18),
            border: palette.highlightedBorder(accent: accent),
          ),
          child: Stack(
            children: [
              // Vertical accent stripe
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 4, color: accent),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(palette),
                    const SizedBox(height: 12),
                    Text(
                      post.body,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    if (post.tickers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: post.tickers
                            .map((t) => _tickerChip(t))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(height: 1, color: palette.subtleDivider),
                    const SizedBox(height: 10),
                    _buildActions(palette),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(SocialPalette palette) {
    return Row(
      children: [
        // Squared avatar tile (more editorial than a circle)
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: LinearGradient(
              colors: [accent, accent.withValues(alpha: 0.55)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            _initials(post.authorName),
            style: const TextStyle(
              color: Color(0xFF0A1628),
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      post.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '· ${post.timeAgo}',
                    style: TextStyle(color: palette.textMuted, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              Text(
                'expertProfile.publicPost'.tr,
                style: TextStyle(color: palette.textMuted, fontSize: 10.5),
              ),
            ],
          ),
        ),
        Icon(
          Icons.more_horiz_rounded,
          size: 18,
          color: palette.textMuted,
        ),
      ],
    );
  }

  Widget _tickerChip(String t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: SocialTokens.cyan.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: SocialTokens.cyan.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.show_chart_rounded,
            size: 11,
            color: SocialTokens.cyan,
          ),
          const SizedBox(width: 4),
          Text(
            '\$$t',
            style: const TextStyle(
              color: SocialTokens.cyan,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(SocialPalette palette) {
    return Row(
      children: [
        _action(
          palette,
          icon: Icons.favorite_border_rounded,
          label: '${post.likes}',
        ),
        const SizedBox(width: 18),
        _action(
          palette,
          icon: Icons.mode_comment_outlined,
          label: '${post.comments}',
        ),
        const Spacer(),
        Icon(
          Icons.bookmark_outline_rounded,
          size: 18,
          color: palette.textMuted,
        ),
        const SizedBox(width: 14),
        Icon(
          Icons.share_outlined,
          size: 17,
          color: palette.textMuted,
        ),
      ],
    );
  }

  Widget _action(
    SocialPalette palette, {
    required IconData icon,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: palette.textMuted),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
