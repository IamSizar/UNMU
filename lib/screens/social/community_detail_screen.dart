import 'package:flutter/material.dart';
import '../../widgets/directional_icon.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'dart:async';

import '../../config/api_config.dart';
import '../../localization/locale_format.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/language_controller.dart';
import '../../controllers/realtime_controller.dart';
import '../../controllers/subscription_controller.dart';
import '../../models/user.dart';
import '../../services/community_service.dart';
import '../../services/realtime_service.dart';
import 'expert_profile_screen.dart';
import '../../widgets/social/community_avatar.dart';
import '../../widgets/social/live_ticker_strip.dart';
import '../../widgets/social/reel_grid_tile.dart';
import '../../widgets/social/shariah_grade_chip.dart';
// trading_chart import removed in Sprint-B step 18 — only call site
// was MockSocialData-driven dead code. Restore when real intraday feed lands.
import '../../widgets/social/video_card.dart';
import 'community_chat_screen.dart';
import 'community_edit_sheet.dart';
import 'community_preview_screen.dart';
import 'create_post_screen.dart';
// Invite-expert flow — owner-only button in the AppBar opens this
// screen which lists platform experts + sends a co-owner invitation.
import 'invite_expert_screen.dart';
import 'mock_social_data.dart';
import 'post_detail_screen.dart';
import 'reels_player_screen.dart';
import 'social_tokens.dart';
import 'video_player_screen.dart';

/// =============================================================================
/// Community Detail & Live Market Forums.
///
/// Layout:
///   ▸ Header (community card + sentiment)            — always visible
///   ▸ Live ticker strip                              — always visible
///   ▸ Trading chart                                  — auto-collapses on Chats
///   ▸ Tab bar                                        — pinned
///   ▸ Tab content (Chats / Posts / Videos / Reels)
///
/// The chart auto-collapses when the user is on the Chats tab so the
/// conversation has room to breathe — this fixes the "I can't scroll the
/// chats" problem on small screens.
/// =============================================================================
class CommunityDetailScreen extends StatefulWidget {
  final Community community;
  const CommunityDetailScreen({super.key, required this.community});

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  int _lastIndex = 0;

  // Tab indices for clarity. Chat lives on its OWN screen now
  // (CommunityChatScreen) reached via the chat icon in the AppBar —
  // so the tab bar is back to two.
  static const int _kMembers = 1;

  // ── Posts ───────────────────────────────────────────────────
  // The community passed in from the list arrives with an EMPTY posts
  // list (the list adapter doesn't embed posts), so we fetch the real
  // feed here on open + on pull-to-refresh. Null until first load.
  List<CommunityPost>? _posts;
  bool _loadingPosts = false;

  // ── Membership state ───────────────────────────────────────
  // Drives the Join/Leave CTA in the header. Null while loading;
  // updates optimistically on tap and reconciles with the server's
  // response.
  CommunityMembership? _membership;
  bool _membershipBusy = false;

  // ── Experts in this community ───────────────────────────────
  // Loaded once on mount. The horizontal "Experts" strip renders
  // when this list is non-empty.
  List<CommunityExpert> _experts = const [];
  bool _expertsLoading = true;

