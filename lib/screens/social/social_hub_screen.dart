import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../widgets/directional_icon.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/language_controller.dart';
import '../../controllers/realtime_controller.dart';
import '../../services/community_service.dart';
import '../../services/community_subscription_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/social/community_avatar.dart';
import '../../widgets/social/community_card.dart';
import '../../widgets/social/greeting_hero.dart';
import '../../widgets/social/leaderboard_row.dart';
import 'all_experts_screen.dart';
import 'community_detail_screen.dart';
import 'community_discovery_screen.dart';
import 'community_preview_screen.dart';
import 'expert_profile_screen.dart';
import 'mock_social_data.dart';
import 'social_tokens.dart';

/// Social & Community Hub — editorial bento layout.
///
///   ▸ Marquee ticker tape (auto-scrolling top strip)
///   ▸ Greeting hero ("Good morning, Sizar · Your network +X.X%")
///   ▸ Live stories rail (avatars of experts active today)
///   ▸ Featured expert card (full-width)
///   ▸ Top movers bento (2-col stat tiles)
///   ▸ Top experts this week (numbered leaderboard)
///   ▸ Your communities (vertical bento cards)
///
/// Theme-reactive: all colors flip with the app's brightness setting.
class SocialHubScreen extends StatefulWidget {
  const SocialHubScreen({super.key});

  @override
  State<SocialHubScreen> createState() => _SocialHubScreenState();
}

class _SocialHubScreenState extends State<SocialHubScreen> {
  /// When true the hub shrinks to "communities you've joined or
  /// own" only — Discover is hidden. Default off so first-time
  /// users still see the catalog. Persists for the screen
  /// lifetime; intentionally not saved to prefs to avoid surprising
  /// users on next launch.
  bool _joinedOnly = false;

  /// Step-23 follow-up — real "joined" set fetched from
  /// `/me/communities`. Replaces the mock-data lookup so the pinned
  /// section reflects DB truth (after a kick on free → paid, the
  /// pinned bucket empties immediately on next open).
  Set<String> _realJoinedIds = const <String>{};

  /// Community IDs the current user has a PENDING paid subscription
  /// for (submitted, admin reviewing). Drives the gold "Pending" pill
  /// on the discovery cards. Loaded alongside [_realJoinedIds] and
  /// refreshed on `community_subscription_*` realtime events.
  Set<String> _pendingJoinIds = const <String>{};

  /// Listens to the realtime hub for events that change the join /
  /// pending state of any community card on this screen (the user
  /// just paid, admin approved their payment, etc.). Cancelled in
  /// [dispose].
  StreamSubscription<dynamic>? _membershipSub;

  // Real data fetched from /api/experts and /api/communities. Adapted
  // into mock-shaped objects so the existing widget signatures keep
  // working. Decorative-only fields (sparklines, pctChange, tickers,
  // activeNow, sentiment) are zero/empty in the adapted objects and
  // the widgets now guard against rendering them.
  List<Expert> _experts = const <Expert>[];
  List<Community> _communities = const <Community>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();

