import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/expert_profile_controller.dart';
import '../../localization/locale_format.dart';
import '../../controllers/subscription_controller.dart';
import '../../utils/responsive.dart';
import '../../models/expert_post.dart' as live_post;
import '../../models/expert_subscription.dart';
import '../../services/community_service.dart';
import 'community_detail_screen.dart';
import 'expert_paywall_screen.dart';
import '../../widgets/platform_adaptive/platform_dialog.dart';
import '../../widgets/common/app_network_image.dart';
import '../../widgets/social/comment_button.dart';
import '../../widgets/social/like_button.dart';
import '../../widgets/social/save_button.dart';
import '../reels/reel_player_screen.dart';
import '../../widgets/social/price_indicator.dart';
import '../../widgets/social/reel_grid_tile.dart';
import '../../widgets/social/report_sheet.dart';
import '../../widgets/social/sparkline_chart.dart';
import '../../widgets/social/trading_chart.dart';
import '../../widgets/social/verified_badge.dart';
import '../../widgets/social/video_card.dart';
import '../subscriptions/subscribe_modal.dart';
import 'create_post_screen.dart';
import 'mock_social_data.dart';
import 'social_tokens.dart';

/// Expert Profile & Trading Insights screen.
///
/// Layout:
///   ▸ Cinematic hero (avatar with ring, gradient backdrop, stats)
///   ▸ TradingView-style chart (currently-analyzed asset)
///   ▸ Sticky tabs: Posts | Reels | Videos
class ExpertProfileScreen extends StatefulWidget {
  final Expert expert;
  const ExpertProfileScreen({super.key, required this.expert});

  @override
  State<ExpertProfileScreen> createState() => _ExpertProfileScreenState();

  /// Open the profile screen for a given expertId — used by author-avatar
  /// taps on post cards in the feed, reel rail, saved screen, etc.
  ///
  /// Sprint-B step 15 — now async. Fetches the real expert via
  /// `CommunityService.listAllExperts()` and adapts to the mock-shaped
  /// `Expert` the rest of this screen still expects. Falls back to a
  /// polite "Profile not available" snackbar when the backend has no
  /// matching row.
  static Future<void> openForExpertId(BuildContext context, String expertId) async {
    if (expertId.isEmpty) return;
    final res = await CommunityService.listAllExperts();
    if (!context.mounted) return;
    RealExpertRow? real;
    for (final r in (res.experts ?? const <RealExpertRow>[])) {
      if (r.id == expertId) {
        real = r;
        break;
      }
    }
    if (real == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('expertProfile.profileUnavailable'.tr),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    final expert = Expert(
      id: real.id,
      name: real.name,
      handle: '@${real.id}',
      expertise: real.expertise,
      tier: ExpertTier.verified,
      subscriberCount: real.subscriberCount,
      sparkline: const <double>[],
      pctChange: 0,
      currentTicker: '',
      currentPrice: 0,
      currentChangePct: 0,
      shariahGrade: '',
      bio: real.bio,
      posts: const [],
      reels: const [],
      videos: const [],
    );
    HapticFeedback.lightImpact();
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExpertProfileScreen(expert: expert),
      ),
    );
  }
}

