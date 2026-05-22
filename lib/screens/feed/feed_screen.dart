import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/feed_controller.dart';
import '../../localization/locale_format.dart';
import '../../models/expert_post.dart';
import '../../services/events_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/social/comment_button.dart';
import '../../widgets/social/comments_sheet.dart';
import '../../widgets/social/like_button.dart';
import '../../widgets/social/notification_bell.dart';
import '../../widgets/social/report_sheet.dart';
import '../../widgets/social/save_button.dart';
import '../../widgets/social/source_badge.dart';
import '../profile/edit_profile_screen.dart';
import '../reels/reel_player_screen.dart';
import '../social/expert_profile_screen.dart';
import '../social/social_tokens.dart';
import 'reels_immersive_view.dart';

/// Bottom-nav **Feed** tab — every post from every expert the user has an
/// active subscription to, newest-first. Filter chips switch between All /
/// Articles / Videos / Reels.
///
/// All state lives in [FeedController] (registered permanent in main.dart),
/// which subscribes to the realtime event stream and reloads the list any
/// time a post lifecycle event or a subscription transition fires.
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final ctrl = Get.find<FeedController>();

    // Whole Scaffold flips between two modes:
    //   * Regular feed   — branded AppBar (Feed wordmark + filter dropdown
    //                      + bell + avatar) with a list of cards.
    //   * Reels mode     — no AppBar, edge-to-edge black, video paints
    //                      under the status bar; a slim translucent
    //                      back-arrow lives inside the immersive view.
    return Obx(() {
      final inReels = ctrl.filter == PostType.reel;
      return Scaffold(
        backgroundColor: inReels ? Colors.black : palette.background,
        appBar: inReels
            ? null
            : AppBar(
                backgroundColor: palette.background,
                elevation: 0,
                titleSpacing: 16,
                title: Row(
                  children: [
                    Text(
                      'feedTab.title'.tr,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _FilterDropdown(controller: ctrl, palette: palette),
                  ],
                ),
                actions: [
                  const NotificationBell(),
                  _ProfileAvatarButton(palette: palette),
                  const SizedBox(width: 6),
                ],
              ),
        // In reels mode we skip SafeArea on top so the video really paints
        // under the status bar. The status bar text stays readable thanks
        // to the system-default translucent overlay; the in-view exit bar
        // lives inside SafeArea so the back-arrow doesn't collide with
        // the time / signal indicators.
        body: SafeArea(
          top: !inReels,
          bottom: false,
          child: Column(
          children: [
            Expanded(
              child: Obx(() {
                if (ctrl.filter == PostType.reel) {
                  return const ReelsImmersiveView();
                }

                final posts = ctrl.posts;
                final loading = ctrl.loading;
                final fetched = ctrl.fetchedOk;

                if (loading && posts.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(
                          color: SocialTokens.cyan),
                    ),
                  );
                }

                if (posts.isEmpty) {
                  return RefreshIndicator(
                    color: SocialTokens.cyan,
                    onRefresh: ctrl.reload,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      children: [
                        _EmptyState(
                          palette: palette,
                          fetched: fetched,
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  color: SocialTokens.cyan,
                  onRefresh: ctrl.reload,
                  // NotificationListener fires loadMore when the user
                  // scrolls within 400px of the bottom — the threshold is
                  // small enough that the next page typically arrives
                  // before they even hit the end of the current one.
                  // The controller debounces duplicates internally.
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is ScrollUpdateNotification) {
                        final m = n.metrics;
                        if (m.pixels >= m.maxScrollExtent - 400) {
                          ctrl.loadMore();
                        }
                      }
                      return false;
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      itemCount: posts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) =>
                          _FeedPostCard(post: posts[i], palette: palette),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
        ),
      );
    });
  }
}

// ============================================================================
// Compact filter dropdown — replaces the old chip strip. Lives next to the
// "Feed" wordmark in the app bar so the body gets its full vertical real
// estate back. Tap → popup menu with All / Articles / Videos / Reels;
// the active option's icon + name is rendered on the trigger pill so the
// current filter is always visible at a glance.
// ============================================================================
class _FilterDropdown extends StatelessWidget {
  final FeedController controller;
  final SocialPalette palette;
  const _FilterDropdown({required this.controller, required this.palette});

  /// Modernized icon set — filled rounded variants. Articles uses
  /// text_snippet_rounded (closer to a real article preview than the
  /// outlined article icon), videos use smart_display (the YouTube-ish
  /// rounded play tile), reels use ondemand_video_rounded.
  ///
  /// The `key` field is a non-null sentinel used as the popup item's
  /// `value`. We can't use `PostType?` directly because Flutter's
  /// PopupMenuButton silently treats a `null` selection as "menu
  /// dismissed" and never fires `onSelected`. That bit us on the "All"
  /// option: clicking it did nothing. Strings sidestep the issue and
  /// we map them back to the nullable PostType at the call boundary.
  static const _options = [
    (labelKey: 'feedTab.filterAll', icon: Icons.dynamic_feed_rounded, type: null, key: 'all'),
    (labelKey: 'feedTab.filterArticles', icon: Icons.text_snippet_rounded, type: PostType.article, key: 'article'),
    (labelKey: 'feedTab.filterVideos', icon: Icons.smart_display_rounded, type: PostType.video, key: 'video'),
    (labelKey: 'feedTab.filterReels', icon: Icons.ondemand_video_rounded, type: PostType.reel, key: 'reel'),
  ];

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final active = controller.filter;
      final current = _options.firstWhere(
        (o) => o.type == active,
        orElse: () => _options.first,
      );

      return PopupMenuButton<String>(
        tooltip: 'feedTab.filterTooltip'.tr,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 6),
        color: palette.surface,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.border),
        ),
        onSelected: (key) {
          HapticUtils.pick();
          // Map the non-null sentinel back to the nullable PostType
          // setFilter expects. Falls back to "all" on an unknown key
          // (defensive — shouldn't happen because _options is closed).
          final picked = _options.firstWhere(
            (o) => o.key == key,
            orElse: () => _options.first,
          );
          controller.setFilter(picked.type);
        },
        itemBuilder: (_) => _options.map((o) {
          final selected = o.type == active;
          return PopupMenuItem<String>(
            value: o.key,
            child: Row(
              children: [
                Icon(
                  o.icon,
                  size: 18,
                  color: selected ? SocialTokens.cyan : palette.textPrimary,
                ),
                const SizedBox(width: 10),
                Text(
                  o.labelKey.tr,
                  style: TextStyle(
                    color:
                        selected ? SocialTokens.cyan : palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                if (selected) ...[
                  const Spacer(),
                  const Icon(Icons.check_rounded,
                      size: 16, color: SocialTokens.cyan),
                ],
              ],
            ),
          );
        }).toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: SocialTokens.cyan.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: SocialTokens.cyan.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(current.icon, size: 14, color: SocialTokens.cyan),
              const SizedBox(width: 6),
              Text(
                current.labelKey.tr,
                style: const TextStyle(
                  color: SocialTokens.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: SocialTokens.cyan,
              ),
            ],
          ),
        ),
      );
    });
  }
}

