import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../widgets/social/source_badge.dart';
import 'mock_social_data.dart';
import 'social_tokens.dart';

/// =============================================================================
/// Full-screen TikTok / Instagram-Reels-style player.
///
/// Vertical PageView — one reel per page, full-bleed gradient backdrop,
/// floating right-side action buttons (like / comment / share / save), and
/// bottom-left info row that ALWAYS shows the originating community so the
/// user knows where the reel came from while scrolling.
///
/// Pass [reels] (list of [FeedReel] = reel + its community) and an
/// [initialIndex] — used by entry-point callers like the Social Hub or
/// Community Detail's Reels grid.
/// =============================================================================
class ReelsPlayerScreen extends StatefulWidget {
  final List<FeedReel> reels;
  final int initialIndex;

  const ReelsPlayerScreen({
    super.key,
    required this.reels,
    this.initialIndex = 0,
  });

  @override
  State<ReelsPlayerScreen> createState() => _ReelsPlayerScreenState();
}

class _ReelsPlayerScreenState extends State<ReelsPlayerScreen> {
  late final PageController _ctrl;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.reels.length - 1);
    _ctrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Brand-locked dark experience — stays the same regardless of theme.
      body: Stack(
        children: [
          PageView.builder(
            controller: _ctrl,
            scrollDirection: Axis.vertical,
            itemCount: widget.reels.length,
            onPageChanged: (i) {
              HapticFeedback.selectionClick();
              setState(() => _index = i);
            },
            itemBuilder: (_, i) => _ReelPage(item: widget.reels[i]),
          ),
          // Top: close button + page progress dots
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _circleIcon(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  // Tiny page index indicator (e.g. "3 / 18")
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      '${_index + 1} / ${widget.reels.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const Spacer(),
                  _circleIcon(icon: Icons.more_vert_rounded, onTap: () {}),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleIcon({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

// ============================================================================
// Single reel page — full-bleed gradient + overlay UI
// ============================================================================
class _ReelPage extends StatefulWidget {
  final FeedReel item;
  const _ReelPage({required this.item});

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  bool _liked = false;
  bool _saved = false;
  bool _paused = false;

  @override
  Widget build(BuildContext context) {
    final reel = widget.item.reel;
    final item = widget.item;
    final hue = (reel.thumbnailSeed * 47) % 360;
    final base = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.32).toColor();
    final accent2 =
        HSLColor.fromAHSL(1, ((hue + 35) % 360).toDouble(), 0.7, 0.55).toColor();

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _paused = !_paused);
      },
      onDoubleTap: () {
        HapticFeedback.mediumImpact();
        setState(() => _liked = true);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Backdrop "video" — placeholder gradient that imitates a reel frame
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [base, accent2, base],
              ),
            ),
          ),
          // Decorative ambient orbs
          Positioned(
            left: -60,
            top: -60,
            child: _orb(Colors.white.withValues(alpha: 0.10), 220),
          ),
          Positioned(
            right: -40,
            bottom: 80,
            child: _orb(Colors.white.withValues(alpha: 0.08), 160),
          ),
          // Bottom dark scrim for legibility
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                  stops: const [0.30, 0.60, 1.0],
                ),
              ),
            ),
          ),
          // Center play / pause button (also tap-to-toggle)
          IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _paused ? 0.95 : 0.0,
              child: Center(
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.45),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55),
                      width: 1.6,
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
            ),
          ),
          // Right-rail action column
          Positioned(
            right: 12,
            bottom: 110,
            child: Column(
              children: [
                _RailAction(
                  icon: _liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  iconColor: _liked ? SocialTokens.down : Colors.white,
                  label: _formatCount(reel.views ~/ 18 + (_liked ? 1 : 0)),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _liked = !_liked);
                  },
                ),
                const SizedBox(height: 14),
                _RailAction(
                  icon: Icons.mode_comment_outlined,
                  label: _formatCount(reel.views ~/ 60),
                  onTap: () {},
                ),
                const SizedBox(height: 14),
                _RailAction(
                  icon: Icons.send_outlined,
                  label: 'reels.share'.tr,
                  onTap: () {},
                ),
                const SizedBox(height: 14),
                _RailAction(
                  icon: _saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  iconColor:
                      _saved ? SocialTokens.gold : Colors.white,
                  label: _saved ? 'reels.saved'.tr : 'reels.save'.tr,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _saved = !_saved);
                  },
                ),
              ],
            ),
          ),
          // Bottom info row — community badge + title + views
          Positioned(
            left: 16,
            right: 88, // leave space for the right rail
            bottom: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SourceBadge.large(
                  targetType: item.source == ReelSource.community
                      ? 'community'
                      : 'expert',
                  communityId: item.community?.id,
                  communityName: item.community?.name ?? '',
                  communityRegionCode: item.community?.regionCode ?? '',
                  expertId: item.expert?.id,
                  expertName: item.expert?.name ?? '',
                ),
                const SizedBox(height: 10),
                Text(
                  reel.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: -0.2,
                    height: 1.3,
                    shadows: [
                      Shadow(color: Colors.black54, blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.visibility_outlined,
                      size: 13,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatCount(reel.views)} ${'reels.viewsSuffix'.tr}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      reel.duration,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _orb(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
      ),
    ),
  );

  String _formatCount(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

// ============================================================================
// Right-rail action button (like / comment / share / save)
// ============================================================================
class _RailAction extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _RailAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.40),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Discriminator for where a reel originated. Drives the source
/// badge variant in the player — community-source uses the
/// region-tinted community badge, expert-source uses the cyan
/// expert badge.
enum ReelSource { community, expert }

/// Wrapper that pairs a reel with its source. Exactly one of
/// [community] or [expert] is non-null, mirroring [source]. The
/// player's source-badge widget renders the right variant based on
/// these.
class FeedReel {
  final ExpertReel reel;
  final ReelSource source;
  final Community? community;
  final Expert? expert;
  const FeedReel({
    required this.reel,
    required this.source,
    this.community,
    this.expert,
  });

  /// Convenience constructor for community-source reels — keeps
  /// the older callsites readable without forcing them to spell
  /// out the discriminator.
  factory FeedReel.fromCommunity(ExpertReel r, Community c) =>
      FeedReel(reel: r, source: ReelSource.community, community: c);

  /// Convenience constructor for expert-source reels.
  factory FeedReel.fromExpert(ExpertReel r, Expert e) =>
      FeedReel(reel: r, source: ReelSource.expert, expert: e);
}

/// Aggregate every reel from every community + every expert profile
/// into one flat list, with each entry tagged by its source so the
/// player can render the right "from ..." badge.
///
/// Sort: community reels first (sorted by community active count),
/// then expert-profile reels (sorted by expert subscriber count).
/// Within each bucket, the original ordering is preserved so a
/// curated reel still shows up where the data placed it.
/// Sprint-B step 19 — aggregator returns an empty list now. The old
/// version read from `MockSocialData.communities/.experts[].reels`
/// (mock fixtures). We don't have a real reels backend feed yet, and
/// the user-visible mandate is "no fake data", so the reels rail
/// renders empty until a real source exists.
///
/// The shape stays the same so callers (`feed_screen._PostsTab`
/// reel rail, `_ReelsTab` grid, community-detail reels tab) keep
/// compiling. They all already guard `reels.isEmpty` (or will after
/// this commit).
List<FeedReel> aggregateAllReels() {
  return const <FeedReel>[];
}
