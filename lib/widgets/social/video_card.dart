import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../screens/social/mock_social_data.dart';
import '../../screens/social/social_tokens.dart';

/// Full-width video card with a 16:9 hero thumbnail.
///
/// Variants:
///   - Set [featured: true] for the top-of-list "MASTERCLASS" treatment with
///     gold pill, larger play CTA, and a soft accent glow.
///   - Otherwise renders as a standard masterclass card.
class VideoCard extends StatelessWidget {
  final ExpertVideo video;
  final String viewsLabel;
  final bool featured;
  final VoidCallback? onTap;

  const VideoCard({
    super.key,
    required this.video,
    required this.viewsLabel,
    this.featured = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);

    final hue = (video.thumbnailSeed * 47) % 360;
    final base = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.34).toColor();
    final accent =
        HSLColor.fromAHSL(1, ((hue + 35) % 360).toDouble(), 0.7, 0.55).toColor();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: featured
                  ? SocialTokens.gold.withValues(
                      alpha: palette.isDark ? 0.45 : 0.30,
                    )
                  : palette.border,
              width: featured ? 1.4 : 1,
            ),
            boxShadow: featured
                ? [
                    BoxShadow(
                      color: SocialTokens.gold.withValues(alpha: 0.16),
                      blurRadius: 26,
                      spreadRadius: -6,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero thumbnail
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [base, accent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    // Soft scrim at bottom for legibility.
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.45),
                            ],
                            stops: const [0.55, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Floating play CTA
                    Center(
                      child: Container(
                        width: featured ? 72 : 56,
                        height: featured ? 72 : 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.6),
                            width: 1.6,
                          ),
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: featured ? 38 : 28,
                        ),
                      ),
                    ),
                    // MASTERCLASS pill (top-left)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [SocialTokens.gold, SocialTokens.goldSoft],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.workspace_premium_rounded,
                              size: 11,
                              color: Color(0xFF0A1628),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'videoCard.masterclass'.tr,
                              style: const TextStyle(
                                color: Color(0xFF0A1628),
                                fontWeight: FontWeight.w900,
                                fontSize: 9,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Duration chip (top-right)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 11,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              video.duration,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Card body
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: featured ? 16 : 14.5,
                        height: 1.25,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      video.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.visibility_outlined,
                          size: 13,
                          color: palette.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_compact(video.views)} $viewsLabel',
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.access_time_rounded,
                          size: 13,
                          color: palette.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          video.publishedAgo,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.bookmark_outline_rounded,
                          size: 18,
                          color: palette.textMuted,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _compact(int n) {
    if (n < 1000) return n.toString();
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

/// Compact horizontal video row used in community detail's Videos tab.
/// Smaller thumbnail on the left, title + meta on the right.
class CompactVideoRow extends StatelessWidget {
  final ExpertVideo video;
  final String viewsLabel;
  final VoidCallback? onTap;

  const CompactVideoRow({
    super.key,
    required this.video,
    required this.viewsLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final hue = (video.thumbnailSeed * 47) % 360;
    final base = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.34).toColor();
    final accent =
        HSLColor.fromAHSL(1, ((hue + 35) % 360).toDouble(), 0.7, 0.55).toColor();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Container(
                      width: 120,
                      height: 78,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [base, accent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.2),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5),
                              width: 1.2,
                            ),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          video.duration,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.visibility_outlined,
                          size: 11,
                          color: palette.textMuted,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            '${_compact(video.views)} $viewsLabel',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.access_time_rounded,
                          size: 11,
                          color: palette.textMuted,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            video.publishedAgo,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _compact(int n) {
    if (n < 1000) return n.toString();
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}