    // Realtime — flip card state the moment a community subscription
    // event arrives for the current user:
    //   * community_subscription_submitted → freshly pending, add ID to
    //     _pendingJoinIds so the gold pill appears
    //   * community_subscription_active   → admin approved, move from
    //     pending → joined
    //   * community_subscription_rejected → admin rejected, drop from
    //     pending (button reverts to "+ Join")
    //   * community_subscription_expired  → drop from both sets
    //
    // We listen on the catch-all `events` stream so we don't have to
    // wire 4 separate listeners. The dispatch is cheap (string equality
    // + Set ops) so the cost is negligible.
    final rt = Get.isRegistered<RealtimeController>()
        ? Get.find<RealtimeController>()
        : null;
    _membershipSub = rt?.events.listen(_onMembershipEvent);
  }

  void _onMembershipEvent(dynamic ev) {
    // ev is a `RealtimeEvent` but we treat it as dynamic to avoid
    // coupling the social hub to the realtime model's exact shape —
    // only `type` and `data['communityId']` matter to us.
    final type = (ev as dynamic).type as String? ?? '';
    if (!type.startsWith('community_subscription_')) return;
    final data = ((ev as dynamic).data as Map?) ?? const {};
    final communityId = data['communityId']?.toString();
    if (communityId == null || communityId.isEmpty) return;
    if (!mounted) return;

    setState(() {
      switch (type) {
        case 'community_subscription_submitted':
          _pendingJoinIds = {..._pendingJoinIds, communityId};
          break;
        case 'community_subscription_active':
          _pendingJoinIds = {..._pendingJoinIds}..remove(communityId);
          _realJoinedIds = {..._realJoinedIds, communityId};
          break;
        case 'community_subscription_rejected':
        case 'community_subscription_cancelled':
        case 'community_subscription_expired':
          _pendingJoinIds = {..._pendingJoinIds}..remove(communityId);
          _realJoinedIds = {..._realJoinedIds}..remove(communityId);
          break;
      }
    });
  }

  @override
  void dispose() {
    _membershipSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final results = await Future.wait([
      CommunityService.myCommunityIds(),
      CommunityService.listAllExperts(),
      CommunityService.listAllCommunities(),
      // Pending community subs — drives the gold "Pending" pill state.
      // Fetched here in parallel so the first-paint hub already shows
      // the right card state without a flicker from Join → Pending.
      CommunitySubscriptionService.myPendingCommunityIds(),
    ]);
    if (!mounted) return;
    final ids = results[0] as ({Set<String>? ids, String? error});
    final experts =
        results[1] as ({List<RealExpertRow>? experts, String? error});
    final communities = results[2]
        as ({List<CommunityMeta>? communities, String? error});
    final pending = results[3] as Set<String>;

    setState(() {
      if (ids.ids != null) _realJoinedIds = ids.ids!;
      _pendingJoinIds = pending;
      _experts = (experts.experts ?? const [])
          .map(_adaptExpert)
          .toList();
      _communities = (communities.communities ?? const [])
          .map(_adaptCommunity)
          .toList();
      _loading = false;
    });
    // Surface a non-blocking snackbar if either fetch failed. The page
    // still renders the cached/empty state so the user can scroll.
    final err = experts.error ?? communities.error;
    if (err != null && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
  }

  Future<void> _loadRealJoinedIds() async {
    final res = await CommunityService.myCommunityIds();
    if (!mounted) return;
    if (res.ids != null) {
      setState(() => _realJoinedIds = res.ids!);
    }
  }

  /// Convert a real backend expert row into the mock-Expert shape used
  /// throughout the social UI. Decorative fields (sparkline, pctChange,
  /// currentTicker, shariahGrade, posts/reels/videos) are deliberately
  /// blank/zero — the widgets render them conditionally, so they stay
  /// hidden until we have real data sources for them.
  static Expert _adaptExpert(RealExpertRow r) => Expert(
        id: r.id,
        name: r.name,
        handle: '@${r.id}',
        expertise: r.expertise,
        tier: ExpertTier.verified,
        subscriberCount: r.subscriberCount,
        sparkline: const <double>[],
        pctChange: 0,
        currentTicker: '',
        currentPrice: 0,
        currentChangePct: 0,
        shariahGrade: '',
        bio: r.bio,
        posts: const [],
        reels: const [],
        videos: const [],
      );

  /// Convert a real backend community row into the mock-Community shape.
  /// Decorative fields (liveTickers, activeNow, chatMessages, posts/
  /// reels/videos) are empty/zero so the card stays honest.
  ///
  /// Sprint-C step 8 — passes `ownerId` through so the hub can flag
  /// owned communities with the gold-crown card variant.
  static Community _adaptCommunity(CommunityMeta m) => Community(
        id: m.id,
        name: m.name,
        tagline: m.tagline,
        regionCode: m.regionCode,
        memberCount: m.memberCount,
        activeNow: 0,
        liveTickers: const [],
        chatMessages: const [],
        posts: const [],
        reels: const [],
        videos: const [],
        ownerId: m.ownerId,
        coverUrl: m.coverUrl,
        avatarUrl: m.avatarUrl,
      );

  @override
  Widget build(BuildContext context) {
    // `isArabic` is still needed below: it's forwarded to out-of-scope
    // widgets (GreetingHero, LeaderboardRow, CommunityCard, AllExpertsScreen)
    // that take an explicit isArabic flag. UI-chrome strings owned by this
    // screen use '.tr' directly.
    final isArabic = Get.find<LanguageController>().isArabic;
    final palette = SocialTheme.of(context);
    final title = 'socialHub.title'.tr;

    // Wrap in Obx so the greeting + any role-derived UI rebuilds when the
    // logged-in user changes (test-account switcher, approval flow, etc.).
    return Obx(() {
    final auth = Get.find<AuthController>();
    auth.userObservable.value; // tracker
    final userName = (auth.user?.email.split('@').first ?? 'there');

    final body = SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hp = constraints.maxWidth < 380 ? 14.0 : 18.0;

          return RefreshIndicator(
            onRefresh: _loadAll,
            child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // ─────── Live ticker tape (was marquee of mock prices)
              // Replaced with a "coming soon" pill until we have a real
              // intraday quote feed.
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
                  child: _ComingSoonCard(
                    icon: Icons.show_chart_rounded,
                    title: 'socialHub.liveTickerTitle'.tr,
                    body: 'socialHub.comingSoon'.tr,
                    compact: true,
                  ),
                ),
              ),

              // ─────── greeting hero (sparkline removed) ───────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 16, hp, 0),
                  child: GreetingHero(
                    userName: userName,
                    isArabic: isArabic,
                  ),
                ),
              ),

              // ─────── Stories rail — coming soon ───────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 22, hp, 0),
                  child: _ComingSoonCard(
                    icon: Icons.auto_stories_rounded,
                    title: 'socialHub.liveStoriesTitle'.tr,
                    body: 'socialHub.liveStoriesBody'.tr,
                  ),
                ),
              ),

              // ─────── Featured expert — coming soon ───────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 22, hp, 0),
                  child: _ComingSoonCard(
                    icon: Icons.star_rounded,
                    title: 'socialHub.featuredExpertTitle'.tr,
                    body: 'socialHub.featuredExpertBody'.tr,
                  ),
                ),
              ),

              // ─────── Top movers — coming soon ───────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 22, hp, 0),
                  child: _ComingSoonCard(
                    icon: Icons.trending_up_rounded,
                    title: 'socialHub.topMovers'.tr,
                    body: 'socialHub.topMoversBody'.tr,
                  ),
                ),
              ),

              // ─────── leaderboard (REAL data) ───────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 26, hp, 0),
                  child: _SectionHeader(
                    palette: palette,
                    title: 'socialHub.topExpertsThisWeek'.tr,
                    subtitle: 'socialHub.thisWeek'.tr,
                    // Premium section — violet says "reach up to the
                    // best on the platform".
                    accent: SocialTokens.violet,
                    // Wave-D Task #14 — route the "View all →" pill
                    // to the new AllExpertsScreen so users with more
                    // than the hub's preview-count of experts can
                    // browse + search the long tail.
                    onViewAll: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AllExpertsScreen(isArabic: isArabic),
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (_loading && _experts.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_experts.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hp, 16, hp, 0),
                    child: _EmptyHint(
                      palette: palette,
                      text: 'socialHub.noVerifiedExperts'.tr,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
                  sliver: SliverList.separated(
                    itemCount: _experts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _StaggeredEntry(
                      index: i,
                      child: LeaderboardRow(
                        rank: i + 1,
                        expert: _experts[i],
                        isArabic: isArabic,
                        onTap: () => _openExpert(context, _experts[i]),
                      ),
                    ),
                  ),
                ),

              // ─────── pinned "Your communities" section ───────
              // Two buckets, one shared header:
              //   1. OWNED — communities where the current user is the
              //      owner. Gold ring, 👑 corner badge, "Owner" pill.
              //   2. JOINED — communities the user has joined (member,
              //      not owner). Region-tinted ring, "✓ Joined" pill,
              //      no crown.
              // The whole section is hidden when the user neither
              // owns nor joins anything (no empty header).
              ..._buildPinnedSection(
                context: context,
                palette: palette,
                hp: hp,
                ownedIds: _ownedCommunityIds(auth.user?.id),
                joinedIds: _joinedCommunityIds(auth.user?.id),
              ),

              // ─────── Discover communities (the regular list) ───────
              // Excludes both owned AND joined so the user only sees
              // brand-new communities here, not duplicates of the
              // pinned section above. Hidden entirely when the user
              // toggles "Joined only" — the pinned section above
              // becomes the whole view.
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 28, hp, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _SectionHeader(
                          palette: palette,
                          title: 'socialHub.yourCommunitiesTitle'.tr,
                          subtitle: 'socialHub.discoverCommunities'.tr,
                          // Discovery section — keep brand cyan. The
                          // sibling "Top experts" uses violet, and the
                          // pinned "YOUR COMMUNITIES" sub-band uses gold.
                          accent: SocialTokens.cyan,
                          // Filter chip already occupies the right side
                          // of this row, so hide the View-all pill to
                          // avoid two trailing controls competing.
                          showViewAll: false,
                        ),
                      ),
                      _JoinedFilterChip(
                        active: _joinedOnly,
                        palette: palette,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _joinedOnly = !_joinedOnly);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (!_joinedOnly)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hp, 12, hp, 28),
                  sliver: Builder(builder: (_) {
                    if (_loading && _communities.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      );
                    }
                    final ownedIds = _ownedCommunityIds(auth.user?.id);
                    final joinedIds = _joinedCommunityIds(auth.user?.id);
                    // Discover excludes both owned + joined so each
                    // community appears in exactly one bucket.
                    final list = _communities
                        .where((c) =>
                            !ownedIds.contains(c.id) &&
                            !joinedIds.contains(c.id))
                        .toList();
                    if (list.isEmpty) {
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: _EmptyHint(
                            palette: palette,
                            text: 'socialHub.noCommunitiesToDiscover'.tr,
                          ),
                        ),
                      );
                    }
                    return SliverList.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _StaggeredEntry(
                        index: i,
                        child: CommunityCard(
                          community: list[i],
                          isArabic: isArabic,
                          isJoined: _realJoinedIds.contains(list[i].id),
                          // New: gold "Pending" pill when the user has
                          // a submitted-but-not-yet-approved subscription
                          // for this community. Wins over the join chip.
                          isPending: _pendingJoinIds.contains(list[i].id),
                          onTap: () => _openCommunity(context, list[i]),
                        ),
                      ),
                    );
                  }),
                ),
              if (_joinedOnly)
                // When "Joined only" is on we surface a small empty
                // hint when the pinned section has nothing — the
                // pinned section itself returns an empty list when
                // the user has no owned/joined communities, so the
                // user would otherwise see a blank screen.
                SliverToBoxAdapter(
                  child: Builder(builder: (_) {
                    final ownedIds = _ownedCommunityIds(auth.user?.id);
                    final joinedIds = _joinedCommunityIds(auth.user?.id);
                    if (ownedIds.isNotEmpty || joinedIds.isNotEmpty) {
                      return const SizedBox(height: 28);
                    }
                    return Padding(
                      padding: EdgeInsets.fromLTRB(hp, 32, hp, 32),
                      child: Center(
                        child: Text(
                          'socialHub.noJoinedCommunities'.tr,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
            ],
            ),
          );
        },
      ),
    );

    if (PlatformUtils.isIOS) {
      return CupertinoPageScaffold(
        backgroundColor: palette.background,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: palette.background,
          border: Border(bottom: BorderSide(color: palette.subtleDivider)),
          middle: Text(
            title,
            style: TextStyle(color: palette.textPrimary),
          ),
          trailing: Icon(
            CupertinoIcons.search,
            color: palette.textSecondary,
            size: 22,
          ),
        ),
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(title, style: TextStyle(color: palette.textPrimary)),
        iconTheme: IconThemeData(color: palette.textPrimary),
        actions: [
          // Feed shortcut icon REMOVED (May 2026) — Feed is now
          // reached via the contextual bottom-nav button-swap (the
          // 2nd slot turns from Indexes → Feed when on Social).
          //
          // Step-19 (mig 0019, item 2.15) — discovery search.
          IconButton(
            tooltip: 'socialHub.discoverTooltip'.tr,
            icon: const Icon(Icons.search_rounded),
            onPressed: () async {
              final picked = await Navigator.of(context).push<dynamic>(
                MaterialPageRoute(
                  builder: (_) => const CommunityDiscoveryScreen(),
                ),
              );
              if (picked == null || !context.mounted) return;
              final id = (picked as dynamic).id as String;
              final c = _communities.firstWhereOrNull(
                (m) => m.id == id,
              );
              if (c != null) {
                _openCommunity(context, c);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('socialHub.joinFlowSoon'.tr),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () {},
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: body,
    );
    }); // end Obx
  }

  void _openExpert(BuildContext context, Expert e) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ExpertProfileScreen(expert: e)),
    );
  }

  // Step-23 follow-up — when the user taps a community card from
  // the hub, route through the preview screen for paid communities
  // they're not yet a member of. Members + owners + free communities
  // go straight to the chat-style detail like before.
  //
  // We do a tiny pre-check on the membership endpoint AND fetch the
  // pricing meta in parallel; both are cheap single-row queries.
  // Falls back to the legacy direct-detail open if either call fails
  // — UX-permissive, the detail screen has its own gate as a backup.
  Future<void> _openCommunity(BuildContext context, Community c) async {
    final results = await Future.wait([
      CommunityService.getMembership(c.id),
      CommunityService.getMeta(c.id),
    ]);
    if (!context.mounted) return;
    final membership = results[0]
        as ({CommunityMembership? membership, String? error});
    final meta = results[1] as ({CommunityMeta? meta, String? error});
    final isMember = membership.membership?.member ?? false;
    final isOwner = membership.membership?.owner ?? false;
    final isPaid = meta.meta?.isPaid ?? false;
    if (!isMember && !isOwner && isPaid) {
      // Non-member of a paid community → preview (with pricing card).
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CommunityPreviewScreen(communityId: c.id),
        ),
      );
      // Refresh real joined ids — user may have joined free / submitted
      // a paid sub from the preview screen.
      if (mounted) await _loadRealJoinedIds();
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CommunityDetailScreen(community: c)),
    );
    // Refresh in case the user joined/left from the detail screen.
    if (mounted) await _loadRealJoinedIds();
  }

  /// Set of community ids the given user owns. Sourced from the real
  /// `ownerId` field on the fetched communities (Sprint-C step 5).
  Set<String> _ownedCommunityIds(int? userId) {
    if (userId == null) return const <String>{};
    return {
      for (final c in _communities)
        if (c.ownerId != null && c.ownerId == userId) c.id,
    };
  }

  /// Set of community ids the user has joined but does NOT own.
  /// `/me/communities` returns both owned + joined; we strip the
  /// owned ids out so each community lands in exactly one bucket.
  Set<String> _joinedCommunityIds(int? userId) {
    if (userId == null) return const <String>{};
    return _realJoinedIds.difference(_ownedCommunityIds(userId));
  }

  /// Build the "Your Communities" pinned section. Two buckets:
  ///
  ///   * Owned (gold ring, crown badge, "Owner" pill)
  ///   * Joined (region-tinted ring, "✓ Joined" pill, no crown)
  ///
  /// Returns an empty sliver list when the user is in neither
  /// bucket, so callers don't have to nullcheck before splatting.
  List<Widget> _buildPinnedSection({
    required BuildContext context,
    required SocialPalette palette,
    required double hp,
    required Set<String> ownedIds,
    required Set<String> joinedIds,
  }) {
    if (ownedIds.isEmpty && joinedIds.isEmpty) return const [];
    final owned = _communities
        .where((c) => ownedIds.contains(c.id))
        .toList();
    final joined = _communities
        .where((c) => joinedIds.contains(c.id))
        .toList();
    return [
      // Section header — gold-accented to read as "your stuff",
      // matching the 👑 owner crown used in the owned cards below.
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(hp, 24, hp, 0),
          child: Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: SocialTokens.gold,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'socialHub.yourCommunitiesBand'.tr,
                style: const TextStyle(
                  color: SocialTokens.gold,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 0.7,
                  color: SocialTokens.gold.withValues(alpha: 0.25),
                ),
              ),
            ],
          ),
        ),
      ),
      // Owned cards first — gold ring with crown so the leadership
      // role reads at a glance.
      if (owned.isNotEmpty)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(hp, 10, hp, 0),
          sliver: SliverList.separated(
            itemCount: owned.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _OwnedCommunityCard(
              community: owned[i],
              onTap: () => _openCommunity(context, owned[i]),
              palette: palette,
            ),
          ),
        ),
      // Joined cards second — region-tinted ring + small "Joined"
      // pill. Visually lighter than owned (no crown, no glow) so the
      // owned cards still pop above them.
      if (joined.isNotEmpty)
        SliverPadding(
          padding:
              EdgeInsets.fromLTRB(hp, owned.isNotEmpty ? 10 : 10, hp, 0),
          sliver: SliverList.separated(
            itemCount: joined.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _JoinedCommunityCard(
              community: joined[i],
              onTap: () => _openCommunity(context, joined[i]),
              palette: palette,
            ),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 6)),
    ];
  }

}