class _ExpertProfileScreenState extends State<ExpertProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // Tracks the previous tab index so we can fire a haptic only on real
  // changes (not during the swipe animation's intermediate frames).
  int _lastTabIndex = 0;

  // Per-screen GetX controller — fetches the real posts for this expert and
  // tracks subscription access. Tagged by expertId so multiple profile
  // screens can coexist without their state colliding.
  late final ExpertProfileController _profileCtrl;

  // ── "Communities I'm in" data ────────────────────────────────
  // Loaded once on mount via /api/experts/:id/communities. The
  // strip auto-hides when the list is empty so experts with zero
  // communities don't get an awkward stray header.
  List<Map<String, dynamic>> _communities = const [];
  bool _communitiesLoading = true;

  @override
  void initState() {
    super.initState();
    // Four type-filtered tabs: All / Articles / Videos / Reels — match
    // the Feed dropdown so users have a familiar pivot here too.
    _tab = TabController(length: 4, vsync: this);
    _tab.addListener(() {
      if (_tab.index != _lastTabIndex) {
        HapticFeedback.selectionClick();
        _lastTabIndex = _tab.index;
      }
    });
    // Pull the latest subscription status for THIS expert so the Subscribe
    // button renders the right state on entry. Realtime updates kick in
    // after the first fetch.
    Get.find<SubscriptionController>().refreshExpert(widget.expert.id);
    // Per-screen profile controller — owns posts list + subscribed flag.
    _profileCtrl = Get.put(
      ExpertProfileController(expertId: widget.expert.id),
      tag: widget.expert.id,
    );
    _loadCommunities();
  }

  /// One-shot fetch on mount. Backend returns owner-first then by
  /// member count — we render in that order. Empty list = strip
  /// is hidden entirely.
  Future<void> _loadCommunities() async {
    final res = await CommunityService.listCommunitiesForExpert(
      widget.expert.id,
    );
    if (!mounted) return;
    setState(() {
      _communities = res.rows ?? const [];
      _communitiesLoading = false;
    });
  }

  /// Push the community detail screen for the tapped strip card.
  /// Sprint-B step 15 — fetch the community via the real backend
  /// (`GET /api/communities/:id` through `CommunityService.getMeta`)
  /// and adapt to the mock-shaped Community the detail screen
  /// expects. Decorative-only fields (tickers, posts, reels, videos,
  /// chat messages) are empty — they're rendered conditionally on
  /// the detail screen and won't crash on empty.
  Future<void> _openCommunityById(BuildContext context, String communityId) async {
    final res = await CommunityService.getMeta(communityId);
    if (!context.mounted) return;
    final meta = res.meta;
    if (meta == null) {
      // Community was hidden/removed by an admin — show a clear modal
      // instead of a transient snackbar.
      await PlatformDialog.show(
        context: context,
        title: 'expertProfile.communityUnavailableTitle'.tr,
        content: 'expertProfile.communityUnavailable'.tr,
        confirmText: 'common.ok'.tr,
      );
      return;
    }
    final c = Community(
      id: meta.id,
      name: meta.name,
      tagline: meta.tagline,
      regionCode: meta.regionCode,
      memberCount: meta.memberCount,
      activeNow: 0,
      liveTickers: const [],
      chatMessages: const [],
      posts: const [],
      reels: const [],
      videos: const [],
      ownerId: meta.ownerId,
    );
    HapticFeedback.lightImpact();
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CommunityDetailScreen(community: c),
      ),
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    Get.delete<ExpertProfileController>(tag: widget.expert.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final e = widget.expert;
    // SCHOLAR retired (mig 0013) — accent is cyan for every expert.
    const accent = SocialTokens.cyan;
    // Wrapped in Obx so a test-account switch (or login/logout) rebuilds the
    // page — without it, the "post on your own profile" FAB stays stale.
    return Obx(() {
    final auth = Get.find<AuthController>();
    auth.userObservable.value; // tracker
    // True only when the logged-in account IS this expert/scholar — so they
    // can post on their own profile.
    final isSelf = auth.user?.expertId == e.id;

    return Scaffold(
      backgroundColor: palette.background,
      // Compose FAB only on your own profile.
      floatingActionButton: isSelf
          ? _ProfileComposeFab(
              accent: accent,
              label: 'expertProfile.newPost'.tr,
              onTap: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => CreatePostScreen.expert(expert: e),
                  ),
                );
                if (created == true && mounted) setState(() {});
              },
            )
          : null,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            backgroundColor: palette.background,
            elevation: 0,
            pinned: true,
            iconTheme: IconThemeData(color: palette.textPrimary),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    e.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.textPrimary),
                  ),
                ),
                const SizedBox(width: 6),
                VerifiedBadge(tier: e.tier, size: 16),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(
                  Icons.share_rounded,
                  color: palette.textPrimary,
                ),
                onPressed: () {},
              ),
              // Overflow menu — for now hosts the "Report user" action.
              // Hidden when the user is viewing their own profile (you
              // can't report yourself; the backend would 400 anyway).
              if (Get.find<AuthController>().user?.expertId != widget.expert.id)
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: palette.textPrimary,
                  ),
                  onSelected: (v) async {
                    if (v != 'report') return;
                    final ok = await ReportSheet.show(
                      context,
                      targetType: 'user',
                      targetId: widget.expert.id,
                      targetLabel: '@${e.name}',
                    );
                    if (ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'expertProfile.reportThanks'.tr,
                          ),
                        ),
                      );
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem<String>(
                      value: 'report',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.flag_outlined,
                            color: Color(0xFFE65A6E),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text('expertProfile.reportUser'.tr),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: _buildHero(palette, e, accent),
          ),
          // ── "Communities I'm in" — horizontal scroll. Hidden
          // when the expert has zero communities (the loader is
          // still in flight on first paint, but renders fine
          // empty until the fetch completes).
          if (!_communitiesLoading && _communities.isNotEmpty)
            SliverToBoxAdapter(
              child: _ExpertCommunitiesStrip(
                communities: _communities,
                accent: accent,
                palette: palette,
                onTap: (id) => _openCommunityById(context, id),
              ),
            ),
          // TradingChart is mock-data-only (no real intraday feed yet).
          // Hide when the adapted expert has no ticker / price data so
          // we don't render a blank chart with default zero values.
          if (e.currentTicker.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: TradingChart(
                  ticker: e.currentTicker,
                  price: e.currentPrice,
                  changePct: e.currentChangePct,
                  shariahGrade: e.shariahGrade,
                  data: MockSocialData.intradayChart(),
                ),
              ),
            ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              palette: palette,
              tabBar: TabBar(
                controller: _tab,
                indicatorColor: accent,
                indicatorWeight: 3,
                labelColor: palette.textPrimary,
                unselectedLabelColor: palette.textMuted,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                isScrollable: false,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.dynamic_feed_rounded, size: 18),
                    iconMargin: const EdgeInsets.only(bottom: 2),
                    text: 'expertProfile.tabAll'.tr,
                  ),
                  Tab(
                    icon: const Icon(Icons.text_snippet_rounded, size: 18),
                    iconMargin: const EdgeInsets.only(bottom: 2),
                    text: 'expertProfile.tabArticles'.tr,
                  ),
                  Tab(
                    icon: const Icon(Icons.smart_display_rounded, size: 18),
                    iconMargin: const EdgeInsets.only(bottom: 2),
                    text: 'expertProfile.tabVideos'.tr,
                  ),
                  Tab(
                    icon: const Icon(Icons.ondemand_video_rounded, size: 18),
                    iconMargin: const EdgeInsets.only(bottom: 2),
                    text: 'expertProfile.tabReels'.tr,
                  ),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tab,
          children: [
            // All / Articles / Videos / Reels — same _LivePostsTab,
            // each instance filters the controller's post list.
            for (final filter in const <live_post.PostType?>[
              null,
              live_post.PostType.article,
              live_post.PostType.video,
              live_post.PostType.reel,
            ])
              _LivePostsTab(
                controller: _profileCtrl,
                expertId: e.id,
                expertName: e.name,
                accent: accent,
                typeFilter: filter,
              ),
          ],
        ),
      ),
    );
    }); // end Obx
  }

  Widget _buildHero(
    SocialPalette palette,
    Expert e,
    Color accent,
  ) {
    final subscribersLabel = 'expertProfile.subscribers'.tr;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        gradient: palette.heroGradient(),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: accent.withValues(alpha: palette.isDark ? 0.45 : 0.30),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: palette.isDark ? 0.18 : 0.10),
            blurRadius: 26,
            spreadRadius: -4,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Soft accent glow
          Positioned(
            right: -50,
            top: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: palette.isDark ? 0.30 : 0.20),
                    accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Watermark sparkline
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 100),
              child: Opacity(
                opacity: palette.isDark ? 0.14 : 0.10,
                child: SparklineChart(
                  data: e.sparkline,
                  height: 60,
                  overrideColor: accent,
                  strokeWidth: 1.6,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar with ring + scholar badge
                    _ProfileAvatar(
                      name: e.name,
                      accent: accent,
                      // SCHOLAR retired (mig 0013) — never premium-styled.
                      isScholar: false,
                      size: 72,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  e.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              VerifiedBadge(tier: e.tier, size: 18),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            e.expertise,
                            style: TextStyle(
                              color: palette.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.people_alt_rounded,
                                size: 13,
                                color: accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${_compact(e.subscriberCount)} '
                                '$subscribersLabel',
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Bio block — expandable when long. Three-line clamp is
                // the Instagram default; tap "more" to read the full bio
                // inline without leaving the screen.
                _ExpandableBio(text: e.bio, palette: palette),
                const SizedBox(height: 14),
                // 3-stat row (Posts / Articles / Subscribers) — driven
                // by the live profile controller's post list, with the
                // mock fallback subscriber count so it always reads.
                _ProfileStatsRow(
                  controller: _profileCtrl,
                  fallbackSubscriberCount: e.subscriberCount,
                  accent: accent,
                  palette: palette,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surfaceElevated,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: palette.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SparklineChart(
                                data: e.sparkline,
                                height: 32,
                              ),
                            ),
                            const SizedBox(width: 8),
                            PriceIndicator(changePct: e.pctChange),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Step-4 button — driven by SubscriptionController so it
                    // reflects pending/active/rejected/none states live.
                    _SubscribeCTA(expertId: e.id, expertName: e.name, accent: accent),
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
    if (n < 1000) return n.toString();
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

// ============================================================================
// Bigger profile avatar reused on the hero
// ============================================================================
class _ProfileAvatar extends StatelessWidget {
  final String name;
  final Color accent;
  final bool isScholar;
  final double size;

  const _ProfileAvatar({
    required this.name,
    required this.accent,
    required this.isScholar,
    this.size = 72,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  accent,
                  accent.withValues(alpha: 0.4),
                  accent,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(3),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
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
                _initials(name),
                style: TextStyle(
                  color: const Color(0xFF0A1628),
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.32,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          if (isScholar)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: size * 0.32,
                height: size * 0.32,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1628),
                  shape: BoxShape.circle,
                  border: Border.all(color: SocialTokens.gold, width: 1.8),
                ),
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: SocialTokens.gold,
                  size: size * 0.20,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

// ============================================================================
// Sticky tab bar delegate (theme-aware)
// ============================================================================
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final SocialPalette palette;
  final TabBar tabBar;
  _TabBarDelegate({required this.palette, required this.tabBar});

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: palette.background,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar || oldDelegate.palette != palette;
}


// ============================================================================
// Tab A: LIVE POSTS — fetched from /api/experts/:id/posts via
// ExpertProfileController. Falls back to mock posts only on first paint
// while the network call is in flight (for accounts that don't actually
// have a real expert row in the DB) so the tab never looks empty.
// ============================================================================
class _LivePostsTab extends StatelessWidget {
  final ExpertProfileController controller;
  final String expertId;
  final String expertName;
  final Color accent;
  /// When set, filters the controller's post list down to a single type
  /// (article / video / reel). null = show everything (the All tab).
  final live_post.PostType? typeFilter;

  const _LivePostsTab({
    required this.controller,
    required this.expertId,
    required this.expertName,
    required this.accent,
    this.typeFilter,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Obx(() {
      // Loading + nothing cached → spinner.
      if (controller.loading && controller.posts.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: CircularProgressIndicator(color: accent),
          ),
        );
      }
      // Filter by type when a typeFilter is active. The All tab
      // (typeFilter == null) keeps the full list.
      final posts = typeFilter == null
          ? controller.posts
          : controller.posts.where((p) => p.postType == typeFilter).toList();

      // Step 29 — the mock-fallback branch was deleted. It only
      // fired when `!controller.fetchedOk && fallbackPosts.isNotEmpty`,
      // and with the Sprint-B adapter, `fallbackPosts` is always
      // empty for real experts, so the branch was effectively dead.
      // For real experts with no posts yet we now always show the
      // honest empty hint below.
      if (posts.isEmpty) {
        return RefreshIndicator.adaptive(
          color: accent,
          onRefresh: controller.reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                child: Center(
                  child: Text(
                    _emptyMessageForFilter(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.textMuted, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return RefreshIndicator.adaptive(
        color: accent,
        onRefresh: controller.reload,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          itemCount: posts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final p = posts[i];
            if (p.isLocked) {
              return _LockedPostCard(
                post: p,
                accent: accent,
                expertId: expertId,
                expertName: expertName,
              );
            }
            return _LivePostCard(post: p, accent: accent);
          },
        ),
      );
    });
  }

  /// Filter-aware empty-state text, so each tab reads naturally.
  String _emptyMessageForFilter() {
    switch (typeFilter) {
      case live_post.PostType.article:
        return 'expertProfile.emptyArticles'.tr;
      case live_post.PostType.video:
        return 'expertProfile.emptyVideos'.tr;
      case live_post.PostType.reel:
        return 'expertProfile.emptyReels'.tr;
      case null:
        return 'expertProfile.emptyPosts'.tr;
    }
  }
}

// ============================================================================
// _LivePostCard — renders one unlocked real ExpertPost. Mirrors the visual
// style of ExpertPostCard (which only knows the mock model) so the live
// list looks consistent with the design language.
// ============================================================================
class _LivePostCard extends StatelessWidget {
  final live_post.ExpertPost post;
  final Color accent;
  const _LivePostCard({required this.post, required this.accent});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Container(
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
                    if (post.title != null && post.title!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        post.title!,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: -0.3,
                          height: 1.3,
                        ),
                      ),
                    ],
                    if (post.body.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        post.body,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                    if (_hasMedia) ...[
                      const SizedBox(height: 12),
                      _buildMedia(palette),
                    ],
                    if (post.tickers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: post.tickers.map(_tickerChip).toList(),
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

  /// True when the post has a renderable cover image OR is a video/reel
  /// (which we always frame in a media box even without an explicit cover).
  bool get _hasMedia {
    final hasCover = post.coverUrl != null && post.coverUrl!.trim().isNotEmpty;
    final isVideoOrReel = post.postType == live_post.PostType.video ||
        post.postType == live_post.PostType.reel;
    return hasCover || isVideoOrReel;
  }

  Widget _buildMedia(SocialPalette palette) {
    final isReel = post.postType == live_post.PostType.reel;
    final isVideo = post.postType == live_post.PostType.video;
    // Reels are vertical (9:16), videos and articles use 16:9.
    final aspect = isReel ? (9 / 16) * 1.6 : 16 / 9;
    final cover = post.coverUrl?.trim() ?? '';
    // Tapping the media area opens the fullscreen player for video/reel
    // posts that have a real mediaUrl. For articles or empty media, no-op.
    final canPlay = (isReel || isVideo) &&
        post.mediaUrl != null &&
        post.mediaUrl!.trim().isNotEmpty;

    final media = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cover.isNotEmpty)
              AppNetworkImage(
                cover,
                fit: BoxFit.cover,
                placeholderColor: palette.surfaceElevated,
                errorWidget: Container(
                  color: palette.surfaceElevated,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: palette.textMuted,
                    size: 32,
                  ),
                ),
              )
            else
              // Video / reel without a cover — solid placeholder so the
              // play button still has a frame to sit on.
              Container(color: palette.surfaceElevated),
            if (isVideo || isReel)
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0A1628).withValues(alpha: 0.55),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.85),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            if (isReel || isVideo)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1628).withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isReel ? 'REEL' : 'VIDEO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            if (post.durationSeconds != null && post.durationSeconds! > 0)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1628).withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatDuration(post.durationSeconds!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!canPlay) return media;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        Get.to(() => ReelPlayerScreen(
              mediaUrl: post.mediaUrl!,
              qualityVariants: post.videoVariants,
              expectedDurationSeconds: post.durationSeconds,
              coverUrl: post.coverUrl,
              title: post.title,
              authorName: post.authorName,
            ));
      },
      child: media,
    );
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildHeader(SocialPalette palette) {
    return Row(
      children: [
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
                      post.authorName.isEmpty
                          ? 'expertProfile.expertFallback'.tr
                          : post.authorName,
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
                    '· ${_relativeTime(post.createdAt)}',
                    style: TextStyle(color: palette.textMuted, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              Text(
                post.visibility == live_post.PostVisibility.subscribersOnly
                    ? 'expertProfile.subscribersPost'.tr
                    : 'expertProfile.publicPost'.tr,
                style: TextStyle(color: palette.textMuted, fontSize: 10.5),
              ),
            ],
          ),
        ),
        Icon(Icons.more_horiz_rounded, size: 18, color: palette.textMuted),
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
        LikeButton(post: post, accent: accent, mutedColor: palette.textMuted),
        const SizedBox(width: 12),
        CommentButton(
            post: post, accent: accent, mutedColor: palette.textMuted),
        const Spacer(),
        SaveButton(post: post, accent: accent, mutedColor: palette.textMuted),
        const SizedBox(width: 8),
        Icon(Icons.share_outlined, size: 17, color: palette.textMuted),
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

  String _relativeTime(DateTime t) => LocaleFormat.relative(t);
}

// ============================================================================
// _LockedPostCard — shown for subscriber-only posts the user can't see yet.
// Renders a teaser (title + cover if any) with a frosted lock + subscribe CTA.
// Tapping the CTA opens the SubscribeModal so the user can pay; once the
// admin accepts, the realtime subscription_active event refreshes this list
// and the card flips into _LivePostCard automatically.
// ============================================================================
class _LockedPostCard extends StatelessWidget {
  final live_post.ExpertPost post;
  final Color accent;
  final String expertId;
  final String expertName;

  const _LockedPostCard({
    required this.post,
    required this.accent,
    required this.expertId,
    required this.expertName,
  });

  void _openPaywall(BuildContext context) {
    HapticFeedback.lightImpact();
    ExpertPaywallScreen.show(
      context,
      expertId: expertId,
      expertName: expertName,
      postTitle: post.title,
      postType: post.postType,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: palette.cardShadow(accent: accent),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openPaywall(context),
            child: Container(
              decoration: BoxDecoration(
                gradient: palette.cardGradient(),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: accent.withValues(
                      alpha: palette.isDark ? 0.45 : 0.30),
                  width: 1.2,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.15),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.5),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.lock_rounded, color: accent, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'expertProfile.subscribersOnly'.tr,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  Text(
                    _typeLabel(post.postType),
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (post.title != null && post.title!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  post.title!,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: -0.3,
                    height: 1.3,
                  ),
                ),
              ],
              if (_lockedHasMedia) ...[
                const SizedBox(height: 12),
                _buildLockedMedia(palette),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'expertProfile.subscribeToRead'
                            .trParams({'name': expertName}),
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        SubscribeModal.show(
                          context,
                          expertId: expertId,
                          expertName: expertName,
                        );
                      },
                      icon: const Icon(Icons.bolt_rounded, size: 16),
                      label: Text(
                        'expertProfile.subscribe'.tr,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: const Color(0xFF0A1628),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _relativeTime(post.createdAt),
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _typeLabel(live_post.PostType t) {
    switch (t) {
      case live_post.PostType.video:
        return 'VIDEO';
      case live_post.PostType.reel:
        return 'REEL';
      case live_post.PostType.article:
        return 'ARTICLE';
    }
  }

  bool get _lockedHasMedia {
    final hasCover = post.coverUrl != null && post.coverUrl!.trim().isNotEmpty;
    final isVideoOrReel = post.postType == live_post.PostType.video ||
        post.postType == live_post.PostType.reel;
    return hasCover || isVideoOrReel;
  }

  Widget _buildLockedMedia(SocialPalette palette) {
    final isReel = post.postType == live_post.PostType.reel;
    final isVideo = post.postType == live_post.PostType.video;
    final aspect = isReel ? (9 / 16) * 1.6 : 16 / 9;
    final cover = post.coverUrl?.trim() ?? '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cover.isNotEmpty)
              AppNetworkImage(
                cover,
                fit: BoxFit.cover,
                placeholderColor: palette.surfaceElevated,
                errorWidget: Container(color: palette.surfaceElevated),
              )
            else
              Container(color: palette.surfaceElevated),
            // Soft frosted overlay so the image reads as "preview only".
            Container(color: Colors.black.withValues(alpha: 0.30)),
            Center(
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.85),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.lock_rounded,
                  color: Color(0xFF0A1628),
                  size: 22,
                ),
              ),
            ),
            if (isReel || isVideo)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1628).withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isReel ? 'REEL' : 'VIDEO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime t) => LocaleFormat.relative(t);
}

