import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../screens/social/community_detail_screen.dart';
import '../../screens/social/expert_profile_screen.dart';
import '../../screens/social/mock_social_data.dart';
import '../../screens/social/social_tokens.dart';

/// Source-attribution pill rendered on reels, posts, and videos.
///
/// Tells the viewer at a glance whether the content came from:
///
///   * a community (region-tinted, globe icon, "From [region] community")
///   * an expert's personal profile (cyan, person icon, "From [expert]")
///
/// Tap opens the source's detail screen — community detail or
/// expert profile — using the static helpers each screen exposes.
/// Falls back to a neutral "from a member" rendering when neither
/// metadata pair is populated (defensive against partial backend
/// payloads).
///
/// Two sizes:
///   * [SourceBadge.large]   — used on full-screen surfaces
///                              (reels player, post detail).
///   * [SourceBadge.compact] — used on feed cards / list rows.
class SourceBadge extends StatelessWidget {
  /// "expert" → expert profile; "community" → community.
  /// Anything else → renders the neutral fallback.
  final String targetType;

  // Community-source fields (relevant when targetType == 'community')
  final String? communityId;
  final String communityName;
  final String communityRegionCode;

  // Expert-source fields (relevant when targetType == 'expert')
  final String? expertId;
  final String expertName;

  /// True for the larger full-screen variant. Cards use the compact
  /// variant.
  final bool large;

  const SourceBadge({
    super.key,
    required this.targetType,
    this.communityId,
    this.communityName = '',
    this.communityRegionCode = '',
    this.expertId,
    this.expertName = '',
    this.large = false,
  });

  /// Convenience constructor for the larger variant used on
  /// reels + post detail.
  const SourceBadge.large({
    super.key,
    required this.targetType,
    this.communityId,
    this.communityName = '',
    this.communityRegionCode = '',
    this.expertId,
    this.expertName = '',
  }) : large = true;

  /// Compact variant used inside feed cards.
  const SourceBadge.compact({
    super.key,
    required this.targetType,
    this.communityId,
    this.communityName = '',
    this.communityRegionCode = '',
    this.expertId,
    this.expertName = '',
  }) : large = false;

  /// Region → flag emoji, mirrors the same set used by the
  /// community-message snackbar so the visual language stays
  /// consistent across surfaces.
  static const Map<String, String> _regionEmoji = {
    'US': '🇺🇸',
    'GCC': '🇸🇦',
    'MENA': '🌐',
    'EU': '🇪🇺',
    'ASIA': '🌏',
    'CN': '🇨🇳',
    'GLOBAL': '🌍',
  };

  bool get _isCommunity =>
      targetType == 'community' ||
      (communityId != null && communityId!.isNotEmpty);

  bool get _isExpert =>
      targetType == 'expert' ||
      (expertId != null && expertId!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    if (_isCommunity) {
      return _CommunityVariant(
        communityId: communityId ?? '',
        communityName:
            communityName.isEmpty ? 'sourceBadge.communityFallback'.tr : communityName,
        regionCode: communityRegionCode,
        regionEmoji: _regionEmoji[communityRegionCode] ?? '🌐',
        palette: palette,
        large: large,
      );
    }
    if (_isExpert) {
      return _ExpertVariant(
        expertId: expertId ?? '',
        expertName: expertName.isEmpty ? 'sourceBadge.expertFallback'.tr : expertName,
        palette: palette,
        large: large,
      );
    }
    // Neutral fallback — should rarely trigger in practice. Stays
    // visually quiet so it doesn't draw the eye when source is
    // unknown.
    return _NeutralVariant(palette: palette, large: large);
  }
}

class _CommunityVariant extends StatelessWidget {
  final String communityId;
  final String communityName;
  final String regionCode;
  final String regionEmoji;
  final SocialPalette palette;
  final bool large;

  const _CommunityVariant({
    required this.communityId,
    required this.communityName,
    required this.regionCode,
    required this.regionEmoji,
    required this.palette,
    required this.large,
  });