// ============================================================================
// Section header — magazine style.
//
// May 2026 refresh: every section now carries an `accent` color so the
// three big shelves on the social hub read as distinct identity zones
//   * gold   → "Your" (personal, you-own-it vibe)
//   * cyan   → "Discover" (brand-default, exploratory)
//   * violet → "Top experts" (premium, reach-up)
//
// Visual additions on top of the old layout:
//   1. A vertical accent bar on the LEFT of the title block (4px wide)
//      so the eye anchors on the section's color before reading any
//      text.
//   2. A thin horizontal divider line trailing off to the right at the
//      title's midline — magazine-spread feel, ties the eye across the
//      section while pointing at the optional CTA on the far right.
//   3. The subtitle picks up the accent (was hard-coded to cyan) so all
//      three colors actually surface.
//
// Backwards-compatible: callers that don't pass `accent` still get the
// previous cyan styling. CTA section unchanged.
// ============================================================================
class _SectionHeader extends StatelessWidget {
  final SocialPalette palette;
  final String title;
  final String subtitle;

  /// Per-section identity color. Defaults to brand cyan to keep
  /// callers that don't bother specifying it visually identical to
  /// the previous design.
  final Color accent;

  /// Show the "View all" pill on the far right. Defaults to true to
  /// preserve the prior layout.
  final bool showViewAll;

