import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../models/expert_post.dart' as backend;
import '../../localization/locale_format.dart';
import '../../services/feed_service.dart';
import 'full_chat_screen.dart';
import 'mock_social_data.dart';
import 'post_detail_screen.dart';
import 'reels_player_screen.dart'
    show FeedReel, ReelsPlayerScreen, aggregateAllReels;
import 'social_tokens.dart';
import 'video_player_screen.dart';

/// =============================================================================
/// Discover hub — 4-tab Instagram-style feed across all communities.
///
///   ┌──────────────────────────────────────────┐
///   │  ←  Discover                       🔔    │ AppBar
///   │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
///   │  [Posts] · Reels · Videos · Chats        │ TabBar (cyan indicator)
///   ├──────────────────────────────────────────┤
///   │                                          │
///   │   …content for the active tab…           │
///   │                                          │
///   └──────────────────────────────────────────┘
///
/// Tabs:
///   ▸ Posts  — Instagram-style cards from every community, tagged with the
///              source community's region tile + name
///   ▸ Reels  — TikTok-style 2-col grid; tap any tile to launch the full-
///              screen vertical-swipe player
///   ▸ Videos — Vertical feed of long-form videos with masterclass/duration
///              badges + community attribution
///   ▸ Chats  — Per-community chat-room previews with last message snippet,
///              tap to enter that community's Chats tab
/// =============================================================================
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  int _lastIndex = 0;

  @override
  void initState() {
    super.initState();
    // Posts only — Reels / Videos / Chats are hidden in this build per the
    // current product scope. Keeping the widgets in code so we can flip them
    // back on by changing this length to 4.
    _tab = TabController(length: 1, vsync: this);
    _tab.addListener(() {
      if (_tab.index != _lastIndex) {
        HapticFeedback.selectionClick();
        _lastIndex = _tab.index;
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'feedScreen.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
        actions: [
          IconButton(
            icon: Icon(
              Icons.notifications_none_rounded,
              color: palette.textPrimary,
            ),
            onPressed: () {},
          ),
          const SizedBox(width: 4),
        ],
        // Tab bar hidden — only one tab in this build.
      ),
      body: const _PostsTab(),
    );
  }
}

// ============================================================================
// Tab 1 — POSTS feed
// ============================================================================
class _PostsTab extends StatefulWidget {
  const _PostsTab();

  @override
  State<_PostsTab> createState() => _PostsTabState();
}