  @override
  Widget build(BuildContext context) {
    final tint = regionCode.isEmpty
        ? SocialTokens.cyan
        : SocialTokens.regionColor(regionCode);
    return _BadgeShell(
      tint: tint,
      palette: palette,
      large: large,
      onTap: () => _openCommunity(context),
      leading: Text(
        regionEmoji,
        style: TextStyle(fontSize: large ? 14 : 12),
      ),
      lines: [
        // Top line — small caps "FROM" + region tag
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'sourceBadge.from'.tr,
              style: TextStyle(
                color: palette.textMuted,
                fontWeight: FontWeight.w900,
                fontSize: large ? 9.5 : 8.5,
                letterSpacing: 0.8,
              ),
            ),
            if (regionCode.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                regionCode,
                style: TextStyle(
                  color: tint,
                  fontWeight: FontWeight.w900,
                  fontSize: large ? 9.5 : 8.5,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ],
        ),
        // Bottom line — community name in tint color
        Text(
          communityName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tint,
            fontWeight: FontWeight.w900,
            fontSize: large ? 12.5 : 11,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }

  void _openCommunity(BuildContext context) {
    if (communityId.isEmpty) return;
    HapticFeedback.selectionClick();
    Community? c;
    for (final entry in MockSocialData.communities) {
      if (entry.id == communityId) {
        c = entry;
        break;
      }
    }
    if (c == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('sourceBadge.communityUnavailable'.tr),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityDetailScreen(community: c!),
      ),
    );
  }
}

class _ExpertVariant extends StatelessWidget {
  final String expertId;
  final String expertName;
  final SocialPalette palette;
  final bool large;

  const _ExpertVariant({
    required this.expertId,
    required this.expertName,
    required this.palette,
    required this.large,
  });

  @override
  Widget build(BuildContext context) {
    const tint = SocialTokens.cyan;
    return _BadgeShell(
      tint: tint,
      palette: palette,
      large: large,
      onTap: () {
        if (expertId.isEmpty) return;
        ExpertProfileScreen.openForExpertId(context, expertId);
      },
      leading: Icon(
        Icons.person_rounded,
        size: large ? 14 : 12,
        color: tint,
      ),
      lines: [
        Text(
          'sourceBadge.fromProfile'.tr,
          style: TextStyle(
            color: palette.textMuted,
            fontWeight: FontWeight.w900,
            fontSize: large ? 9.5 : 8.5,
            letterSpacing: 0.8,
          ),
        ),
        Text(
          expertName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tint,
            fontWeight: FontWeight.w900,
            fontSize: large ? 12.5 : 11,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

class _NeutralVariant extends StatelessWidget {
  final SocialPalette palette;
  final bool large;
  const _NeutralVariant({required this.palette, required this.large});

  @override
  Widget build(BuildContext context) {
    return _BadgeShell(
      tint: palette.textMuted,
      palette: palette,
      large: large,
      onTap: null,
      leading: Icon(
        Icons.person_outline_rounded,
        size: large ? 14 : 12,
        color: palette.textMuted,
      ),
      lines: [
        Text(
          'sourceBadge.from'.tr,
          style: TextStyle(
            color: palette.textMuted,
            fontWeight: FontWeight.w900,
            fontSize: large ? 9.5 : 8.5,
            letterSpacing: 0.8,
          ),
        ),
        Text(
          'sourceBadge.aMember'.tr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: large ? 12.5 : 11,
          ),
        ),
      ],
    );
  }
}

/// Common visual shell — keeps both variants pixel-aligned with the
/// same padding, radius, border, and shadow treatment.
class _BadgeShell extends StatelessWidget {
  final Color tint;
  final SocialPalette palette;
  final bool large;
  final VoidCallback? onTap;
  final Widget leading;
  final List<Widget> lines;

  const _BadgeShell({
    required this.tint,
    required this.palette,
    required this.large,
    required this.onTap,
    required this.leading,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    final padH = large ? 10.0 : 8.0;
    final padV = large ? 6.0 : 4.0;
    final radius = large ? 12.0 : 10.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          padding: EdgeInsets.fromLTRB(padH, padV, padH + 2, padV),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1726).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: tint.withValues(alpha: 0.45),
              width: large ? 0.9 : 0.7,
            ),
            boxShadow: [
              BoxShadow(
                color: tint.withValues(alpha: 0.18),
                blurRadius: large ? 10 : 6,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: large ? 180 : 140,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: lines,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