  /// Tap handler for the "View all" pill. When null and the pill is
  /// shown, the pill renders but its tap is a no-op (gives a ripple
  /// hint without navigating). Provide a callback to actually route
  /// to a full-list screen. Section call sites pass:
  ///   * Top Experts → AllExpertsScreen (new — June 2026)
  ///   * Discover    → showViewAll: false (filter chip occupies the
  ///                   right side instead, and the discover grid is
  ///                   already the full list below)
  final VoidCallback? onViewAll;

  const _SectionHeader({
    required this.palette,
    required this.title,
    required this.subtitle,
    this.accent = SocialTokens.cyan,
    this.showViewAll = true,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Vertical accent bar — only 4px wide but it does heavy
        // lifting for "this section is THIS color".
        Container(
          width: 4,
          height: 36,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.45),
                blurRadius: 8,
                spreadRadius: -1,
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
                subtitle.toUpperCase(),
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  letterSpacing: -0.5,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
        if (showViewAll)
          Material(
            color: Colors.transparent,
            child: InkWell(
              // Routes to a section-specific full-list screen when the
              // caller wires `onViewAll`. Currently only Top Experts
              // does so (→ AllExpertsScreen); Discover keeps
              // showViewAll=false because its grid is already the
              // full list. When null we keep the ripple but no nav.
              onTap: onViewAll ?? () {},
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'socialHub.viewAll'.tr,
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 4),
                    DirectionalIcon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// _ComingSoonCard — soft outlined card with sparkle icon + short copy.
// Used to fill the slots where we previously rendered fake / mock data
// (marquee, stories, featured expert, top movers, etc.) until the real
// backend source exists for that feature.
// =============================================================================
class _ComingSoonCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool compact;
  const _ComingSoonCard({
    required this.icon,
    required this.title,
    required this.body,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    // Pill label localized via GetX i18n — Arabic users see "قريباً"
    // instead of "SOON". Matches the body-copy localization on the
    // cards above.
    final pillLabel = 'socialHub.soon'.tr;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        // Subtle cyan→violet brand wash on top of the surface so
        // "coming soon" placeholders feel intentional (part of the
        // brand) instead of skeleton-loading squares.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SocialTokens.cyan.withValues(
              alpha: palette.isDark ? 0.08 : 0.05,
            ),
            SocialTokens.violet.withValues(
              alpha: palette.isDark ? 0.07 : 0.04,
            ),
            palette.surface,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(
          color: SocialTokens.cyan.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        children: [
          // Icon tile picks up a small gradient too so the eye notices
          // the placeholder is brand-styled, not bare.
          Container(
            width: compact ? 30 : 36,
            height: compact ? 30 : 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  SocialTokens.cyan.withValues(alpha: 0.20),
                  SocialTokens.violet.withValues(alpha: 0.20),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: SocialTokens.cyan.withValues(alpha: 0.30),
                width: 0.8,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: SocialTokens.cyan,
              size: compact ? 16 : 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 13 : 14,
                    letterSpacing: -0.2,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 2),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: SocialTokens.cyan.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: SocialTokens.cyan.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              pillLabel,
              style: const TextStyle(
                color: SocialTokens.cyan,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// _EmptyHint — friendly empty state row when a real-data list comes back
// with zero rows (no experts yet, no communities to discover, etc.).
// =============================================================================
class _EmptyHint extends StatelessWidget {
  final SocialPalette palette;
  final String text;
  const _EmptyHint({required this.palette, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.subtleDivider),
      ),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Staggered fade+slide entry animation
// ============================================================================
class _StaggeredEntry extends StatefulWidget {
  final int index;
  final Widget child;
  const _StaggeredEntry({required this.index, required this.child});

  @override
  State<_StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<_StaggeredEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_ctrl.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 14),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Pinned-section community card — gold-tinted ring + corner crown +
/// "Owner" pill, signalling at a glance that the current user owns this
/// community. Layout intentionally mirrors [CommunityCard] for visual
/// continuity, just with a stronger accent so the section reads as
/// "your stuff" without saying it twice.
class _OwnedCommunityCard extends StatelessWidget {
  final Community community;
  final VoidCallback onTap;
  final SocialPalette palette;
  const _OwnedCommunityCard({
    required this.community,
    required this.onTap,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final c = community;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: SocialTokens.gold.withValues(alpha: 0.45),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: SocialTokens.gold.withValues(alpha: 0.15),
                blurRadius: 12,
                spreadRadius: -2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Square avatar with a gold crown overlaid on the bottom-
              // right so the "owner" cue lands inside the composition,
              // not floating above the row. Shows the uploaded
              // `avatarUrl` if set, otherwise a region-tinted initials
              // tile via [CommunityAvatar].
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CommunityAvatar(
                    size: 54,
                    name: c.name,
                    regionCode: c.regionCode,
                    avatarUrl: c.avatarUrl,
                    borderRadius: 14,
                  ),
                  Positioned(
                    bottom: -4,
                    right: -4,
                    child: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.surface,
                        border: Border.all(
                          color: SocialTokens.gold,
                          width: 1.6,
                        ),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: SocialTokens.gold,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 15.5,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Compact gold "Owner" pill so even at a glance
                        // the user knows which row is theirs.
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color:
                                SocialTokens.gold.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color:
                                  SocialTokens.gold.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            'socialHub.owner'.tr,
                            style: const TextStyle(
                              color: SocialTokens.gold,
                              fontWeight: FontWeight.w900,
                              fontSize: 9.5,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(c),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              DirectionalIcon(
                Icons.chevron_right_rounded,
                color: palette.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(Community c) {
    final membersLabel = 'socialHub.members'.tr;
    final count = c.memberCount;
    final compact = count >= 1000
        ? '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}K'
        : '$count';
    return '$compact $membersLabel · ${c.regionCode}';
  }

  // (Per-card _initials helper retired with the CommunityAvatar refactor —
  // see lib/widgets/social/community_avatar.dart.)
}

/// Pinned-section card for a community the current user has JOINED
/// (member, not owner). Visually lighter than [_OwnedCommunityCard] —
/// region-tinted ring instead of gold, no crown badge, and a small
/// "✓ Joined" pill so the bucket is unambiguous at a glance.
class _JoinedCommunityCard extends StatelessWidget {
  final Community community;
  final VoidCallback onTap;
  final SocialPalette palette;
  const _JoinedCommunityCard({
    required this.community,
    required this.onTap,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final c = community;
    final regionColor = SocialTokens.regionColor(c.regionCode);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: regionColor.withValues(alpha: 0.45),
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              // Square avatar — uploaded `avatarUrl` if set, otherwise
              // a region-tinted initials tile. Same widget the owned
              // card uses, just a touch smaller (50 vs 54).
              CommunityAvatar(
                size: 50,
                name: c.name,
                regionCode: c.regionCode,
                avatarUrl: c.avatarUrl,
                borderRadius: 13,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // "✓ Joined" pill — region-tinted so it
                        // matches the avatar + ring instead of fighting
                        // them.
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: regionColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: regionColor.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_rounded,
                                size: 11,
                                color: regionColor,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'socialHub.joined'.tr,
                                style: TextStyle(
                                  color: regionColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 9.5,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(c),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              DirectionalIcon(
                Icons.chevron_right_rounded,
                color: palette.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(Community c) {
    final membersLabel = 'socialHub.members'.tr;
    final count = c.memberCount;
    final compact = count >= 1000
        ? '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}K'
        : '$count';
    return '$compact $membersLabel · ${c.regionCode}';
  }

  // (Per-card _initials helper retired with the CommunityAvatar refactor —
  // see lib/widgets/social/community_avatar.dart.)
}

// ─── "Joined only" filter chip ─────────────────────────────────────
//
// Pill-shaped toggle rendered next to the Discover section header.
// Tap to flip; when active the Discover list collapses and only
// the pinned (owned + joined) section is visible. Stable for the
// screen lifetime — not persisted across app launches.
class _JoinedFilterChip extends StatelessWidget {
  final bool active;
  final SocialPalette palette;
  final VoidCallback onTap;

  const _JoinedFilterChip({
    required this.active,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = SocialTokens.cyan;
    final fg = active ? accent : palette.textMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? accent.withValues(alpha: 0.16)
                : palette.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active
                  ? accent.withValues(alpha: 0.6)
                  : palette.border.withValues(alpha: 0.6),
              width: active ? 1.2 : 0.7,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.check_rounded : Icons.tune_rounded,
                size: 13,
                color: fg,
              ),
              const SizedBox(width: 4),
              Text(
                'socialHub.joinedOnly'.tr,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