// ============================================================================
// _ProfileAvatarButton — small initials circle in the top-right of the app
// bar. Tapping opens the edit-profile screen so the user can quickly jump
// to "their account" without bottom-nav-tab switching.
// ============================================================================
class _ProfileAvatarButton extends StatelessWidget {
  final SocialPalette palette;
  const _ProfileAvatarButton({required this.palette});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return Obx(() {
      auth.userObservable.value; // tracker for re-renders
      final user = auth.user;
      final letter = ((user?.name ?? user?.email ?? '?')
              .trim()
              .characters
              .firstOrNull ??
          '?')
          .toUpperCase();

      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 4),
        child: InkWell(
          onTap: () {
            HapticUtils.tap();
            Get.to(() => const EditProfileScreen());
          },
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  SocialTokens.cyan,
                  SocialTokens.cyan.withValues(alpha: 0.6),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: SocialTokens.cyan.withValues(alpha: 0.55),
                width: 1.4,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              letter,
              style: const TextStyle(
                color: Color(0xFF0A1628),
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
      );
    });
  }
}

// ============================================================================
// Post card — same visual language as the live cards on expert profiles,
// with an extra "by Sarah ›" attribution row that taps through to the
// expert's profile.
// ============================================================================
class _FeedPostCard extends StatelessWidget {
  final ExpertPost post;
  final SocialPalette palette;
  const _FeedPostCard({required this.post, required this.palette});