class _PostsTabState extends State<_PostsTab>
    with AutomaticKeepAliveClientMixin {
  // Sprint-B step 14 — posts come from the real `/api/me/feed`
  // endpoint (subscriber feed of expert posts) instead of being
  // aggregated from `MockSocialData.communities[].posts`. The
  // existing `_FeedPostCard` widget expects mock-shaped Community+
  // CommunityPost objects, so we adapt the backend `ExpertPost`
  // rows into those shapes at fetch time.
  List<FeedPost> _posts = const [];
  bool _loading = true;
  String? _error;
  late final List<FeedReel> _reels;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reels = aggregateAllReels();
    _load();
  }

  Future<void> _load() async {
    final fresh = await FeedService.myFeed(limit: 50);
    if (!mounted) return;
    if (fresh == null) {
      setState(() {
        _loading = false;
        _error = 'feedScreen.feedLoadError'.tr;
      });
      return;
    }
    setState(() {
      _loading = false;
      _error = null;
      _posts = fresh.map(_adaptToFeedPost).toList();
    });
  }

  /// Convert a backend `ExpertPost` (target=expert or target=community)
  /// into the mock-shaped `FeedPost` the card was originally built for.
  /// Community context is filled with the post's own community fields
  /// when present, otherwise we synthesize a "from expert profile"
  /// placeholder so the header still has a name + region pill.
  FeedPost _adaptToFeedPost(backend.ExpertPost p) {
    final author = p.authorName.isNotEmpty ? p.authorName : 'Expert';
    final ticker = p.tickers.isNotEmpty ? p.tickers.first : '';
    final body = p.body;
    // ExpertPost has no `stance` — community posts on the backend do,
    // but it's not exposed here. Default to HOLD so the pill renders
    // neutrally. We'll wire real stance once the backend includes it.
    final timeAgo = _relativeTime(p.createdAt);
    final post = CommunityPost(
      id: p.id.toString(),
      author: author,
      timeAgo: timeAgo,
      title: p.title ?? '',
      body: body,
      ticker: ticker,
      stance: 'HOLD',
      upvotes: p.upvotes + p.likes,
      comments: p.comments,
    );
    // Community header context. For target=community posts we have
    // real values; for target=expert we synthesize a placeholder
    // community keyed off the expert profile.
    final commId = (p.communityId ?? '').isNotEmpty
        ? p.communityId!
        : 'expert:${p.expertId}';
    final commName = p.communityName.isNotEmpty
        ? p.communityName
        : p.expertName.isNotEmpty
            ? p.expertName
            : author;
    final regionCode = p.communityRegionCode.isNotEmpty
        ? p.communityRegionCode
        : 'EX';
    final community = Community(
      id: commId,
      name: commName,
      tagline: '',
      regionCode: regionCode,
      memberCount: 0,
      activeNow: 0,
      liveTickers: const [],
      chatMessages: const [],
      posts: const [],
      reels: const [],
      videos: const [],
      ownerId: null,
    );
    return FeedPost(post: post, community: community);
  }

  static String _relativeTime(DateTime t) => LocaleFormat.relative(t);

  void _openReel(int index) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ReelsPlayerScreen(
          reels: _reels,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = SocialTheme.of(context);
    if (_loading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator.adaptive(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
        // +1 for the top reels rail; +1 for the error banner if any
        itemCount: _posts.length + 1 + (_error == null ? 0 : 1),
        itemBuilder: (_, i) {
          if (i == 0) {
            return _ReelsRail(
              reels: _reels,
              palette: palette,
              onTap: _openReel,
            );
          }
          if (_error != null && i == 1) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: palette.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: palette.textMuted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          if (_posts.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
              child: Center(
                child: Text(
                  'feedScreen.emptySubscribe'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }
          final offset = 1 + (_error == null ? 0 : 1);
          final feedPost = _posts[i - offset];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => PostDetailScreen(
                      post: feedPost.post,
                      community: feedPost.community,
                    ),
                  ),
                );
              },
              child: _FeedPostCard(
                feedPost: feedPost,
                palette: palette,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// Tab 2 — REELS grid
// ============================================================================
class _ReelsTab extends StatefulWidget {
  const _ReelsTab();

  @override
  State<_ReelsTab> createState() => _ReelsTabState();
}

class _ReelsTabState extends State<_ReelsTab>
    with AutomaticKeepAliveClientMixin {
  late final List<FeedReel> _reels;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reels = aggregateAllReels();
  }

  void _openAt(int index) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            ReelsPlayerScreen(reels: _reels, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 9 / 14,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _reels.length,
      itemBuilder: (_, i) =>
          _ReelGridCell(feedReel: _reels[i], onTap: () => _openAt(i)),
    );
  }
}

// ============================================================================
// Tab 3 — VIDEOS feed
// ============================================================================
class _VideosTab extends StatefulWidget {
  const _VideosTab();

  @override
  State<_VideosTab> createState() => _VideosTabState();
}

class _VideosTabState extends State<_VideosTab>
    with AutomaticKeepAliveClientMixin {
  late final List<FeedVideo> _videos;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _videos = _aggregateVideos();
  }

  List<FeedVideo> _aggregateVideos() {
    final out = <FeedVideo>[];
    final sorted = [...MockSocialData.communities]
      ..sort((a, b) => b.activeNow.compareTo(a.activeNow));
    for (final c in sorted) {
      for (final v in c.videos) {
        out.add(FeedVideo(video: v, community: c));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = SocialTheme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: _videos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final feedVideo = _videos[i];
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => VideoPlayerScreen(
                  video: feedVideo.video,
                  community: feedVideo.community,
                ),
              ),
            );
          },
          child: _FeedVideoCard(feedVideo: feedVideo, palette: palette),
        );
      },
    );
  }
}