// ============================================================================
// Tab B: REELS — TikTok-style 3-column grid with trending ranks for top 3.
// Currently dormant; the expert profile is 1-tab (posts only) until
// reels per-expert are wired back in.
// ============================================================================
// ignore: unused_element
class _ReelsTab extends StatelessWidget {
  final List<ExpertReel> reels;
  const _ReelsTab({required this.reels});

  @override
  Widget build(BuildContext context) {
    final viewsLabel = 'expertProfile.views'.tr;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        // iPad: more columns, same 9:14 tile shape (no aspect glitch).
        crossAxisCount: context.responsive(phone: 3, tablet: 5, large: 6),
        childAspectRatio: 9 / 14,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: reels.length,
      itemBuilder: (_, i) => ReelGridTile(
        reel: reels[i],
        viewsLabel: viewsLabel,
        rank: i + 1, // pass rank so the top 3 get a trending badge
      ),
    );
  }
}

// ============================================================================
// Tab C: VIDEOS — featured masterclass at top + standard list below.
// Same dormant status as the reels tab above.
// ============================================================================
// ignore: unused_element
class _VideosTab extends StatelessWidget {
  final List<ExpertVideo> videos;
  const _VideosTab({required this.videos});

  @override
  Widget build(BuildContext context) {
    final viewsLabel = 'expertProfile.views'.tr;
    if (videos.isEmpty) return const SizedBox.shrink();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: videos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => VideoCard(
        video: videos[i],
        viewsLabel: viewsLabel,
        // First video gets the "FEATURED MASTERCLASS" gold treatment.
        featured: i == 0,
      ),
    );
  }
}