  // Realtime subscription — listens for community_member_changed
  // so the header member count updates live when anyone joins or
  // leaves THIS community.
  StreamSubscription<RealtimeEvent>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    // 2-tab build: Posts / Members. (Chat moved to its own screen.)
    _tab = TabController(length: 2, vsync: this);
    // Rebuild only when the active tab actually changes — not on every
    // animation tick — so the chart's AnimatedSize transition stays smooth.
    _tab.addListener(() {
      if (_tab.index != _lastIndex) {
        // Light selection click on every confirmed tab change.
        HapticFeedback.selectionClick();
        if (mounted) setState(() => _lastIndex = _tab.index);
      }
    });
    _loadMembership();
    _loadExperts();
    _loadPosts();
    _wireRealtime();
    // Step-23 follow-up — defense in depth: if a non-member of a
    // paid community somehow lands on this screen (any unanticipated
    // entry point), bounce them to the preview/pricing screen on the
    // next frame. pushReplacement so the back button doesn't loop
    // them right back here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeBounceForPaidGate();
    });
  }

  /// Fetches live community + membership state and pushReplacements
  /// to [CommunityPreviewScreen] when the viewer is a non-member of a
  /// paid community. Owners and existing members bypass the bounce.
  /// Best-effort — any fetch error leaves the screen as-is.
  Future<void> _maybeBounceForPaidGate() async {
    final results = await Future.wait([
      CommunityService.getMeta(widget.community.id),
      CommunityService.getMembership(widget.community.id),
    ]);
    if (!mounted) return;
    final meta = results[0] as ({CommunityMeta? meta, String? error});
    final mem = results[1]
        as ({CommunityMembership? membership, String? error});
    final isPaid = meta.meta?.isPaid ?? false;
    final isMember = mem.membership?.member ?? false;
    final isOwner = mem.membership?.owner ?? false;
    if (isPaid && !isMember && !isOwner) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              CommunityPreviewScreen(communityId: widget.community.id),
        ),
      );
    }
  }

  /// Fetches the community's real post feed (the passed-in community has
  /// an empty posts list). Safe to call repeatedly — drives both the
  /// initial load and pull-to-refresh.
  Future<void> _loadPosts() async {
    if (mounted) setState(() => _loadingPosts = true);
    final res = await CommunityService.listPosts(widget.community.id);
    if (!mounted) return;
    setState(() {
      _loadingPosts = false;
      if (res.rows != null) {
        _posts = res.rows!.map(_toCommunityPost).toList();
      }
    });
  }

  CommunityPost _toCommunityPost(Map<String, dynamic> j) {
    return CommunityPost(
      id: (j['id'] ?? '').toString(),
      author: j['authorName']?.toString() ?? '',
      timeAgo: _relativeTime(j['createdAt']?.toString()),
      title: j['title']?.toString() ?? '',
      body: j['body']?.toString() ?? '',
      ticker: j['ticker']?.toString() ?? '',
      stance: (j['stance']?.toString() ?? 'HOLD').toUpperCase(),
      upvotes: (j['upvotes'] as num?)?.toInt() ?? 0,
      comments: (j['comments'] as num?)?.toInt() ?? 0,
      coverUrl: j['coverUrl']?.toString() ?? '',
      authorId: (j['authorId'] as num?)?.toInt() ?? 0,
      isHidden: j['isHidden'] as bool? ?? false,
    );
  }

  static String _relativeTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    return LocaleFormat.relative(t);
  }

  // ── Post moderation (author / owner / admin) ────────────────
  // The server is the final gate (requireCommunityPostMod). These
  // client checks decide whether to SHOW the ⋯ menu so we don't
  // surface actions that would 403. Co-owners aren't distinguishable
  // here, but the owner sees the menu and co-owners still get a clean
  // server-side 403 with a toast if they somehow reach an action.

  /// True when the current viewer may moderate [post]: a platform admin,
  /// the community owner, or the post's own author.
  bool _canModeratePost(CommunityPost post, {required bool amOwner}) {
    final me = Get.find<AuthController>().user;
    if (me == null) return false;
    if (me.role == UserRole.admin) return true;
    if (amOwner) return true;
    return post.authorId != 0 && post.authorId == me.id;
  }

  /// Edit dialog — community posts are articles, so title + body are the
  /// fields that matter. PATCHes then refreshes the feed.
  Future<void> _editPost(CommunityPost post) async {
    final palette = SocialTheme.of(context);
    final titleCtl = TextEditingController(text: post.title);
    final bodyCtl = TextEditingController(text: post.body);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(
          'community.editPost.title'.tr,
          style: TextStyle(color: palette.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtl,
                style: TextStyle(color: palette.textPrimary),
                decoration: InputDecoration(
                  labelText: 'community.editPost.fieldTitle'.tr,
                  labelStyle: TextStyle(color: palette.textMuted),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyCtl,
                minLines: 3,
                maxLines: 8,
                style: TextStyle(color: palette.textPrimary),
                decoration: InputDecoration(
                  labelText: 'community.editPost.fieldBody'.tr,
                  labelStyle: TextStyle(color: palette.textMuted),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('common.save'.tr),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final title = titleCtl.text.trim();
    final body = bodyCtl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      Get.snackbar(
        'common.required'.tr,
        'community.editPost.required'.tr,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final res = await CommunityService.updatePost(
      widget.community.id,
      int.tryParse(post.id) ?? 0,
      title: title,
      body: body,
    );
    if (!mounted) return;
    if (res.error != null) {
      Get.snackbar('common.error'.tr, res.error!,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    await _loadPosts();
    Get.snackbar(
      'common.success'.tr,
      'community.editPost.updated'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  /// Hide / un-hide toggle. Hidden posts vanish from members' feeds but
  /// stay visible (dimmed) to moderators + the author.
  Future<void> _toggleHidePost(CommunityPost post) async {
    final res = await CommunityService.setPostHidden(
      widget.community.id,
      int.tryParse(post.id) ?? 0,
      !post.isHidden,
    );
    if (!mounted) return;
    if (res.error != null) {
      Get.snackbar('common.error'.tr, res.error!,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    await _loadPosts();
    Get.snackbar(
      'common.done'.tr,
      post.isHidden
          ? 'community.post.nowVisible'.tr
          : 'community.post.hidden'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  /// Delete with confirmation. Permanent.
  Future<void> _deletePost(CommunityPost post) async {
    final palette = SocialTheme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(
          'community.deletePost.title'.tr,
          style: TextStyle(color: palette.textPrimary),
        ),
        content: Text(
          'community.deletePost.body'.tr,
          style: TextStyle(color: palette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SocialTokens.down),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('common.delete'.tr),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final res = await CommunityService.deletePost(
      widget.community.id,
      int.tryParse(post.id) ?? 0,
    );
    if (!mounted) return;
    if (res.error != null) {
      Get.snackbar('common.error'.tr, res.error!,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    await _loadPosts();
    Get.snackbar(
      'common.done'.tr,
      'community.deletePost.deleted'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _tab.dispose();
    super.dispose();
  }

  /// Listen to the global realtime stream for member-count changes
  /// scoped to this community. The hub already auto-subscribes the
  /// connection to `community:<id>` channels for any community the
  /// user has joined; we just filter here for this screen's id.
  void _wireRealtime() {
    final RealtimeController rt;
    try {
      rt = Get.find<RealtimeController>();
    } catch (_) {
      // Realtime not registered (offline dev / tests) — leave the
      // header at the seed/probe count.
      return;
    }
    _realtimeSub = rt.events.listen((ev) {
      if (ev.type != 'community_member_changed') return;
      final cid = ev.data['communityId']?.toString() ?? '';
      if (cid != widget.community.id) return;
      final count = (ev.data['memberCount'] as num?)?.toInt();
      if (count == null) return;
      if (!mounted) return;
      setState(() {
        // Patch the membership snapshot's count without changing
        // member/owner flags — those didn't change here.
        _membership = CommunityMembership(
          member: _membership?.member ?? false,
          owner: _membership?.owner ?? false,
          memberCount: count,
        );
      });
    });
  }

  /// One-shot fetch on mount — backend tells us whether the caller
  /// is a member + whether they're the owner. Owners see no
  /// Join/Leave CTA (they get the gear menu instead).
  Future<void> _loadMembership() async {
    final res = await CommunityService.getMembership(widget.community.id);
    if (!mounted) return;
    if (res.membership != null) {
      setState(() => _membership = res.membership);
    }
  }

  Future<void> _loadExperts() async {
    final res = await CommunityService.listExperts(widget.community.id);
    if (!mounted) return;
    setState(() {
      _experts = res.experts ?? const [];
      _expertsLoading = false;
    });
  }

  /// Toggle membership. Optimistic flip for instant feedback +
  /// reconcile with server response. On failure we restore the
  /// previous state and snackbar the error.
  /// Returns true when the current viewer is allowed to post in this
  /// community. Mirrors the backend `CreateCommunityPost` gate so the
  /// FAB visibility matches what the server will accept:
  ///
  ///   * the owner always qualifies (owners are guaranteed EXPERT
  ///     role + member by the proposal-approval flow),
  ///   * everyone else needs role == expert AND a non-null expertId
  ///     AND a confirmed membership row.
  ///
  /// The membership probe might still be loading on first frame —
  /// in that case we hide the FAB rather than flash it briefly,
  /// since `_membership == null` means we don't know yet.
  bool _canComposeInCommunity(
    AuthController auth, {
    required bool amOwner,
  }) {
    if (amOwner) return true;
    final user = auth.user;
    if (user == null) return false;
    if (user.role != UserRole.expert) return false;
    if (user.expertId == null || user.expertId!.isEmpty) return false;
    return _membership?.member ?? false;
  }

  /// Confirmation dialog shown before the user leaves a community.
  /// Returns true on confirm, false / null on cancel.
  ///
  /// Owners never reach this — the membership button isn't rendered
  /// for them in the first place (see `if (!amOwner ...)` in build).
  Future<bool?> _confirmLeave() {
    return showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final palette = SocialTheme.of(dialogCtx);
        return AlertDialog(
          backgroundColor: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'community.leave.title'.trParams({'name': widget.community.name}),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'community.leave.body'.tr,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(
                'common.cancel'.tr,
                style: TextStyle(color: palette.textMuted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: SocialTokens.down,
              ),
              child: Text(
                'community.leave'.tr,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleMembership() async {
    final currentlyMember = _membership?.member ?? false;
    if (_membershipBusy) return;
    // Leaving is destructive (loses access to private posts + chat) —
    // require an explicit confirm so a stray tap on the "Joined" pill
    // doesn't accidentally remove the user. Joining stays one-tap.
    if (currentlyMember) {
      final confirmed = await _confirmLeave();
      if (confirmed != true) return;
    } else {
      // Step-23 follow-up — pre-check pricing on join. If the
      // community is paid, route directly to the preview/pricing
      // screen instead of letting the optimistic flip happen and
      // then rolling back when the server returns 402. Avoids a
      // confusing flash and a dead-end toast.
      final metaRes = await CommunityService.getMeta(widget.community.id);
      if (!mounted) return;
      final meta = metaRes.meta;
      if (meta != null && meta.isPaid) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CommunityPreviewScreen(
              communityId: widget.community.id,
            ),
          ),
        );
        if (mounted) await _loadMembership();
        return;
      }
    }
    HapticFeedback.selectionClick();
    final priorCount = _membership?.memberCount ?? widget.community.memberCount;
    setState(() {
      _membershipBusy = true;
      // Optimistic flip — UI feels instant. Bump the member count
      // by ±1 so the header updates immediately; the realtime
      // event will reconcile with the authoritative server value.
      _membership = CommunityMembership(
        member: !currentlyMember,
        owner: _membership?.owner ?? false,
        memberCount: currentlyMember
            ? (priorCount > 0 ? priorCount - 1 : 0)
            : priorCount + 1,
      );
    });
    // Step-23 follow-up — branched on the action because leave() and
    // join() now return different tuple shapes (join carries the
    // price hint when the server returns 402 for paid communities).
    bool ok;
    String? errMsg;
    bool paymentRequired = false;
    if (currentlyMember) {
      final r = await CommunityService.leave(widget.community.id);
      ok = r.ok;
      errMsg = r.error;
    } else {
      final r = await CommunityService.join(widget.community.id);
      ok = r.ok;
      errMsg = r.error;
      paymentRequired = r.paymentRequired;
    }
    if (!mounted) return;
    if (!ok) {
      // Roll back — re-flip to the prior state.
      HapticFeedback.heavyImpact();
      setState(() {
        _membership = CommunityMembership(
          member: currentlyMember,
          owner: _membership?.owner ?? false,
          memberCount: priorCount,
        );
        _membershipBusy = false;
      });
      // Step-23 — auto-route to the preview/pricing screen when the
      // server returned 402 (paid community). Saves the user from a
      // dead-end "couldn't join" toast.
      if (paymentRequired) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CommunityPreviewScreen(
              communityId: widget.community.id,
            ),
          ),
        );
        if (mounted) await _loadMembership();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(errMsg ?? 'community.actionFailed'.tr),
        ),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _membershipBusy = false);
    // Confirmation snackbar — Telegram-style "you joined" / "left".
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Text(
          currentlyMember
              ? 'community.left'.tr
              : 'community.joinedCommunity'.tr,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = Get.find<LanguageController>().isArabic;
    final palette = SocialTheme.of(context);
    final c = widget.community;
    final accent = SocialTokens.regionColor(c.regionCode);
    // The lead ticker / live ticker strip / trading chart are all
    // mock-data-only for now (no real intraday quote feed yet). When
    // the community has no ticker rows (every community fetched from
    // the real backend right now), we skip those widgets entirely
    // rather than crash on `.first`. `hasTickers` is consumed by the
    // LiveTickerStrip render gate below; the chart's lead-ticker
    // derived block was deleted in step 18, so `lead` isn't computed
    // here any more.
    final hasTickers = c.liveTickers.isNotEmpty;

    final upCount = c.liveTickers.where((q) => q.changePct >= 0).length;
    final sentiment = c.liveTickers.isEmpty
        ? 0.5
        : upCount / c.liveTickers.length;

    // Owner gate — the gear ⚙ + manage sheet only render for the user
    // whose id matches community.ownerId. Reads the live AuthController
    // value so a test-account switch updates the visibility on rebuild.
    final auth = Get.find<AuthController>();
    final amOwner = c.ownerId != null && auth.user?.id == c.ownerId;

    // 2-tab build — Posts / Members. Chat lives on its own screen.
    final tabBar = TabBar(
      controller: _tab,
      indicatorColor: accent,
      indicatorWeight: 3,
      labelColor: palette.textPrimary,
      unselectedLabelColor: palette.textMuted,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800),
      tabs: [
        Tab(text: 'community.tab.posts'.tr),
        Tab(text: 'community.tab.members'.tr),
      ],
    );

    return Scaffold(
      backgroundColor: palette.background,
      // resizeToAvoidBottomInset is true by default — the chat input floats
      // above the keyboard automatically.
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(c.name, style: TextStyle(color: palette.textPrimary)),
        iconTheme: IconThemeData(color: palette.textPrimary),
        actions: [
          // Chat icon — visible to everyone. Pushes the standalone
          // [CommunityChatScreen] so the conversation gets the full
          // screen instead of squeezing into a tab.
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            tooltip: 'community.tooltip.chat'.tr,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CommunityChatScreen(community: c),
                ),
              );
            },
          ),
          // Owner-only "Invite expert" (mig 0032 — co-owner invite
          // flow). Sits BETWEEN the chat icon and the gear so the
          // order reads `[💬] [👤➕] [⚙]`. Only the primary owner
          // can send invitations (co-owners can NOT invite further
          // co-owners — keeps the power structure clear).
          if (amOwner)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_rounded),
              tooltip: 'community.tooltip.inviteExpert'.tr,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InviteExpertScreen(
                      communityId: c.id,
                      communityName: c.name,
                    ),
                  ),
                );
              },
            ),
          // Owner-only gear ⚙ — taps open a manage sheet. Sits to the
          // RIGHT of the chat icon so the order reads `[💬]  [⚙]`.
          if (amOwner)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'community.tooltip.manage'.tr,
              onPressed: () => _ManageSheet.show(
                context,
                community: c,
                onJumpToMembers: () {
                  Navigator.of(context).pop();
                  _tab.animateTo(_kMembers);
                },
              ),
            ),
        ],
      ),
      // Floating composer trigger — only experts who are members of
      // THIS community see it. Backend (CreateCommunityPost) enforces
      // the same gate, so a user who somehow bypasses the visibility
      // check still gets a 403. Returns true on successful publish
      // so we rebuild and the newly-prepended post shows up at the
      // top of the list.
      //
      // Eligibility:
      //   * viewer.role == EXPERT  AND  expertId != null
      //   * viewer is a member of this community (via _membership probe)
      //   * OR viewer is the community owner (always an expert + member)
      floatingActionButton:
          (_canComposeInCommunity(auth, amOwner: amOwner)
              ? _ComposeFab(
                  accent: accent,
                  label: 'community.newPost'.tr,
                  onTap: () async {
                    final created = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) =>
                            CreatePostScreen.community(community: c),
                      ),
                    );
                    if (created == true && mounted) setState(() {});
                  },
                )
              : null),
      // NestedScrollView lets the header (community card + ticker + chart)
      // scroll AWAY when the user scrolls within a tab, giving Posts /
      // Videos / Reels full-height browsing space. The TabBar stays pinned.
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _CommunityHeader(
                community: c,
                palette: palette,
                accent: accent,
                sentiment: sentiment,
                isArabic: isArabic,
                memberCountOverride: _membership?.memberCount,
                // Owners always see "Joined" (they're a member by
                // definition); others read from the live probe.
                isJoinedOverride: amOwner
                    ? true
                    : _membership?.member,
              ),
            ),
          ),
          // ── Join / Leave CTA ──────────────────────────────────
          // Shown only to non-owners. Owners get the gear menu in
          // the AppBar instead. Hidden until the membership probe
          // completes so we don't flash Join → Leave.
          if (!amOwner && _membership != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _MembershipButton(
                  isMember: _membership!.member,
                  busy: _membershipBusy,
                  accent: accent,
                  palette: palette,
                  onTap: () => _toggleMembership(),
                ),
              ),
            ),
          // ── Experts in this community ─────────────────────────
          // Horizontal scroll of expert cards, owner-first then by
          // subscriber count. Tap to push the expert profile.
          // Hidden when there are zero experts (most communities
          // will have at least the owner).
          if (!_expertsLoading && _experts.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
                child: _CommunityExpertsStrip(
                  experts: _experts,
                  accent: accent,
                  palette: palette,
                ),
              ),
            ),
          // Live ticker strip + trading chart are mock-data-only for
          // now (no real intraday feed). Hidden when no ticker data
          // is present — we'll reintroduce once we have a real quote
          // provider wired to the backend.
          if (hasTickers)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child:
                    LiveTickerStrip(quotes: c.liveTickers, isArabic: isArabic),
              ),
            ),
          // Sprint-B step 18 — the intraday chart was the last
          // MockSocialData.* call in this file. Dead in practice
          // (the gate `hasTickers && lead != null` is never true
          // with real-backend adapted communities, since liveTickers
          // is empty). When we re-introduce a real intraday feed,
          // swap in the real series here.
          //
          // Kept as a no-op placeholder so existing tests that pass
          // a mock community with liveTickers don't crash.
          // Pinned tab bar — stays at the top of the view as the header
          // collapses upward.
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(palette: palette, tabBar: tabBar),
          ),
        ],
        body: TabBarView(
          controller: _tab,
          children: [
            _CommunityPostsTab(
              posts: _posts ?? c.posts,
              community: c,
              onRefresh: _loadPosts,
              loading: _loadingPosts && _posts == null,
              canModerate: (p) => _canModeratePost(p, amOwner: amOwner),
              onEditPost: _editPost,
              onToggleHidePost: _toggleHidePost,
              onDeletePost: _deletePost,
            ),
            _CommunityMembersTab(
              community: c,
              accent: accent,
              isArabic: isArabic,
              amOwner: amOwner,
            ),
          ],
        ),
      ),
    );
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
// Header (community meta + sentiment meter)
// ============================================================================
class _CommunityHeader extends StatefulWidget {
  final Community community;
  final SocialPalette palette;
  final Color accent;
  final double sentiment;
  final bool isArabic;
  /// Live member count override — supplied by the parent screen
  /// from the `community_member_changed` realtime event +
  /// membership probe. Falls back to `community.memberCount`
  /// (the seed value) until the first server response lands.
  final int? memberCountOverride;
  /// Step-23 follow-up — real membership state from the
  /// `/communities/:id/membership` probe. Drives the "Joined" /
  /// "Join" badge in the header so it reflects DB truth, not the
  /// hardcoded mock state. Null while loading; the badge stays
  /// hidden until we know.
  final bool? isJoinedOverride;