// ============================================================================
// Tab 4 — CHATS list
// ============================================================================
class _ChatsTab extends StatefulWidget {
  const _ChatsTab();

  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab>
    with AutomaticKeepAliveClientMixin {
  late final List<ChatPreview> _previews;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _previews = MockSocialData.communities.map((c) {
      return ChatPreview(
        community: c,
        lastMessage: c.chatMessages.isNotEmpty ? c.chatMessages.last : null,
      );
    }).toList()
      // Most-active rooms first.
      ..sort((a, b) => b.community.activeNow.compareTo(a.community.activeNow));
  }

  void _openCommunity(Community c) {
    HapticFeedback.lightImpact();
    // Open the dedicated full-screen chat (no header card, no chart, no
    // tabs — just messages + input).
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FullChatScreen(community: c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final palette = SocialTheme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: _previews.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final p = _previews[i];
        return _ChatPreviewTile(
          preview: p,
          palette: palette,
          onTap: () => _openCommunity(p.community),
        );
      },
    );
  }
}

// ============================================================================
// Reels rail (used at the top of the Posts tab)
// ============================================================================
class _ReelsRail extends StatelessWidget {
  final List<FeedReel> reels;
  final SocialPalette palette;
  final ValueChanged<int> onTap;

  const _ReelsRail({
    required this.reels,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Sprint-B step 19 — hide the rail entirely when there are no
    // reels. We don't have a real reels feed yet; mock reels are now
    // empty (see aggregateAllReels). The empty rail used to render
    // the "REELS" header on top of an empty horizontal strip, which
    // looked broken.
    if (reels.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Row(
              children: [
                Text(
                  'feedScreen.reelsHeader'.tr,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: SocialTokens.cyan.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '${reels.length}',
                    style: const TextStyle(
                      color: SocialTokens.cyan,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'feedScreen.watchAll'.tr,
                  style: TextStyle(
                    color: SocialTokens.cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: reels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final r = reels[i];
                return _ReelRailTile(feedReel: r, onTap: () => onTap(i));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReelRailTile extends StatelessWidget {
  final FeedReel feedReel;
  final VoidCallback onTap;

  const _ReelRailTile({required this.feedReel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final reel = feedReel.reel;
    // Source-aware accent — community uses its region color, expert
    // (or unknown) falls back to cyan.
    final accent = feedReel.community != null
        ? SocialTokens.regionColor(feedReel.community!.regionCode)
        : SocialTokens.cyan;
    final hue = (reel.thumbnailSeed * 47) % 360;
    final base = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.34).toColor();
    final accent2 =
        HSLColor.fromAHSL(1, ((hue + 35) % 360).toDouble(), 0.7, 0.55).toColor();

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 80,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [base, accent2],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                      stops: const [0.50, 1.0],
                    ),
                  ),
                ),
              ),
              const Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    feedReel.community?.regionCode ?? '',
                    style: const TextStyle(
                      color: Color(0xFF0A1628),
                      fontWeight: FontWeight.w900,
                      fontSize: 9,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Text(
                  reel.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                    height: 1.2,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Reel grid cell — used in the Reels TAB grid
// ============================================================================
class _ReelGridCell extends StatelessWidget {
  final FeedReel feedReel;
  final VoidCallback onTap;
  const _ReelGridCell({required this.feedReel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final reel = feedReel.reel;
    // Source-aware accent — community uses its region color, expert
    // (or unknown) falls back to cyan.
    final accent = feedReel.community != null
        ? SocialTokens.regionColor(feedReel.community!.regionCode)
        : SocialTokens.cyan;
    final hue = (reel.thumbnailSeed * 47) % 360;
    final base = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.34).toColor();
    final accent2 =
        HSLColor.fromAHSL(1, ((hue + 35) % 360).toDouble(), 0.7, 0.55).toColor();

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [base, accent2],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                    stops: const [0.45, 1.0],
                  ),
                ),
              ),
            ),
            const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  feedReel.community?.regionCode ?? '',
                  style: const TextStyle(
                    color: Color(0xFF0A1628),
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  reel.duration,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reel.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                      height: 1.2,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Feed video card — vertical list cell used in the Videos tab
// ============================================================================
class _FeedVideoCard extends StatelessWidget {
  final FeedVideo feedVideo;
  final SocialPalette palette;
  const _FeedVideoCard({required this.feedVideo, required this.palette});

  @override
  Widget build(BuildContext context) {
    final v = feedVideo.video;
    final c = feedVideo.community;
    final accent = SocialTokens.regionColor(c.regionCode);
    final hue = (v.thumbnailSeed * 47) % 360;
    final base = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.34).toColor();
    final accent2 =
        HSLColor.fromAHSL(1, ((hue + 35) % 360).toDouble(), 0.7, 0.55).toColor();

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow(accent: accent),
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
                      colors: [base, accent2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
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
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 1.6,
                      ),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: _CommunityChip(community: c, accent: accent),
                ),
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
                          v.duration,
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
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    height: 1.3,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  v.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 13,
                      color: palette.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_compact(v.views)} ${'feedScreen.viewsSuffix'.tr}',
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '· ${v.publishedAgo}',
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
    );
  }

  String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

// ============================================================================
// Community chip — used as overlay on the video thumbnail
// ============================================================================
class _CommunityChip extends StatelessWidget {
  final Community community;
  final Color accent;
  const _CommunityChip({required this.community, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 4, 8, 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [accent, accent.withValues(alpha: 0.55)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Text(
              community.regionCode.substring(0, 1),
              style: const TextStyle(
                color: Color(0xFF0A1628),
                fontWeight: FontWeight.w900,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            community.regionCode,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Chat preview tile — list cell used in the Chats tab
// ============================================================================
class _ChatPreviewTile extends StatelessWidget {
  final ChatPreview preview;
  final SocialPalette palette;
  final VoidCallback onTap;
  const _ChatPreviewTile({
    required this.preview,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = preview.community;
    final last = preview.lastMessage;
    final accent = SocialTokens.regionColor(c.regionCode);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              // Region tile + active dot
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      gradient: LinearGradient(
                        colors: [accent, accent.withValues(alpha: 0.55)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      c.regionCode,
                      style: const TextStyle(
                        color: Color(0xFF0A1628),
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: SocialTokens.up,
                        border: Border.all(
                          color: palette.surface,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Name + last message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 14.5,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          last?.timeAgo ?? '',
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            last == null
                                ? 'feedScreen.noMessages'.tr
                                : '${last.author}: ${last.body}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Active-now badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: SocialTokens.up.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.bolt_rounded,
                                size: 10,
                                color: SocialTokens.up,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${c.activeNow}',
                                style: const TextStyle(
                                  color: SocialTokens.up,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10,
                                ),
                              ),
                            ],
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
}

// ============================================================================
// Single feed post card (Posts tab)
// ============================================================================
class _FeedPostCard extends StatefulWidget {
  final FeedPost feedPost;
  final SocialPalette palette;
  const _FeedPostCard({required this.feedPost, required this.palette});

  @override
  State<_FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends State<_FeedPostCard> {
  bool _liked = false;
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final post = widget.feedPost.post;
    final community = widget.feedPost.community;
    final palette = widget.palette;
    final accent = SocialTokens.regionColor(community.regionCode);

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
        boxShadow: palette.cardShadow(accent: accent),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PostHeader(
            palette: palette,
            community: community,
            accent: accent,
            author: post.author,
            timeAgo: post.timeAgo,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.title,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: -0.2,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  post.body,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          // Step 27 — hide the stance pill on discussion-style posts.
          // Community posts where the author didn't pick a stock have
          // empty ticker after Sprint-C step 9. Rendering a default
          // "HOLD" pill on those was misleading.
          if (post.ticker.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: _StancePill(ticker: post.ticker, stance: post.stance),
            ),
          _PostActionRow(
            palette: palette,
            liked: _liked,
            saved: _saved,
            upvotes: post.upvotes + (_liked ? 1 : 0),
            comments: post.comments,
            onLike: () {
              HapticFeedback.selectionClick();
              setState(() => _liked = !_liked);
            },
            onComment: () {},
            onShare: () {},
            onSave: () {
              HapticFeedback.selectionClick();
              setState(() => _saved = !_saved);
            },
          ),
        ],
      ),
    );
  }
}

class _PostHeader extends StatelessWidget {
  final SocialPalette palette;
  final Community community;
  final Color accent;
  final String author;
  final String timeAgo;
  const _PostHeader({
    required this.palette,
    required this.community,
    required this.accent,
    required this.author,
    required this.timeAgo,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: LinearGradient(
                colors: [accent, accent.withValues(alpha: 0.55)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              community.regionCode,
              style: const TextStyle(
                color: Color(0xFF0A1628),
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  community.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: SocialTokens.cyan.withValues(alpha: 0.22),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        size: 10,
                        color: SocialTokens.cyan,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    Text(
                      ' · $timeAgo',
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.more_horiz_rounded,
              color: palette.textMuted,
              size: 18,
            ),
            onPressed: () {},
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _StancePill extends StatelessWidget {
  final String ticker;
  final String stance;
  const _StancePill({required this.ticker, required this.stance});

  Color get _color {
    switch (stance.toUpperCase()) {
      case 'BUY':
        return SocialTokens.up;
      case 'SELL':
        return SocialTokens.down;
      default:
        return SocialTokens.gold;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            stance.toUpperCase() == 'BUY'
                ? Icons.trending_up_rounded
                : stance.toUpperCase() == 'SELL'
                    ? Icons.trending_down_rounded
                    : Icons.balance_rounded,
            size: 13,
            color: _color,
          ),
          const SizedBox(width: 6),
          Text(
            '${stance.toUpperCase()}  \$$ticker',
            style: TextStyle(
              color: _color,
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostActionRow extends StatelessWidget {
  final SocialPalette palette;
  final bool liked;
  final bool saved;
  final int upvotes;
  final int comments;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  const _PostActionRow({
    required this.palette,
    required this.liked,
    required this.saved,
    required this.upvotes,
    required this.comments,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.subtleDivider)),
      ),
      child: Row(
        children: [
          _action(
            icon: liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            iconColor: liked ? SocialTokens.down : palette.textSecondary,
            label: '$upvotes',
            onTap: onLike,
          ),
          const SizedBox(width: 4),
          _action(
            icon: Icons.mode_comment_outlined,
            iconColor: palette.textSecondary,
            label: '$comments',
            onTap: onComment,
          ),
          const SizedBox(width: 4),
          _action(
            icon: Icons.send_outlined,
            iconColor: palette.textSecondary,
            label: 'feedScreen.share'.tr,
            onTap: onShare,
          ),
          const Spacer(),
          IconButton(
            onPressed: onSave,
            icon: Icon(
              saved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              color: saved ? SocialTokens.gold : palette.textSecondary,
              size: 20,
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: iconColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Pairing structs — every cross-community feed item carries its source
// ============================================================================
class FeedPost {
  final CommunityPost post;
  final Community community;
  const FeedPost({required this.post, required this.community});
}

class FeedVideo {
  final ExpertVideo video;
  final Community community;
  const FeedVideo({required this.video, required this.community});
}

class ChatPreview {
  final Community community;
  final ChatMessage? lastMessage;
  const ChatPreview({required this.community, required this.lastMessage});
}