// ============================================================================
// Floating compose button — only shown to the expert/scholar viewing their
// OWN profile. Mirrors the community detail screen's compose pill.
// ============================================================================
class _ProfileComposeFab extends StatelessWidget {
  final Color accent;
  final String label;
  final VoidCallback onTap;
  const _ProfileComposeFab({
    required this.accent,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent, accent.withValues(alpha: 0.6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.45),
              blurRadius: 16,
              spreadRadius: -2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.edit_rounded,
              size: 18,
              color: Color(0xFF0A1628),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF0A1628),
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// _SubscribeCTA — replaces the old toggle button. Reads from the
// SubscriptionController so it reflects pending/active/rejected states
// live (driven by realtime + Phoenix restart on accept).
// ============================================================================
class _SubscribeCTA extends StatelessWidget {
  final String expertId;
  final String expertName;
  final Color accent;
  const _SubscribeCTA({
    required this.expertId,
    required this.expertName,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<SubscriptionController>();
    return Obx(() {
      final sub = ctrl.forExpert(expertId);
      final spec = _spec(sub);
      return ElevatedButton.icon(
        onPressed: spec.disabled
            ? null
            : () async {
                HapticFeedback.lightImpact();
                if (sub == null ||
                    sub.status == SubStatus.cancelled ||
                    sub.status == SubStatus.rejected ||
                    sub.status == SubStatus.expired) {
                  // None / terminal — open the subscribe modal.
                  await SubscribeModal.show(
                    context,
                    expertId: expertId,
                    expertName: expertName,
                  );
                } else if (sub.status == SubStatus.active) {
                  // Active — confirm cancel.
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('expertProfile.cancelSubTitle'.tr),
                      content: Text('expertProfile.cancelSubBody'.tr),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('expertProfile.keep'.tr),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text('common.cancel'.tr),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await ctrl.cancel(sub.id, expertId: expertId);
                  }
                }
                // Pending → no action; the disabled button speaks for itself.
              },
        icon: Icon(spec.icon, size: 18),
        label: Text(
          spec.label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: spec.filled ? accent : Colors.transparent,
          foregroundColor: spec.filled ? Colors.black : accent,
          disabledBackgroundColor: accent.withValues(alpha: 0.12),
          disabledForegroundColor: accent.withValues(alpha: 0.7),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: accent, width: 1.4),
          ),
        ),
      );
    });
  }