  const _CommunityHeader({
    required this.community,
    required this.palette,
    required this.accent,
    required this.sentiment,
    required this.isArabic,
    this.memberCountOverride,
    this.isJoinedOverride,
  });

  @override
  State<_CommunityHeader> createState() => _CommunityHeaderState();
}

class _CommunityHeaderState extends State<_CommunityHeader> {
  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final accent = widget.accent;
    final c = widget.community;
    final membersLabel = 'community.members.label'.tr;
    final activeLabel = 'community.activeNow'.tr;
    // Step-23 follow-up — joined state comes from the real
    // membership probe (parent passes it as an override). When the
    // probe hasn't completed yet, we default to "Join" so we never
    // falsely advertise "Joined" for non-members of paid communities.
    final isJoined = widget.isJoinedOverride ?? false;
    final joinLabel = isJoined ? 'community.joined'.tr : 'community.join'.tr;
    final sentimentLabel = widget.sentiment >= 0.5
        ? 'community.sentiment.bullish'.tr
        : 'community.sentiment.bearish'.tr;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: palette.heroGradient(),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent.withValues(alpha: palette.isDark ? 0.45 : 0.30),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: palette.isDark ? 0.16 : 0.10),
            blurRadius: 22,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar — uploaded community logo if set, otherwise a
              // region-tinted initials tile via [CommunityAvatar].
              // Replaces the previous region-code gradient block so the
              // detail page header matches the cards in the hub /
              // discover surfaces.
              CommunityAvatar(
                size: 50,
                name: c.name,
                regionCode: c.regionCode,
                avatarUrl: c.avatarUrl,
                borderRadius: 13,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.people_alt_rounded,
                          size: 12,
                          color: palette.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_compact(widget.memberCountOverride ?? c.memberCount)} $membersLabel',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.bolt_rounded,
                          size: 12,
                          color: SocialTokens.up,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${c.activeNow} $activeLabel',
                          style: const TextStyle(
                            color: SocialTokens.up,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Step-23 follow-up — read-only state badge. The real
              // Join / Leave action lives on the bigger
              // _MembershipButton below, so this badge just reflects
              // truth without its own onPressed (the old toggle was
              // local-state-only and didn't call any backend).
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isJoined ? Colors.transparent : accent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent, width: 1.3),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isJoined ? Icons.check_rounded : Icons.add_rounded,
                      size: 13,
                      color: isJoined ? accent : Colors.black,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      joinLabel,
                      style: TextStyle(
                        color: isJoined ? accent : Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SentimentMeter(
            palette: palette,
            sentiment: widget.sentiment,
            label: sentimentLabel,
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

class _SentimentMeter extends StatelessWidget {
  final SocialPalette palette;
  final double sentiment;
  final String label;
  const _SentimentMeter({
    required this.palette,
    required this.sentiment,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (sentiment * 100).round();
    final isBullish = sentiment >= 0.5;
    final color = isBullish ? SocialTokens.up : SocialTokens.down;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isBullish
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              'community.marketSentiment'.tr,
              style: TextStyle(color: palette.textMuted, fontSize: 11),
            ),
            const Spacer(),
            Text(
              '$label · $pct%',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: SocialTokens.down.withValues(alpha: 0.25),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: sentiment.clamp(0.04, 1.0),
                  child: Container(color: SocialTokens.up),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Tab A: CHATS — redesigned messaging UI
// ============================================================================
class _ChatsTab extends StatefulWidget {
  final List<ChatMessage> initialMessages;
  final List<TickerQuote> liveTickers;
  final bool isArabic;

  const _ChatsTab({
    required this.initialMessages,
    required this.liveTickers,
    required this.isArabic,
  });

  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab>
    with AutomaticKeepAliveClientMixin {
  late List<ChatMessage> _messages;
  late final TextEditingController _input;
  late final ScrollController _scroll;
  late final FocusNode _focus;
  bool _hasText = false;

  // TabBarView inside NestedScrollView lazily disposes off-screen tabs.
  // Keep the chat alive so composing text + message list survive tab switches.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _messages = List<ChatMessage>.from(widget.initialMessages);
    _input = TextEditingController();
    _scroll = ScrollController();
    _focus = FocusNode();
    _input.addListener(() {
      final has = _input.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(
        ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          author: 'You',
          timeAgo: 'now',
          body: text,
          tickers: const [],
          isCurrentUser: true,
        ),
      );
      _input.clear();
      _hasText = false;
    });
    // With reverse: true, "scroll to newest" = animateTo(0).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _insertTicker(String symbol) {
    final base = _input.text;
    final sep = base.isEmpty || base.endsWith(' ') ? '' : ' ';
    _input.text = '$base$sep\$$symbol ';
    _input.selection = TextSelection.fromPosition(
      TextPosition(offset: _input.text.length),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final palette = SocialTheme.of(context);
    final todayLabel = 'community.chatTab.today'.tr;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            physics: const BouncingScrollPhysics(),
            // +1 for the "TODAY" header that floats at the top of the list.
            itemCount: _messages.length + 1,
            itemBuilder: (_, i) {
              // Last item (i == _messages.length) is the TODAY chip at top.
              if (i == _messages.length) {
                return _DateSeparator(palette: palette, label: todayLabel);
              }
              final realIndex = _messages.length - 1 - i;
              final msg = _messages[realIndex];
              // Hide the avatar/header if previous-author == this author so
              // consecutive messages stack tightly (Slack-style).
              final prev = realIndex > 0 ? _messages[realIndex - 1] : null;
              final showAuthor = prev == null || prev.author != msg.author;
              return _MessageBubble(
                palette: palette,
                message: msg,
                showAuthor: showAuthor,
              );
            },
          ),
        ),
        _SymbolQuickInsertBar(
          palette: palette,
          tickers: widget.liveTickers,
          onTap: _insertTicker,
        ),
        _ChatInputBar(
          palette: palette,
          controller: _input,
          focusNode: _focus,
          hasText: _hasText,
          onSend: _send,
        ),
      ],
    );
  }
}

// ── Date separator chip ─────────────────────────────────────────────
class _DateSeparator extends StatelessWidget {
  final SocialPalette palette;
  final String label;
  const _DateSeparator({required this.palette, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: palette.subtleDivider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.border),
              ),
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: palette.subtleDivider)),
        ],
      ),
    );
  }
}