  @override
  Widget build(BuildContext context) {
    // Articles get the Instagram-style layout — cover at top, actions in
    // a clean row, bold "23 likes" count, caption with author bold inline,
    // "View all N comments" link, and a small grey timestamp at the
    // bottom. Videos and reels keep the existing inline layout because
    // their cover-with-play-overlay treatment is already video-y.
    if (post.postType == PostType.article) {
      return _FeedArticleCard(post: post, palette: palette);
    }
    return _FeedMediaCard(post: post, palette: palette);
  }
}

/// Original feed-card layout, kept as `_FeedMediaCard` and reserved for
/// video / reel posts. Articles use [_FeedArticleCard] now.
class _FeedMediaCard extends StatelessWidget {
  final ExpertPost post;
  final SocialPalette palette;
  const _FeedMediaCard({required this.post, required this.palette});

  static const _accent = SocialTokens.cyan;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: palette.cardShadow(accent: _accent),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            gradient: palette.cardGradient(),
            borderRadius: BorderRadius.circular(18),
            border: palette.highlightedBorder(accent: _accent),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 4, color: _accent),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _attribution(context),
                    if (post.title != null && post.title!.isNotEmpty) ...[
                      const SizedBox(height: 10),
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
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (_hasMedia) ...[
                      const SizedBox(height: 12),
                      _mediaBox(),
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
                    _actions(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attribution(BuildContext context) {
    void openProfile() =>
        ExpertProfileScreen.openForExpertId(context, post.expertId);
    return Row(
      children: [
        GestureDetector(
          onTap: openProfile,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                colors: [_accent, _accent.withValues(alpha: 0.55)],
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
                fontSize: 12,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: openProfile,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  post.authorName.isEmpty
                      ? 'feedTab.expertFallback'.tr
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
                const SizedBox(height: 1),
                Text(
                  _relativeTime(post.createdAt),
                  style: TextStyle(color: palette.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _typeLabel(post.postType),
            style: TextStyle(
              color: _accent,
              fontWeight: FontWeight.w900,
              fontSize: 9,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );
  }

  bool get _hasMedia {
    final hasCover = post.coverUrl != null && post.coverUrl!.trim().isNotEmpty;
    final isVideoOrReel =
        post.postType == PostType.video || post.postType == PostType.reel;
    return hasCover || isVideoOrReel;
  }

  Widget _mediaBox() {
    final isReel = post.postType == PostType.reel;
    final isVideo = post.postType == PostType.video;
    final aspect = isReel ? (9 / 16) * 1.6 : 16 / 9;
    final cover = post.coverUrl?.trim() ?? '';
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
              Image.network(
                cover,
                fit: BoxFit.cover,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return Container(color: palette.surfaceElevated);
                },
                errorBuilder: (_, __, ___) =>
                    Container(color: palette.surfaceElevated),
              )
            else
              Container(color: palette.surfaceElevated),
            if (isVideo || isReel)
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0A1628).withValues(alpha: 0.55),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.85),
                      width: 1.4,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            if (post.durationSeconds != null && post.durationSeconds! > 0)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
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
              coverUrl: post.coverUrl,
              title: post.title,
              authorName: post.authorName,
            ));
      },
      child: media,
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
          const Icon(Icons.show_chart_rounded,
              size: 11, color: SocialTokens.cyan),
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

  Widget _actions() {
    return Row(
      children: [
        LikeButton(post: post, accent: _accent, mutedColor: palette.textMuted),
        const SizedBox(width: 12),
        CommentButton(
            post: post, accent: _accent, mutedColor: palette.textMuted),
        const Spacer(),
        SaveButton(post: post, accent: _accent, mutedColor: palette.textMuted),
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

  String _typeLabel(PostType t) {
    switch (t) {
      case PostType.article:
        return 'feedTab.badgeArticle'.tr;
      case PostType.video:
        return 'feedTab.badgeVideo'.tr;
      case PostType.reel:
        return 'feedTab.badgeReel'.tr;
    }
  }

  String _relativeTime(DateTime t) => LocaleFormat.relative(t);

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ============================================================================
// _FeedArticleCard — Instagram-style article post.
//
// Layout:
//   ▸ Compact header: avatar + bold name + time + visibility chip + ⋯
//   ▸ Cover image (4:3, edge-to-edge). When the article has no cover,
//     a typographic hero card takes its place so every article still
//     has a strong visual anchor.
//   ▸ Action row: heart, comment, share | save (clean, no divider, no
//     count beside the icons).
//   ▸ "23 likes" line in bold (hidden when count is 0).
//   ▸ Caption block:
//        • Title (bold, larger), if present.
//        • Body (regular). Long bodies clamp to 3 lines with a "more"
//          tail; tap to expand inline.
//        • "View all 12 comments" link → opens the comments sheet.
//        • Tickers as compact chips.
//   ▸ Timestamp: small grey at the bottom.
// ============================================================================
class _FeedArticleCard extends StatefulWidget {
  final ExpertPost post;
  final SocialPalette palette;

  const _FeedArticleCard({required this.post, required this.palette});

  @override
  State<_FeedArticleCard> createState() => _FeedArticleCardState();
}

class _FeedArticleCardState extends State<_FeedArticleCard> {
  static const _accent = SocialTokens.cyan;
  static const _bodyClampLines = 3;

  bool _expanded = false;

  /// Pop the native OS share sheet via `share_plus`. The URL won't
  /// resolve to the app yet — deep-link routing arrives next milestone
  /// — but the shape is already correct so existing shares stay valid.
  /// Post overflow menu. Opens a small action sheet from the bottom
  /// with the "Report" action; the report flow itself is delegated to
  /// [ReportSheet] which handles reason selection + submission.
  Future<void> _showPostMenu(BuildContext sheetCtx, ExpertPost p) async {
    HapticUtils.lightTap();
    final author =
        p.authorName.trim().isEmpty ? 'feedTab.thisExpert'.tr : p.authorName;
    await showModalBottomSheet<void>(
      context: sheetCtx,
      backgroundColor: Theme.of(sheetCtx).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(
                Icons.flag_outlined,
                color: Color(0xFFE65A6E),
              ),
              title: Text('feedTab.reportPost'.tr),
              subtitle: Text(
                'feedTab.flagForModeration'.trParams({'author': author}),
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await Future<void>.delayed(
                  const Duration(milliseconds: 80),
                );
                if (!sheetCtx.mounted) return;
                final ok = await ReportSheet.show(
                  sheetCtx,
                  targetType: 'post',
                  targetId: p.id.toString(),
                  targetLabel: 'feedTab.thisPost'.tr,
                );
                if (ok && sheetCtx.mounted) {
                  ScaffoldMessenger.of(sheetCtx).showSnackBar(
                    SnackBar(
                      content: Text('feedTab.reportThanks'.tr),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _sharePost(BuildContext btnContext, ExpertPost p) async {
    HapticUtils.tap();
    final title = (p.title ?? '').trim();
    final author = p.authorName.trim().isEmpty
        ? 'feedTab.shareExpertFallback'.tr
        : p.authorName.trim();
    final body = title.isEmpty
        ? 'feedTab.shareBodyNoTitle'.trParams({'author': author})
        : 'feedTab.shareBodyWithTitle'
            .trParams({'title': title, 'author': author});
    final url = 'https://unmu.app/p/${p.id}';
    // share_plus needs a non-empty rectangle on iPad where the share
    // sheet anchors to a popover — pass the rendered button bounds.
    final box = btnContext.findRenderObject() as RenderBox?;
    // Fire-and-forget admin instrumentation.
    unawaited(EventsService.logShare(p.id));
    await Share.share(
      '$body\n\n$url',
      subject: title.isEmpty ? 'feedTab.shareSubjectFallback'.tr : title,
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final palette = widget.palette;
    final hasCover = p.coverUrl != null && p.coverUrl!.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: palette.cardShadow(accent: _accent),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: palette.highlightedBorder(accent: _accent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(palette),
              // Source badge — between header and media. Tells the
              // viewer at a glance whether this came from an expert's
              // profile or a community. Auto-hides for posts with no
              // source metadata (older mock paths).
              if (p.isFromCommunity || p.isFromExpertProfile)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SourceBadge.compact(
                      targetType: p.isFromCommunity
                          ? 'community'
                          : 'expert',
                      communityId: p.communityId,
                      communityName: p.communityName,
                      communityRegionCode: p.communityRegionCode,
                      expertId: p.expertId,
                      expertName: p.expertName.isEmpty
                          ? p.authorName
                          : p.expertName,
                    ),
                  ),
                ),
              if (hasCover) _coverImage(p, palette) else _typographicHero(p, palette),
              _actionRow(p, palette),
              if (p.likes > 0) _likeCountLine(p, palette),
              _captionBlock(p, palette),
              if (p.comments > 0) _viewAllCommentsLink(context, p, palette),
              if (p.tickers.isNotEmpty) _tickerStrip(p),
              _timestamp(p, palette),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────
  Widget _header(SocialPalette palette) {
    final p = widget.post;
    // Tappable region around the avatar + author name → opens the
    // expert's profile so users can see their bio, stats, and full
    // post catalog.
    void openProfile() =>
        ExpertProfileScreen.openForExpertId(context, p.expertId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: openProfile,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [_accent, _accent.withValues(alpha: 0.55)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials(p.authorName),
                style: const TextStyle(
                  color: Color(0xFF0A1628),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: GestureDetector(
                    onTap: openProfile,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      p.authorName.isEmpty
                          ? 'feedTab.expertFallback'.tr
                          : p.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '· ${_relativeTime(p.createdAt)}',
                  style: TextStyle(color: palette.textMuted, fontSize: 11),
                ),
                const SizedBox(width: 6),
                if (p.visibility == PostVisibility.subscribersOnly)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _accent.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      'feedTab.subsBadge'.tr,
                      style: const TextStyle(
                        color: _accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Overflow menu — wraps an IconButton so the same Icon stays
          // visually centered in the header row while gaining tap target.
          // Today's entries: Report. We can fan in Hide / Mute / Block
          // later without touching the surrounding layout.
          IconButton(
            tooltip: 'feedTab.moreTooltip'.tr,
            icon: Icon(
              Icons.more_horiz_rounded,
              size: 20,
              color: palette.textMuted,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => _showPostMenu(context, p),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  // ── Cover image (4:3) ─────────────────────────────────────────────
  Widget _coverImage(ExpertPost p, SocialPalette palette) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Image.network(
        p.coverUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return Container(color: palette.surfaceElevated);
        },
        errorBuilder: (_, __, ___) => _typographicHero(p, palette),
      ),
    );
  }

  /// Used when the article has no cover — gives every article a strong
  /// visual hook even without an image. Gradient + the title in big
  /// bold text, centered.
  Widget _typographicHero(ExpertPost p, SocialPalette palette) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _accent.withValues(alpha: 0.22),
              const Color(0xFF0A1628),
            ],
          ),
        ),
        padding: const EdgeInsets.all(28),
        alignment: Alignment.center,
        child: Text(
          (p.title ?? '').isNotEmpty ? p.title! : 'feedTab.articleFallback'.tr,
          textAlign: TextAlign.center,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: -0.4,
            height: 1.25,
            shadows: const [
              Shadow(color: Colors.black54, blurRadius: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ── Action row (heart / comment / share | save) ──────────────────
  Widget _actionRow(ExpertPost p, SocialPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Row(
        children: [
          LikeButton(
            post: p,
            accent: _accent,
            mutedColor: palette.textPrimary,
            iconSize: 26,
            showCount: false,
          ),
          const SizedBox(width: 10),
          CommentButton(
            post: p,
            accent: _accent,
            mutedColor: palette.textPrimary,
            iconSize: 24,
            showCount: false,
          ),
          const SizedBox(width: 10),
          // Share — pops the native OS share sheet via share_plus
          // (UIActivityViewController on iOS, Intent.ACTION_SEND on
          // Android). The deep-link URL won't resolve to the app yet —
          // that arrives with the deep-link routing milestone — but the
          // shape is already correct so existing shares stay valid.
          Builder(
            builder: (btnContext) => InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _sharePost(btnContext, p),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.ios_share_rounded,
                  size: 22,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
          const Spacer(),
          SaveButton(
            post: p,
            accent: _accent,
            mutedColor: palette.textPrimary,
          ),
        ],
      ),
    );
  }

  // ── "23 likes" bold line ─────────────────────────────────────────
  Widget _likeCountLine(ExpertPost p, SocialPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: Text(
        '${_formatCount(p.likes)} '
        '${p.likes == 1 ? 'feedTab.likeOne'.tr : 'feedTab.likeMany'.tr}',
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.w900,
          fontSize: 13.5,
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  // ── Caption: title (bold) + body (regular) + inline "more" ────────
  Widget _captionBlock(ExpertPost p, SocialPalette palette) {
    final title = p.title?.trim();
    final body = p.body.trim();
    if ((title == null || title.isEmpty) && body.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title.isNotEmpty)
            Text(
              title,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: -0.3,
                height: 1.3,
              ),
            ),
          if (body.isNotEmpty) ...[
            if (title != null && title.isNotEmpty) const SizedBox(height: 4),
            // Body — clamps to 3 lines until expanded. The "more" tail
            // appears as a subtle muted suffix; tapping anywhere on the
            // body toggles expansion.
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topLeft,
                child: _expanded
                    ? Text(
                        body,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13.5,
                          height: 1.45,
                        ),
                      )
                    : Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: body,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 13.5,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                        maxLines: _bodyClampLines,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ),
            if (!_expanded && _bodyLikelyTruncates(body))
              GestureDetector(
                onTap: () => setState(() => _expanded = true),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'feedTab.more'.tr,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Heuristic — if the body is long enough that 3 lines won't fit it,
  /// show the "more" affordance. Avoids using a TextPainter (cheap +
  /// "good enough" — over-trigger is fine, under-trigger is the bug to
  /// avoid). Tuned around ~50 chars per line on a typical phone width.
  bool _bodyLikelyTruncates(String body) {
    return body.length > 150 || '\n'.allMatches(body).length > 2;
  }

  // ── "View all N comments" link ───────────────────────────────────
  Widget _viewAllCommentsLink(
    BuildContext context,
    ExpertPost p,
    SocialPalette palette,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: GestureDetector(
        onTap: () {
          CommentsSheet.show(
            context,
            postId: p.id,
            postOwnerExpertId: p.expertId,
            accent: _accent,
          );
        },
        behavior: HitTestBehavior.opaque,
        child: Text(
          (p.comments == 1
                  ? 'feedTab.viewAllCommentsOne'
                  : 'feedTab.viewAllCommentsMany')
              .trParams({'count': _formatCount(p.comments)}),
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ── Ticker chips ──────────────────────────────────────────────────
  Widget _tickerStrip(ExpertPost p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: p.tickers.map((t) => _tickerChip(t)).toList(),
      ),
    );
  }

  Widget _tickerChip(String t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.show_chart_rounded, size: 11, color: _accent),
          const SizedBox(width: 4),
          Text(
            '\$$t',
            style: const TextStyle(
              color: _accent,
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Timestamp (small grey) ────────────────────────────────────────
  Widget _timestamp(ExpertPost p, SocialPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Text(
        _absoluteish(p.createdAt),
        style: TextStyle(
          color: palette.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────
  static String _formatCount(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  static String _relativeTime(DateTime t) => LocaleFormat.relative(t);

  /// Bottom timestamp — Instagram pattern: "2 HOURS AGO" all-caps grey.
  static String _absoluteish(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) {
      final m = d.inMinutes.clamp(1, 59);
      return (m == 1 ? 'feedTab.minuteAgoOne' : 'feedTab.minuteAgoMany')
          .trParams({'count': '$m'});
    }
    if (d.inHours < 24) {
      final h = d.inHours;
      return (h == 1 ? 'feedTab.hourAgoOne' : 'feedTab.hourAgoMany')
          .trParams({'count': '$h'});
    }
    if (d.inDays < 7) {
      final dd = d.inDays;
      return (dd == 1 ? 'feedTab.dayAgoOne' : 'feedTab.dayAgoMany')
          .trParams({'count': '$dd'});
    }
    final w = (d.inDays / 7).floor();
    return (w == 1 ? 'feedTab.weekAgoOne' : 'feedTab.weekAgoMany')
        .trParams({'count': '$w'});
  }
}

// ============================================================================
// Empty state — separate copy for "fetched, no subs" vs "couldn't reach".
// ============================================================================
class _EmptyState extends StatelessWidget {
  final SocialPalette palette;
  final bool fetched;
  const _EmptyState({required this.palette, required this.fetched});

  @override
  Widget build(BuildContext context) {
    final title = fetched
        ? 'feedTab.emptyTitle'.tr
        : 'feedTab.errorTitle'.tr;
    final subtitle = fetched
        ? 'feedTab.emptySubtitle'.tr
        : 'feedTab.errorSubtitle'.tr;
    final icon = fetched ? Icons.workspace_premium_rounded : Icons.cloud_off_rounded;
    final color = fetched ? SocialTokens.cyan : palette.textMuted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 90, 32, 60),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 32, color: color),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