  _CTASpec _spec(ExpertSubscription? sub) {
    if (sub == null) {
      return _CTASpec(
          label: 'expertProfile.subscribe'.tr,
          icon: Icons.add_rounded,
          filled: true);
    }
    switch (sub.status) {
      case SubStatus.pending:
        return _CTASpec(
          label: 'expertProfile.pending'.tr,
          icon: Icons.hourglass_top,
          filled: false,
          disabled: true,
        );
      case SubStatus.active:
        return _CTASpec(
            label: 'expertProfile.subscribed'.tr,
            icon: Icons.check_rounded,
            filled: false);
      case SubStatus.rejected:
        return _CTASpec(
            label: 'expertProfile.tryAgain'.tr,
            icon: Icons.refresh_rounded,
            filled: true);
      case SubStatus.cancelled:
      case SubStatus.expired:
        return _CTASpec(
            label: 'expertProfile.subscribe'.tr,
            icon: Icons.add_rounded,
            filled: true);
    }
  }
}

class _CTASpec {
  final String label;
  final IconData icon;
  final bool filled;
  final bool disabled;
  const _CTASpec({
    required this.label,
    required this.icon,
    required this.filled,
    this.disabled = false,
  });
}

// ============================================================================
// _ExpandableBio — three-line clamped bio with an inline "more" link.
// Tap "more" → reveals the full bio with an animated size transition.
// Keeps the hero compact for short bios while letting long ones breathe.
// ============================================================================
class _ExpandableBio extends StatefulWidget {
  final String text;
  final SocialPalette palette;
  const _ExpandableBio({required this.text, required this.palette});