// ── Message bubble (avatar + bubble + tickers) ──────────────────────
class _MessageBubble extends StatelessWidget {
  final SocialPalette palette;
  final ChatMessage message;
  final bool showAuthor;

  const _MessageBubble({
    required this.palette,
    required this.message,
    required this.showAuthor,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isCurrentUser;
    final accent = isMe ? SocialTokens.cyan : _avatarColorFor(message.author);

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isMe
            ? SocialTokens.cyan.withValues(alpha: 0.18)
            : palette.surface,
        border: Border.all(
          color: isMe
              ? SocialTokens.cyan.withValues(alpha: 0.4)
              : palette.border,
        ),
        // Slack/iMessage-style bubble: rounded with one corner squared near
        // the avatar to create a "tail" feel.
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isMe ? 14 : (showAuthor ? 4 : 14)),
          topRight: Radius.circular(isMe ? (showAuthor ? 4 : 14) : 14),
          bottomLeft: const Radius.circular(14),
          bottomRight: const Radius.circular(14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message.body,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          if (message.tickers.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: message.tickers
                  .map(
                    (t) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: SocialTokens.cyan.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '\$$t',
                        style: const TextStyle(
                          color: SocialTokens.cyan,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );

    final headerLine = showAuthor
        ? Padding(
            // Indent the header to line up with the bubble (38 = avatar + gap).
            padding: EdgeInsets.fromLTRB(
              isMe ? 0 : 38,
              0,
              isMe ? 38 : 0,
              4,
            ),
            child: Row(
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                Text(
                  message.author,
                  style: TextStyle(
                    color: isMe ? SocialTokens.cyan : palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  message.timeAgo,
                  style: TextStyle(color: palette.textMuted, fontSize: 10),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    final avatar = SizedBox(
      width: 30,
      height: 30,
      child: showAuthor
          ? Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [accent, accent.withValues(alpha: 0.55)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials(message.author),
                style: const TextStyle(
                  color: Color(0xFF0A1628),
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: -0.5,
                ),
              ),
            )
          : const SizedBox.shrink(),
    );

    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.74;

    return Padding(
      padding: EdgeInsets.only(top: showAuthor ? 8 : 2, bottom: 0),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          headerLine,
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                avatar,
                const SizedBox(width: 8),
              ],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: bubble,
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 8),
                avatar,
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  /// Stable per-author hue so each chatter has a recognizable color.
  Color _avatarColorFor(String name) {
    final hash = name.codeUnits.fold<int>(0, (a, b) => a + b);
    final hue = (hash * 47) % 360;
    return HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.62).toColor();
  }
}

// ── Quick-insert symbol bar (tap to inject $TICKER into the input) ────
class _SymbolQuickInsertBar extends StatelessWidget {
  final SocialPalette palette;
  final List<TickerQuote> tickers;
  final ValueChanged<String> onTap;

  const _SymbolQuickInsertBar({
    required this.palette,
    required this.tickers,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.subtleDivider)),
      ),
      child: Row(
        children: [
          Icon(Icons.add_chart_rounded, size: 14, color: palette.textMuted),
          const SizedBox(width: 5),
          Text(
            'community.chat.insertSymbol'.tr.toUpperCase(),
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: tickers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final t = tickers[i];
                return GestureDetector(
                  onTap: () => onTap(t.symbol),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShariahGradeChip(grade: t.shariahGrade, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '\$${t.symbol}',
                          style: const TextStyle(
                            color: SocialTokens.cyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
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
}

// ── Chat input bar (multiline-friendly text field + animated send) ────
class _ChatInputBar extends StatelessWidget {
  final SocialPalette palette;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final VoidCallback onSend;

  const _ChatInputBar({
    required this.palette,
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.subtleDivider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        Icons.add_circle_outline_rounded,
                        color: palette.textMuted,
                        size: 22,
                      ),
                      onPressed: () {},
                      visualDensity: VisualDensity.compact,
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'community.chat.typeMessage'.tr,
                          hintStyle: TextStyle(color: palette.textMuted),
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.sentiment_satisfied_rounded,
                        color: palette.textMuted,
                        size: 22,
                      ),
                      onPressed: () {},
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send button — animates color/scale when text is present.
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: hasText
                    ? const LinearGradient(
                        colors: [SocialTokens.cyan, SocialTokens.cyanSoft],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: hasText ? null : palette.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(
                  color: hasText ? SocialTokens.cyan : palette.border,
                ),
                boxShadow: hasText
                    ? [
                        BoxShadow(
                          color: SocialTokens.cyan.withValues(alpha: 0.45),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: hasText ? onSend : null,
                  customBorder: const CircleBorder(),
                  child: Center(
                    child: Icon(
                      Icons.send_rounded,
                      size: 19,
                      color: hasText
                          ? const Color(0xFF0A1628)
                          : palette.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Tab B: POSTS — forum threads. Tap a row → opens the full-screen post
// detail viewer.
// ============================================================================
class _CommunityPostsTab extends StatelessWidget {
  final List<CommunityPost> posts;
  final Community community;
  final Future<void> Function()? onRefresh;
  final bool loading;
  // Moderation hooks — null-safe. When [canModerate] returns true for a
  // post, [_PostThread] renders a ⋯ menu wired to these callbacks.
  final bool Function(CommunityPost)? canModerate;
  final void Function(CommunityPost)? onEditPost;
  final void Function(CommunityPost)? onToggleHidePost;
  final void Function(CommunityPost)? onDeletePost;
  const _CommunityPostsTab({
    required this.posts,
    required this.community,
    this.onRefresh,
    this.loading = false,
    this.canModerate,
    this.onEditPost,
    this.onToggleHidePost,
    this.onDeletePost,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final Widget child = posts.isEmpty
        ? ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 100),
              Center(
                child: loading
                    ? const CircularProgressIndicator()
                    : Text(
                        'community.posts.empty'.tr,
                        style: TextStyle(color: palette.textMuted, fontSize: 14),
                      ),
              ),
            ],
          )
        : ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: posts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final p = posts[i];
              final mod = canModerate?.call(p) ?? false;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => PostDetailScreen(
                        post: p,
                        community: community,
                      ),
                    ),
                  );
                },
                child: _PostThread(
                  post: p,
                  canModerate: mod,
                  onEdit: mod ? () => onEditPost?.call(p) : null,
                  onToggleHide: mod ? () => onToggleHidePost?.call(p) : null,
                  onDelete: mod ? () => onDeletePost?.call(p) : null,
                ),
              );
            },
          );
    if (onRefresh == null) return child;
    return RefreshIndicator(onRefresh: onRefresh!, child: child);
  }
}

// Resolves a post cover URL for display: S3 covers arrive as absolute
// https URLs; legacy disk covers arrive as `/uploads/...` and get the API
// origin prepended so Image.network can load them.
String _resolvePostImageUrl(String u) {
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  final origin = ApiConfig.baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
  return origin + u;
}

class _PostThread extends StatelessWidget {
  final CommunityPost post;
  // Moderation menu — shown only when [canModerate] is true (author /
  // owner / admin). Callbacks are null otherwise.
  final bool canModerate;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleHide;
  final VoidCallback? onDelete;
  const _PostThread({
    required this.post,
    this.canModerate = false,
    this.onEdit,
    this.onToggleHide,
    this.onDelete,
  });

  Color _stanceColor(String s) {
    switch (s.toUpperCase()) {
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
    final palette = SocialTheme.of(context);
    final stanceColor = _stanceColor(post.stance);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // Hidden posts (only visible here to moderators + the author) get
        // a faint gold tint + border so it's obvious they're not in the
        // members' feed.
        color: post.isHidden
            ? SocialTokens.gold.withValues(alpha: 0.06)
            : palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: post.isHidden
              ? SocialTokens.gold.withValues(alpha: 0.5)
              : palette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Left group expands so the author name ellipsizes instead
              // of overflowing when the ⋯ menu / Hidden badge are present.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        post.author,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· ${post.timeAgo}',
                      style: TextStyle(color: palette.textMuted, fontSize: 11),
                    ),
                    if (post.isHidden) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: SocialTokens.gold.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: SocialTokens.gold),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.visibility_off_outlined,
                                size: 11, color: SocialTokens.gold),
                            const SizedBox(width: 3),
                            Text(
                              'community.post.hiddenBadge'.tr,
                              style: const TextStyle(
                                color: SocialTokens.gold,
                                fontWeight: FontWeight.w900,
                                fontSize: 9,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: stanceColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: stanceColor),
                ),
                child: Text(
                  post.ticker.isEmpty
                      ? post.stance
                      : '${post.stance}  \$${post.ticker}',
                  style: TextStyle(
                    color: stanceColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              // ── Moderation ⋯ menu (author / owner / admin) ──────
              if (canModerate) ...[
                const SizedBox(width: 2),
                SizedBox(
                  height: 28,
                  width: 28,
                  child: PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz_rounded,
                        size: 18, color: palette.textMuted),
                    color: palette.surfaceElevated,
                    padding: EdgeInsets.zero,
                    tooltip: 'community.actions'.tr,
                    onSelected: (v) {
                      switch (v) {
                        case 'edit':
                          onEdit?.call();
                          break;
                        case 'hide':
                          onToggleHide?.call();
                          break;
                        case 'delete':
                          onDelete?.call();
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_outlined,
                              size: 18, color: palette.textSecondary),
                          const SizedBox(width: 10),
                          Text('common.edit'.tr,
                              style: TextStyle(color: palette.textPrimary)),
                        ]),
                      ),
                      PopupMenuItem<String>(
                        value: 'hide',
                        child: Row(children: [
                          Icon(
                              post.isHidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                              color: palette.textSecondary),
                          const SizedBox(width: 10),
                          Text(
                              post.isHidden
                                  ? 'community.post.unhide'.tr
                                  : 'community.post.hide'.tr,
                              style: TextStyle(color: palette.textPrimary)),
                        ]),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(children: [
                          const Icon(Icons.delete_outline_rounded,
                              size: 18, color: SocialTokens.down),
                          const SizedBox(width: 10),
                          Text('common.delete'.tr,
                              style:
                                  const TextStyle(color: SocialTokens.down)),
                        ]),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            post.title,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            post.body,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          // Cover image (e.g. a shared index chart).
          if (post.coverUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _resolvePostImageUrl(post.coverUrl),
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (ctx, c, p) => p == null
                    ? c
                    : Container(
                        height: 160,
                        alignment: Alignment.center,
                        color: palette.surfaceElevated,
                        child: const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      ),
                errorBuilder: (ctx, _, __) => Container(
                  height: 120,
                  alignment: Alignment.center,
                  color: palette.surfaceElevated,
                  child: Icon(Icons.broken_image_outlined,
                      color: palette.textMuted),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.arrow_upward_rounded,
                size: 16,
                color: SocialTokens.up,
              ),
              const SizedBox(width: 4),
              Text(
                '${post.upvotes}',
                style: const TextStyle(
                  color: SocialTokens.up,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 14),
              Icon(
                Icons.mode_comment_outlined,
                size: 14,
                color: palette.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                '${post.comments}',
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


// ============================================================================
// Tab C: VIDEOS — community-shared long-form videos. Tap → full-screen
// player viewer. Currently dormant: the community detail screen is
// 2-tab (Posts + Members), so this widget is kept here as a quick
// re-enable for if/when the videos tab comes back.
// ============================================================================
// ignore: unused_element
class _CommunityVideosTab extends StatelessWidget {
  final List<ExpertVideo> videos;
  final Community community;
  const _CommunityVideosTab({
    required this.videos,
    required this.community,
  });

  @override
  Widget build(BuildContext context) {
    final viewsLabel = 'community.views'.tr;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: videos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => CompactVideoRow(
        video: videos[i],
        viewsLabel: viewsLabel,
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => VideoPlayerScreen(
                video: videos[i],
                community: community,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// Floating compose button — gradient pill matching the community accent.
// ============================================================================
class _ComposeFab extends StatelessWidget {
  final Color accent;
  final String label;
  final VoidCallback onTap;
  const _ComposeFab({
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
// Tab D: REELS — community-shared quick clips (TikTok-style 2-col grid).
// Tapping a tile opens the full-screen Reels player at that reel's index in
// the cross-community aggregated list, so users can swipe up/down through
// reels from EVERY community in one continuous TikTok-style flow.
// Same dormant status as the videos tab above.
// ============================================================================
// ignore: unused_element
class _CommunityReelsTab extends StatelessWidget {
  final List<ExpertReel> reels;
  const _CommunityReelsTab({required this.reels});

  void _openPlayer(BuildContext context, ExpertReel tapped) {
    final all = aggregateAllReels();
    var idx = all.indexWhere((fr) => fr.reel.id == tapped.id);
    if (idx < 0) idx = 0;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ReelsPlayerScreen(reels: all, initialIndex: idx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewsLabel = 'community.views'.tr;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 4 / 5,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: reels.length,
      itemBuilder: (_, i) {
        final r = reels[i];
        return ReelGridTile(
          reel: r,
          viewsLabel: viewsLabel,
          rank: i + 1, // top 3 get a gold trending badge
          onTap: () => _openPlayer(context, r),
        );
      },
    );
  }
}
// ============================================================================
// Tab C: MEMBERS — the roster, owner pinned to top.
//
// Step-23 follow-up: fetches the real member list from
// `/communities/:id/members` so newly-accepted paid subscribers (and
// fresh free joiners) show up immediately. Listens on the community
// realtime channel for `community_member_changed` so the tab patches
// itself live when the admin accepts a subscription elsewhere. Pull-
// to-refresh as a manual safety net.
// ============================================================================
class _CommunityMembersTab extends StatefulWidget {
  final Community community;
  final Color accent;
  final bool isArabic;
  final bool amOwner;
  const _CommunityMembersTab({
    required this.community,
    required this.accent,
    required this.isArabic,
    required this.amOwner,
  });

  @override
  State<_CommunityMembersTab> createState() => _CommunityMembersTabState();
}

class _CommunityMembersTabState extends State<_CommunityMembersTab> {
  List<CommunityMember> _members = const [];
  bool _loading = true;
  String? _error;
  StreamSubscription<RealtimeEvent>? _rtSub;

  @override
  void initState() {
    super.initState();
    _load();
    _wireRealtime();
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    super.dispose();
  }

  /// Listen for `community_member_changed` events on the active
  /// community channel and re-fetch on each one. Best-effort — when
  /// realtime isn't registered (offline dev / tests), the tab still
  /// works via initial load + pull-to-refresh.
  void _wireRealtime() {
    try {
      final rt = Get.find<RealtimeController>();
      _rtSub = rt.events.listen((ev) {
        if (ev.type != 'community_member_changed') return;
        final cid = ev.data['communityId']?.toString() ?? '';
        if (cid != widget.community.id) return;
        _load();
      });
    } catch (_) {
      // realtime not registered — pull-to-refresh covers the gap.
    }
  }

  /// Owner-only — confirm + fire DELETE /communities/:id/members/:userId,
  /// then prune the row from local state without a full refetch.
  Future<void> _confirmKick(CommunityMember m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('community.kick.title'.tr),
        content: Text(
          'community.kick.body'.trParams({'name': m.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE65A6E),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('common.remove'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await CommunityService.removeMember(
      widget.community.id,
      m.userId,
    );
    if (!mounted) return;
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'community.kick.removeFailed'.tr)),
      );
      return;
    }
    setState(() {
      _members = _members.where((x) => x.userId != m.userId).toList();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('community.kick.removed'.trParams({'name': m.name}))),
    );
  }

  Future<void> _load() async {
    final res = await CommunityService.listMembers(widget.community.id);
    if (!mounted) return;
    if (res.error != null || res.members == null) {
      setState(() {
        _loading = false;
        _error = res.error ?? 'community.members.loadError'.tr;
      });
      return;
    }
    // Convert real backend rows into the existing CommunityMember shape
    // so the row widget stays untouched.
    final converted = res.members!
        .map((r) => CommunityMember(
              userId: r.userId,
              name: r.name.isEmpty ? r.email.split('@').first : r.name,
              email: r.email,
              role: r.role,
              isOwner: r.isOwner,
              joinedAt: r.joinedAt,
            ))
        .toList()
      ..sort((a, b) {
        if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
        return b.joinedAt.compareTo(a.joinedAt);
      });
    setState(() {
      _loading = false;
      _members = converted;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    if (_loading && _members.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: widget.accent),
      );
    }
    if (_error != null && _members.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  color: palette.textMuted, size: 32),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textMuted),
              ),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: Text('common.retry'.tr),
              ),
            ],
          ),
        ),
      );
    }
    if (_members.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'community.members.empty'.tr,
                  style: TextStyle(color: palette.textMuted),
                ),
              ),
            ),
          ],
        ),
      );
    }
    // Group: experts on top (owner-first), then regular members.
    // Owner is always pinned at the top of the experts group if they
    // are an expert; if the owner is a USER (legacy), they go at the
    // top of the members group. We still keep is-owner sort intact
    // inside each group.
    final experts = _members
        .where((m) => m.role.toUpperCase() == 'EXPERT' || m.isOwner)
        .toList();
    final regulars = _members
        .where((m) => m.role.toUpperCase() != 'EXPERT' && !m.isOwner)
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          if (experts.isNotEmpty) ...[
            _MembersSectionHeader(
              icon: Icons.workspace_premium_rounded,
              label: 'community.members.experts'.tr,
              count: experts.length,
              accent: SocialTokens.gold,
            ),
            const SizedBox(height: 10),
            ...experts.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MemberRow(
                  member: m,
                  accent: widget.accent,
                  showEmail: widget.amOwner,
                  amOwner: widget.amOwner,
                  onKick: widget.amOwner ? () => _confirmKick(m) : null,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (regulars.isNotEmpty) ...[
            _MembersSectionHeader(
              icon: Icons.group_rounded,
              label: 'community.members.section'.tr,
              count: regulars.length,
              accent: widget.accent,
            ),
            const SizedBox(height: 10),
            ...regulars.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MemberRow(
                  member: m,
                  accent: widget.accent,
                  showEmail: widget.amOwner,
                  amOwner: widget.amOwner,
                  onKick: widget.amOwner ? () => _confirmKick(m) : null,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small pill-style header used to label the Experts / Members groups
/// in the community Members tab. Stays visually quiet — the row cards
/// below are what carry the eye.
class _MembersSectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color accent;
  const _MembersSectionHeader({
    required this.icon,
    required this.label,
    required this.count,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 13.5,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  final CommunityMember member;
  final Color accent;
  final bool showEmail;
  /// When true the trailing 3-dot menu offers "Remove member" so the
  /// community owner can kick. Self-rows (member.isOwner) suppress
  /// the menu even when amOwner is true — the owner can't kick
  /// themselves; they need to transfer ownership first.
  final bool amOwner;
  final VoidCallback? onKick;
  const _MemberRow({
    required this.member,
    required this.accent,
    required this.showEmail,
    this.amOwner = false,
    this.onKick,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: member.isOwner
              ? SocialTokens.gold.withValues(alpha: 0.4)
              : palette.border.withValues(alpha: 0.6),
          width: 0.7,
        ),
      ),
      child: Row(
        children: [
          _MemberAvatar(name: member.name, role: member.role, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (member.isOwner) ...[
                      const Icon(
                        Icons.workspace_premium_rounded,
                        size: 14,
                        color: SocialTokens.gold,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        member.name,
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
                    const SizedBox(width: 6),
                    _RoleBadge(role: member.role),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  showEmail
                      ? member.email
                      : 'community.members.joined'.trParams(
                          {'time': _relTime(member.joinedAt)}),
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          if (member.isOwner)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: SocialTokens.gold.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: SocialTokens.gold.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                'community.owner'.tr,
                style: const TextStyle(
                  color: SocialTokens.gold,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  letterSpacing: 0.4,
                ),
              ),
            )
          else if (amOwner && onKick != null)
            // 3-dot menu — only the community owner sees this, and
            // only on non-owner rows. Today's only entry is "Remove
            // member"; mute / ban / role-change can hang off the same
            // menu later without touching this layout.
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                size: 18,
                color: palette.textMuted,
              ),
              tooltip: 'community.actions'.tr,
              onSelected: (v) {
                if (v == 'kick') onKick?.call();
              },
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  value: 'kick',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person_remove_outlined,
                        size: 18,
                        color: Color(0xFFE65A6E),
                      ),
                      const SizedBox(width: 10),
                      Text('community.removeMember'.tr),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _relTime(DateTime t) => LocaleFormat.relative(t);
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final tone = _toneFor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tone.ring),
      ),
      child: Text(
        role,
        style: TextStyle(
          color: tone.fg,
          fontWeight: FontWeight.w900,
          fontSize: 9.5,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  ({Color bg, Color fg, Color ring}) _toneFor(String role) {
    switch (role.toUpperCase()) {
      case 'ADMIN':
        return (
          bg: SocialTokens.gold.withValues(alpha: 0.14),
          fg: SocialTokens.gold,
          ring: SocialTokens.gold.withValues(alpha: 0.4),
        );
      case 'EXPERT':
        return (
          bg: SocialTokens.cyan.withValues(alpha: 0.14),
          fg: SocialTokens.cyan,
          ring: SocialTokens.cyan.withValues(alpha: 0.4),
        );
      default:
        return (
          bg: const Color(0xFF94A3B8).withValues(alpha: 0.14),
          fg: const Color(0xFF94A3B8),
          ring: const Color(0xFF94A3B8).withValues(alpha: 0.4),
        );
    }
  }
}

// Shared avatar disc — used by both Chat bubbles and Members rows.
class _MemberAvatar extends StatelessWidget {
  final String name;
  final String role;
  final double size;
  const _MemberAvatar({
    required this.name,
    required this.role,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    Color tint;
    switch (role.toUpperCase()) {
      case 'ADMIN':
        tint = SocialTokens.gold;
        break;
      case 'EXPERT':
        tint = SocialTokens.cyan;
        break;
      default:
        tint = const Color(0xFF94A3B8);
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint.withValues(alpha: 0.18),
        border: Border.all(color: tint.withValues(alpha: 0.55)),
      ),
      child: Text(
        _initials(name),
        style: TextStyle(
          color: tint,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.42,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

// ============================================================================
// Owner manage sheet — bottom-sheet popped from the gear ⚙ in the
// AppBar. Only the "Members" entry is wired in v1; everything else is
// "coming soon" so the UI signals more management lives here later.
// ============================================================================
class _ManageSheet extends StatelessWidget {
  final Community community;
  final VoidCallback onJumpToMembers;
  const _ManageSheet({
    required this.community,
    required this.onJumpToMembers,
  });

  static Future<void> show(
    BuildContext context, {
    required Community community,
    required VoidCallback onJumpToMembers,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManageSheet(
        community: community,
        onJumpToMembers: onJumpToMembers,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: palette.border, width: 1),
          left: BorderSide(color: palette.border, width: 1),
          right: BorderSide(color: palette.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'community.manage.title'.tr,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                community.name,
                style: TextStyle(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 18),
              _ManageRow(
                icon: Icons.people_alt_rounded,
                label: 'community.manage.members'.tr,
                onTap: onJumpToMembers,
                palette: palette,
              ),
              // Step-19 (mig 0019, items 2.13–2.18) — owner can edit
              // the community's description, rules, cover image,
              // category, tags, and public/private toggle. All in one
              // sheet for fewer round-trips.
              _ManageRow(
                icon: Icons.edit_note_rounded,
                label: 'community.manage.editDescription'.tr,
                palette: palette,
                onTap: () async {
                  final saved = await CommunityEditSheet.show(
                    context,
                    communityId: community.id,
                  );
                  if (saved == true && context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('community.manage.updated'.tr),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              _ManageRow(
                icon: Icons.push_pin_outlined,
                label: 'community.manage.pinPost'.tr,
                onTap: null,
                palette: palette,
                comingSoon: true,
              ),
              _ManageRow(
                icon: Icons.person_remove_outlined,
                label: 'community.manage.removeMember'.tr,
                palette: palette,
                onTap: () {
                  Navigator.of(context).pop();
                  _MemberPickerSheet.show(
                    context,
                    community: community,
                    mode: _PickerMode.remove,
                  );
                },
              ),
              _ManageRow(
                icon: Icons.swap_horiz_rounded,
                label: 'community.manage.transferOwnership'.tr,
                palette: palette,
                onTap: () {
                  Navigator.of(context).pop();
                  _MemberPickerSheet.show(
                    context,
                    community: community,
                    mode: _PickerMode.transfer,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Picker for owner-only actions that need to point at one community
// member (kick, transfer ownership). Reused for both — the [mode]
// just changes the title, action label, and the API call wired to
// each row tap.
enum _PickerMode { remove, transfer }

class _MemberPickerSheet extends StatefulWidget {
  final Community community;
  final _PickerMode mode;
  const _MemberPickerSheet({required this.community, required this.mode});

  static Future<void> show(
    BuildContext context, {
    required Community community,
    required _PickerMode mode,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MemberPickerSheet(community: community, mode: mode),
    );
  }

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  bool _loading = true;
  String? _error;
  List<CommunityMemberRow> _members = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await CommunityService.listMembers(widget.community.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _members = res.members ?? const [];
      _error = res.error;
    });
  }

  /// Eligible rows for the active picker mode.
  ///
  /// * remove   → every member except the current owner. Owner can't
  ///              kick themselves; that's "transfer ownership", not
  ///              "remove member".
  /// * transfer → only EXPERT (or ADMIN) members. Mirrors the backend
  ///              rule in TransferCommunityOwnership — a regular USER
  ///              can't inherit owner-only powers.
  List<CommunityMemberRow> _eligibleMembers() {
    if (widget.mode == _PickerMode.remove) {
      return _members.where((m) => !m.isOwner).toList();
    }
    return _members
        .where((m) =>
            !m.isOwner &&
            (m.role.toUpperCase() == 'EXPERT' ||
                m.role.toUpperCase() == 'ADMIN'))
        .toList();
  }

  /// Confirmation dialog + API call for the chosen action. Returns
  /// to the picker on cancel; closes the picker on success.
  Future<void> _onPick(BuildContext ctx, CommunityMemberRow m) async {
    final palette = SocialTheme.of(ctx);
    final isRemove = widget.mode == _PickerMode.remove;
    final memberName = m.name.isEmpty ? m.email : m.name;
    final title = isRemove
        ? 'community.picker.confirmRemoveTitle'.tr
        : 'community.picker.confirmTransferTitle'.tr;
    final body = isRemove
        ? 'community.picker.confirmRemoveBody'.trParams({'name': memberName})
        : 'community.picker.confirmTransferBody'
            .trParams({'name': memberName});
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(
          title,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          body,
          style: TextStyle(color: palette.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('common.cancel'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              isRemove
                  ? 'community.picker.remove'.tr
                  : 'community.picker.transfer'.tr,
              style: TextStyle(
                color: isRemove
                    ? const Color(0xFFFF6B7A)
                    : SocialTokens.cyan,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    HapticFeedback.selectionClick();
    final res = isRemove
        ? await CommunityService.removeMember(widget.community.id, m.userId)
        : await CommunityService.transferOwnership(
            widget.community.id, m.userId);
    if (!mounted) return;
    if (!res.ok) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(res.error ?? 'community.actionFailed'.tr),
        ),
      );
      return;
    }
    Navigator.of(ctx).pop();
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          isRemove
              ? 'community.picker.removed'.tr
              : 'community.picker.transferred'.tr,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final isRemove = widget.mode == _PickerMode.remove;
    final title = isRemove
        ? 'community.picker.removeTitle'.tr
        : 'community.picker.transferTitle'.tr;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: palette.textMuted,
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                _error!,
                                style:
                                    TextStyle(color: palette.textPrimary),
                              ),
                            ),
                          )
                        : Builder(builder: (_) {
                          final eligible = _eligibleMembers();
                          if (eligible.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  widget.mode == _PickerMode.transfer
                                      ? 'community.picker.transferEmpty'.tr
                                      : 'community.picker.removeEmpty'.tr,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: palette.textMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            );
                          }
                          return ListView.builder(
                            itemCount: eligible.length,
                            itemBuilder: (_, i) {
                              final m = eligible[i];
                              // Owner can't pick themselves — that
                              // would be a no-op (kick) or an error
                              // (transfer to self). Render but disabled.
                              final auth = Get.find<AuthController>();
                              final isMe = m.userId == auth.user?.id;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: SocialTokens.cyan
                                      .withValues(alpha: 0.18),
                                  child: Text(
                                    (m.name.isEmpty
                                            ? m.email
                                            : m.name)
                                        .substring(0, 1)
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      color: SocialTokens.cyan,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  m.name.isEmpty ? m.email : m.name,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  m.isOwner
                                      ? 'community.owner'.tr
                                      : m.role,
                                  style: TextStyle(
                                    color: m.isOwner
                                        ? SocialTokens.gold
                                        : palette.textMuted,
                                    fontSize: 11,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                trailing: isMe
                                    ? const Icon(
                                        Icons.person_pin_rounded,
                                        color: SocialTokens.cyan,
                                      )
                                    : DirectionalIcon(
                                        Icons.chevron_right_rounded,
                                        color: palette.textMuted,
                                      ),
                                enabled: !isMe,
                                onTap: () => _onPick(context, m),
                              );
                            },
                          );
                        }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManageRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final SocialPalette palette;
  final bool comingSoon;
  const _ManageRow({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.palette,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: onTap == null
                    ? palette.textMuted.withValues(alpha: 0.5)
                    : palette.textPrimary,
                size: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: onTap == null
                        ? palette.textMuted.withValues(alpha: 0.7)
                        : palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
              if (comingSoon)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: palette.textMuted.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'community.manage.soon'.tr,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w900,
                      fontSize: 9.5,
                      letterSpacing: 0.5,
                    ),
                  ),
                )
              else
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
}

// ─── Join / Leave button ─────────────────────────────────────────
//
// Pill-shaped CTA shown on the community detail screen for any
// signed-in user who isn't the owner. State flips between two
// modes:
//
//   * Not joined → bold accent-filled "Join" button.
//   * Joined     → outlined "Joined ✓" button (tap to leave).
//
// Busy spinner replaces the icon while a request is in flight so
// the user can't double-tap.
class _MembershipButton extends StatelessWidget {
  final bool isMember;
  final bool busy;
  final Color accent;
  final SocialPalette palette;
  final VoidCallback onTap;

  const _MembershipButton({
    required this.isMember,
    required this.busy,
    required this.accent,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Member state shows "Joined ✓" with a small "Leave" hint pill
    // tucked on the right edge, signalling the row is tappable for
    // the leave action without burying the success state. Non-member
    // shows the prominent solid CTA.
    final label = isMember ? 'community.joined'.tr : 'community.joinCta'.tr;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isMember
                ? Colors.transparent
                : accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isMember
                  ? accent.withValues(alpha: 0.6)
                  : accent,
              width: isMember ? 1 : 1.4,
            ),
          ),
          child: Row(
            mainAxisAlignment: isMember
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    )
                  else
                    Icon(
                      isMember
                          ? Icons.check_rounded
                          : Icons.add_rounded,
                      size: 18,
                      color: accent,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              // Leave hint — only on the joined state. Quietly tells
              // the user "tapping this row opens the leave confirm".
              if (isMember && !busy)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: SocialTokens.down.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: SocialTokens.down.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.logout_rounded,
                        size: 12,
                        color: SocialTokens.down,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'community.leave'.tr,
                        style: const TextStyle(
                          color: SocialTokens.down,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
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

// ─── Experts in this community ──────────────────────────────────
//
// Horizontal scroll of expert cards rendered above the live ticker
// strip. Each card shows the expert's initials, name, expertise,
// subscriber count, and a View pill. Owner is starred with a gold
// gem and rendered first.
class _CommunityExpertsStrip extends StatelessWidget {
  final List<CommunityExpert> experts;
  final Color accent;
  final SocialPalette palette;

  const _CommunityExpertsStrip({
    required this.experts,
    required this.accent,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Icon(
                Icons.verified_rounded,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: 6),
              Text(
                'community.experts.title'.tr,
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
                  '${experts.length}',
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
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: experts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _CommunityExpertCard(
              expert: experts[i],
              accent: accent,
              palette: palette,
            ),
          ),
        ),
      ],
    );
  }
}

class _CommunityExpertCard extends StatelessWidget {
  final CommunityExpert expert;
  final Color accent;
  final SocialPalette palette;

  const _CommunityExpertCard({
    required this.expert,
    required this.accent,
    required this.palette,
  });

  String _initials(String n) {
    final parts = n.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String _compact(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    }
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final tint = expert.isOwner ? SocialTokens.gold : accent;
    return Container(
      width: 168,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.85),
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
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tint.withValues(alpha: 0.18),
                  border: Border.all(
                    color: tint.withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  _initials(expert.name),
                  style: TextStyle(
                    color: tint,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              if (expert.isOwner) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.workspace_premium_rounded,
                  size: 14,
                  color: SocialTokens.gold,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            expert.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            expert.expertise.isEmpty
                ? 'community.expertFallback'.tr
                : expert.expertise,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
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
                _compact(expert.subscriberCount),
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              // Subscribed-aware pill — Obx subscribes to the
              // controller's reactive map so a Subscribe/Cancel
              // anywhere in the app live-flips this card too.
              Obx(() {
                bool subscribed = false;
                try {
                  final ctrl = Get.find<SubscriptionController>();
                  subscribed =
                      ctrl.forExpert(expert.expertId)?.isActiveNow ?? false;
                } catch (_) {
                  // Controller not registered (unit tests etc.) —
                  // fall back to the View label.
                }
                final pillBg = subscribed
                    ? Colors.transparent
                    : tint.withValues(alpha: 0.18);
                final pillBorder = subscribed
                    ? tint.withValues(alpha: 0.5)
                    : Colors.transparent;
                final label = subscribed
                    ? 'community.subscribed'.tr
                    : 'community.view'.tr;
                return Material(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      // Same destination either way — the profile
                      // screen owns Subscribe / Cancel UI. Tapping
                      // a "Subscribed ✓" pill takes you to manage
                      // the subscription rather than re-subscribing.
                      ExpertProfileScreen.openForExpertId(
                        context,
                        expert.expertId,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: pillBorder,
                          width: subscribed ? 1 : 0,
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: tint,
                          fontWeight: FontWeight.w900,
                          fontSize: 10.5,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}