  @override
  State<_ExpandableBio> createState() => _ExpandableBioState();
}

class _ExpandableBioState extends State<_ExpandableBio> {
  bool _expanded = false;

  bool get _likelyClamps =>
      widget.text.length > 130 || '\n'.allMatches(widget.text).length > 1;

  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) return const SizedBox.shrink();
    final palette = widget.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topLeft,
          child: Text(
            widget.text,
            maxLines: _expanded ? null : 3,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
        if (_likelyClamps)
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _expanded
                    ? 'expertProfile.showLess'.tr
                    : 'expertProfile.more'.tr,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// _ProfileStatsRow — 3 columns of bold numbers + labels:
//
//        12          7         2.5K
//       Posts    Articles   Subscribers
//
// Reads `Posts` and `Articles` live from the ExpertProfileController
// (filtered by type). Subscribers comes from the mock data for now —
// no backend endpoint yet for "current subscriber count per expert."
// ============================================================================
class _ProfileStatsRow extends StatelessWidget {
  final ExpertProfileController controller;
  final int fallbackSubscriberCount;
  final Color accent;
  final SocialPalette palette;

  const _ProfileStatsRow({
    required this.controller,
    required this.fallbackSubscriberCount,
    required this.accent,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Obx(() {
        final all = controller.posts;
        final articles =
            all.where((p) => p.postType == live_post.PostType.article).length;
        return Row(
          children: [
            Expanded(
                child: _stat('${all.length}', 'expertProfile.statPosts'.tr)),
            _divider(),
            Expanded(
                child: _stat('$articles', 'expertProfile.statArticles'.tr)),
            _divider(),
            Expanded(
                child: _stat(_compact(fallbackSubscriberCount),
                    'expertProfile.statSubscribers'.tr)),
          ],
        );
      }),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 17,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 28,
      color: palette.border,
    );
  }

  static String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}


// ─── Communities-on-expert-profile strip ───────────────────────────
//
// Horizontal scroll of small community cards rendered on the
// expert profile screen. Owner-first then by member count (server
// already orders this way; we just render). Tap a card to push
// the matching CommunityDetailScreen.
class _ExpertCommunitiesStrip extends StatelessWidget {
  final List<Map<String, dynamic>> communities;
  final Color accent;
  final SocialPalette palette;
  final void Function(String id) onTap;

  const _ExpertCommunitiesStrip({
    required this.communities,
    required this.accent,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.groups_2_rounded, size: 16, color: accent),
                const SizedBox(width: 6),
                Text(
                  'expertProfile.communities'.tr,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${communities.length}',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: communities.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final c = communities[i];
                final id = c['id']?.toString() ?? '';
                final name = c['name']?.toString() ?? '—';
                final regionCode = c['regionCode']?.toString() ?? '';
                final tagline = c['tagline']?.toString() ?? '';
                final memberCount =
                    (c['memberCount'] as num?)?.toInt() ?? 0;
                final tint = regionCode.isEmpty
                    ? accent
                    : SocialTokens.regionColor(regionCode);
                return Material(
                  color: palette.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onTap(id),
                    child: Container(
                      width: 200,
                      padding:
                          const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: tint.withValues(alpha: 0.35),
                          width: 0.7,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tint.withValues(alpha: 0.18),
                                  border: Border.all(
                                    color: tint.withValues(alpha: 0.6),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  name.isEmpty
                                      ? '·'
                                      : name
                                          .substring(0, 1)
                                          .toUpperCase(),
                                  style: TextStyle(
                                    color: tint,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tagline.isEmpty
                                ? 'expertProfile.communityFallback'.tr
                                : tagline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Icon(
                                Icons.people_alt_rounded,
                                size: 11,
                                color: palette.textMuted,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                _compactCount(memberCount),
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10.5,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _compactCount(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    }
    return '$n';
  }
}
