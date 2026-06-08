import 'package:flutter/material.dart';
import '../../widgets/directional_icon.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/app_config_controller.dart';
import '../../controllers/expert_dashboard_controller.dart';
import '../../localization/locale_format.dart';
import '../../models/community_proposal.dart';
import '../../models/expert_post.dart';
import '../../services/community_proposal_service.dart';
import '../../services/expert_post_service.dart';
import '../../services/studio_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/common/app_network_image.dart';
import '../interactions/post_interactions_screen.dart';
import '../reels/reel_player_screen.dart';
import 'create_post_screen.dart';
import 'drafts_screen.dart';
import 'earnings_screen.dart';
import 'edit_pricing_sheet.dart';
import 'propose_community_sheet.dart';

/// Expert "Studio" — your posts, your stats, the quick "+ New Post" button.
///
/// Reachable from the Profile screen (only when `auth.user.isExpert` is true).
/// All state lives in [ExpertDashboardController]; the screen wraps reactive
/// regions in `Obx`.
class ExpertDashboardScreen extends StatefulWidget {
  const ExpertDashboardScreen({super.key});

  @override
  State<ExpertDashboardScreen> createState() => _ExpertDashboardScreenState();
}

class _ExpertDashboardScreenState extends State<ExpertDashboardScreen> {
  late final ExpertDashboardController controller;

  @override
  void initState() {
    super.initState();
    // Lazily register the controller so it's torn down when no studio screen
    // is on the stack. Keeps memory tight.
    controller = Get.put(ExpertDashboardController(), tag: 'studio');
    controller.refreshPosts();
    // Fire-and-forget — the metrics row renders an inline spinner
    // until this resolves, so we don't await it.
    controller.refreshDashboard();
  }

  @override
  void dispose() {
    Get.delete<ExpertDashboardController>(tag: 'studio');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('dashboard.title'.tr),
        actions: [
          // Step-20 (mig 0020, item 4.15) — quick jump into the drafts
          // + scheduled posts list. Bookmark icon mirrors the
          // "save as draft" affordance in the composer.
          IconButton(
            tooltip: 'dashboard.draftsTooltip'.tr,
            icon: const Icon(Icons.bookmark_outline_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DraftsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: controller.refreshPosts,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: Text('dashboard.newPost'.tr),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              controller.refreshPosts(),
              controller.refreshDashboard(),
            ]);
          },
          child: Obx(() {
            // Reading reactive state up-front so Obx tracker sees every Rx.
            final loading = controller.isLoading;
            final error = controller.error;
            final posts = controller.posts;
            final filter = controller.activeType;

            return ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // "Propose a community" CTA + "My proposals" list.
                // Manages its own state (loads via /me/community-proposals
                // on mount, prepends after a successful submit). Lives at
                // the top of the studio because creating a community is a
                // higher-intent action than publishing a post.
                const _ProposalsSection(),
                const SizedBox(height: 18),
                // Real metrics (Phase 3.1) — subscribers, revenue, engagement.
                // Falls back to a slim post-count row when the dashboard
                // call is still in flight on first open.
                _MetricsBlock(controller: controller),
                const SizedBox(height: 12),
                _PricingTile(controller: controller),
                const SizedBox(height: 12),
                _EarningsTile(controller: controller),
                const SizedBox(height: 18),
                _StatsRow(
                  total: posts.length,
                  articles: controller.articleCount,
                  videos: controller.videoCount,
                  reels: controller.reelCount,
                ),
                const SizedBox(height: 16),
                _FilterTabs(
                  active: filter,
                  onChange: controller.setFilter,
                ),
                const SizedBox(height: 12),
                if (loading && posts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (error != null && posts.isEmpty)
                  _EmptyState(
                    icon: Icons.error_outline,
                    title: 'dashboard.couldNotLoadPosts'.tr,
                    subtitle: error,
                  )
                else if (posts.isEmpty)
                  _EmptyState(
                    icon: Icons.edit_note_outlined,
                    title: 'dashboard.noPostsTitle'.tr,
                    subtitle: 'dashboard.noPostsSubtitle'.tr,
                  )
                else
                  ...posts.map((p) => _PostTile(
                        post: p,
                        controller: controller,
                      )),
              ],
            );
          }),
        ),
      ),
    );
  }

  Future<void> _openCreate() async {
    final result = await Navigator.of(context).push<ExpertPost>(
      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
    );
    if (result != null) controller.prepend(result);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final int total;
  final int articles;
  final int videos;
  final int reels;
  const _StatsRow({
    required this.total,
    required this.articles,
    required this.videos,
    required this.reels,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatCard(label: 'dashboard.statTotal'.tr, value: '$total')),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(label: 'dashboard.statArticles'.tr, value: '$articles')),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(label: 'dashboard.statVideos'.tr, value: '$videos')),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(label: 'dashboard.statReels'.tr, value: '$reels')),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  final PostType? active;
  final ValueChanged<PostType?> onChange;
  const _FilterTabs({required this.active, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Chip(label: 'dashboard.filterAll'.tr, selected: active == null, onTap: () => onChange(null)),
          const SizedBox(width: 8),
          _Chip(
            label: 'dashboard.filterArticles'.tr,
            selected: active == PostType.article,
            onTap: () => onChange(PostType.article),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'dashboard.filterVideos'.tr,
            selected: active == PostType.video,
            onTap: () => onChange(PostType.video),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'dashboard.filterReels'.tr,
            selected: active == PostType.reel,
            onTap: () => onChange(PostType.reel),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.18)
              : cs.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? cs.primary : cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  final ExpertPost post;
  final ExpertDashboardController controller;
  const _PostTile({required this.post, required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isReel = post.postType == PostType.reel;
    final isVideo = post.postType == PostType.video;
    final hasMedia = post.coverUrl != null && post.coverUrl!.isNotEmpty;

    return Opacity(
      // Subtle dim to make hidden posts visually distinct without burying
      // them — the owner still needs to find and manage them.
      opacity: post.isHidden ? 0.65 : 1.0,
      child: GestureDetector(
        // Tap on the body of the tile (anywhere not handled by an inner
        // gesture — kebab menu, cover-play, etc.) opens the post's
        // interactions screen with Likes / Comments tabs. The kebab
        // PopupMenuButton and the cover's GestureDetector take
        // precedence because Flutter dispatches inner-first.
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticUtils.tap();
          Get.to(() => PostInteractionsScreen(post: post));
        },
        child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: post.isHidden
                ? Colors.redAccent.withValues(alpha: 0.45)
                : cs.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          if (hasMedia)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if ((isVideo || isReel) &&
                    post.mediaUrl != null &&
                    post.mediaUrl!.trim().isNotEmpty) {
                  HapticFeedback.lightImpact();
                  Get.to(() => ReelPlayerScreen(
                        mediaUrl: post.mediaUrl!,
                        qualityVariants: post.videoVariants,
                        expectedDurationSeconds: post.durationSeconds,
                        coverUrl: post.coverUrl,
                        title: post.title,
                        authorName: post.authorName,
                      ));
                }
              },
              child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: AspectRatio(
                aspectRatio: isReel ? 9 / 16 * 2.2 : 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppNetworkImage(
                      post.coverUrl!,
                      fit: BoxFit.cover,
                      placeholderColor: cs.surface,
                      errorWidget: Container(color: cs.surface),
                    ),
                    if (isVideo || isReel)
                      const Center(
                        child: CircleAvatar(
                          radius: 24,
                          child: Icon(Icons.play_arrow_rounded, size: 28),
                        ),
                      ),
                    Positioned(
                      top: 8, left: 8,
                      child: _Pill(
                        text: post.postType.displayName.toUpperCase(),
                        color: cs.primary,
                      ),
                    ),
                    Positioned(
                      top: 8, right: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (post.isHidden) ...[
                            _Pill(text: 'dashboard.pillHidden'.tr, color: Colors.redAccent),
                            const SizedBox(width: 6),
                          ],
                          _Pill(
                            text: post.visibility == PostVisibility.public
                                ? 'dashboard.pillPublic'.tr
                                : 'dashboard.pillSubsOnly'.tr,
                            color: post.visibility == PostVisibility.public
                                ? Colors.green
                                : Colors.amber,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hasMedia)
                  Row(
                    children: [
                      _Pill(text: post.postType.displayName.toUpperCase(), color: cs.primary),
                      const SizedBox(width: 6),
                      _Pill(
                        text: post.visibility == PostVisibility.public
                            ? 'dashboard.pillPublic'.tr
                            : 'dashboard.pillSubsOnly'.tr,
                        color: post.visibility == PostVisibility.public
                            ? Colors.green
                            : Colors.amber,
                      ),
                      if (post.isHidden) ...[
                        const SizedBox(width: 6),
                        _Pill(text: 'dashboard.pillHidden'.tr, color: Colors.redAccent),
                      ],
                      const Spacer(),
                      _StudioActionMenu(post: post, controller: controller),
                    ],
                  ),
                if (!hasMedia) const SizedBox(height: 8),
                if (hasMedia)
                  // When media is shown, the kebab lives at the top of the
                  // text column so it stays reachable without overlapping
                  // the cover art.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Spacer(),
                        _StudioActionMenu(post: post, controller: controller),
                      ],
                    ),
                  ),
                if (post.title != null && post.title!.isNotEmpty)
                  Text(
                    post.title!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                if (post.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    post.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    _MetaIcon(icon: Icons.favorite_outline, value: post.likes),
                    const SizedBox(width: 12),
                    _MetaIcon(icon: Icons.comment_outlined, value: post.comments),
                    const Spacer(),
                    Text(
                      LocaleFormat.relative(post.createdAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
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

// ─────────────────────────────────────────────────────────────────────────────
// Studio action menu — kebab dropdown with Edit / Hide / Delete shown next
// to every post the expert authored. Uses optimistic local updates via the
// controller so the UI feels snappy even when the network call is in flight.
// ─────────────────────────────────────────────────────────────────────────────
class _StudioActionMenu extends StatelessWidget {
  final ExpertPost post;
  final ExpertDashboardController controller;
  const _StudioActionMenu({required this.post, required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<_StudioAction>(
      tooltip: 'dashboard.menuTooltip'.tr,
      icon: Icon(Icons.more_horiz_rounded, size: 20, color: cs.onSurfaceVariant),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: (action) => _handle(context, action),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _StudioAction.edit,
          child: Row(
            children: [
              const Icon(Icons.edit_rounded, size: 16),
              const SizedBox(width: 10),
              Text('dashboard.actionEdit'.tr),
            ],
          ),
        ),
        PopupMenuItem(
          value: _StudioAction.toggleHide,
          child: Row(
            children: [
              Icon(
                post.isHidden
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                size: 16,
              ),
              const SizedBox(width: 10),
              Text(post.isHidden ? 'dashboard.actionUnhide'.tr : 'dashboard.actionHide'.tr),
            ],
          ),
        ),
        PopupMenuItem(
          value: _StudioAction.delete,
          child: Row(
            children: [
              const Icon(Icons.delete_outline_rounded,
                  size: 16, color: Color(0xFFE65A6E)),
              const SizedBox(width: 10),
              Text('dashboard.actionDelete'.tr, style: const TextStyle(color: Color(0xFFE65A6E))),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handle(BuildContext context, _StudioAction action) async {
    HapticFeedback.lightImpact();
    switch (action) {
      case _StudioAction.edit:
        await _edit(context);
        break;
      case _StudioAction.toggleHide:
        await _toggleHide(context);
        break;
      case _StudioAction.delete:
        await _confirmAndDelete(context);
        break;
    }
  }

  Future<void> _edit(BuildContext context) async {
    final updated = await Navigator.of(context).push<ExpertPost>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CreatePostScreen.edit(post: post),
      ),
    );
    if (updated != null) {
      controller.replace(updated);
    }
  }

  Future<void> _toggleHide(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ExpertPostService.setHidden(
      expertId: post.expertId,
      postId: post.id,
      hidden: !post.isHidden,
    );
    if (result.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    if (result.post != null) controller.replace(result.post!);
    messenger.showSnackBar(
      SnackBar(
        content: Text(post.isHidden
            ? 'dashboard.nowVisible'.tr
            : 'dashboard.nowHidden'.tr),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmAndDelete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('dashboard.deletePostTitle'.tr),
        content: Text(
          'dashboard.deletePostBody'.tr,
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
            child: Text('common.delete'.tr),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await ExpertPostService.delete(
      expertId: post.expertId,
      postId: post.id,
    );
    if (err != null) {
      messenger.showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    controller.removeById(post.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text('dashboard.postDeleted'.tr),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

enum _StudioAction { edit, toggleHide, delete }

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _MetaIcon extends StatelessWidget {
  final IconData icon;
  final int value;
  const _MetaIcon({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          '$value',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Community-proposals section — lives at the top of the studio.
//
// Renders:
//   • A "Create new community" CTA card — opens ProposeCommunitySheet
//   • A horizontal scroll of "My proposals" status tiles (only when the
//     user has submitted at least one proposal)
//
// Loads via `/api/me/community-proposals` on mount. A successful submit
// pops back with the new proposal which we prepend optimistically so the
// user sees their PENDING row instantly.
// ============================================================================
class _ProposalsSection extends StatefulWidget {
  const _ProposalsSection();

  @override
  State<_ProposalsSection> createState() => _ProposalsSectionState();
}

class _ProposalsSectionState extends State<_ProposalsSection> {
  List<CommunityProposal> _proposals = const [];
  bool _loading = true;

  bool get _hasPending =>
      _proposals.any((p) => p.status == ProposalStatus.pending);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await CommunityProposalService.listMine();
    if (!mounted) return;
    setState(() {
      _proposals = list;
      _loading = false;
    });
  }

  Future<void> _openSheet() async {
    HapticUtils.lightTap();
    final created = await ProposeCommunitySheet.show(context);
    if (created != null && mounted) {
      // Optimistic prepend so the user sees their PENDING row instantly
      // — the next visit will also re-fetch via `_load()` for correctness.
      setState(() {
        _proposals = [created, ..._proposals];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Community kill-switch — hide the whole "create community" section
    // (CTA + my-proposals) when the admin has disabled communities.
    if (!Get.find<AppConfigController>().communityEnabled.value) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CreateCommunityCard(
          enabled: !_hasPending,
          pending: _hasPending,
          onTap: _hasPending ? null : _openSheet,
        ),
        if (!_loading && _proposals.isNotEmpty) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 2, bottom: 8),
            child: Text(
              'dashboard.myProposals'.tr,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.2,
              ),
            ),
          ),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: _proposals.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _ProposalTile(proposal: _proposals[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _CreateCommunityCard extends StatelessWidget {
  final bool enabled;
  final bool pending;
  final VoidCallback? onTap;
  const _CreateCommunityCard({
    required this.enabled,
    required this.pending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: enabled
                  ? [
                      cs.primary.withValues(alpha: 0.18),
                      cs.primary.withValues(alpha: 0.06),
                    ]
                  : [
                      cs.surfaceContainerHighest.withValues(alpha: 0.40),
                      cs.surfaceContainerHighest.withValues(alpha: 0.20),
                    ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled
                  ? cs.primary.withValues(alpha: 0.55)
                  : cs.outlineVariant.withValues(alpha: 0.40),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: enabled
                      ? cs.primary.withValues(alpha: 0.18)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.50),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: enabled
                        ? cs.primary.withValues(alpha: 0.50)
                        : cs.outlineVariant.withValues(alpha: 0.50),
                  ),
                ),
                child: Icon(
                  pending
                      ? Icons.hourglass_top_rounded
                      : Icons.add_business_rounded,
                  color: enabled ? cs.primary : cs.onSurfaceVariant,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pending
                          ? 'dashboard.proposalAwaiting'.tr
                          : 'dashboard.createCommunity'.tr,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      pending
                          ? 'dashboard.proposalAwaitingSub'.tr
                          : 'dashboard.createCommunitySub'.tr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (!pending)
                DirectionalIcon(
                  Icons.arrow_forward_rounded,
                  color: cs.primary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProposalTile extends StatelessWidget {
  final CommunityProposal proposal;
  const _ProposalTile({required this.proposal});

  ({Color color, IconData icon, String label}) _statusVisuals() {
    switch (proposal.status) {
      case ProposalStatus.pending:
        return (
          color: const Color(0xFFE6BD0F), // gold
          icon: Icons.hourglass_top_rounded,
          label: 'dashboard.statusPending'.tr,
        );
      case ProposalStatus.approved:
        return (
          color: const Color(0xFF10B981), // green
          icon: Icons.check_circle_rounded,
          label: 'dashboard.statusApproved'.tr,
        );
      case ProposalStatus.rejected:
        return (
          color: const Color(0xFFEF4444), // red
          icon: Icons.cancel_rounded,
          label: 'dashboard.statusRejected'.tr,
        );
      case ProposalStatus.unknown:
        return (
          color: const Color(0xFF94A0B5), // muted
          icon: Icons.help_outline_rounded,
          label: 'dashboard.statusUnknown'.tr,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = _statusVisuals();
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: v.color.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(v.icon, color: v.color, size: 14),
              const SizedBox(width: 4),
              Text(
                v.label,
                style: TextStyle(
                  color: v.color,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            proposal.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            proposal.status == ProposalStatus.rejected &&
                    proposal.rejectionReason.isNotEmpty
                ? 'dashboard.reasonPrefix'
                    .trParams({'reason': proposal.rejectionReason})
                : proposal.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 3.1 — real metrics block. Pulled from /me/expert/dashboard.
// While the call is in flight we render the same row with em-dashes so
// the layout doesn't shift on resolution.
// ─────────────────────────────────────────────────────────────────────────────

class _MetricsBlock extends StatelessWidget {
  final ExpertDashboardController controller;
  const _MetricsBlock({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final dash = controller.dashboard;
      final currency = dash?.currency ?? 'usd';
      final subs = dash?.subscribers;
      final eng = dash?.engagement;

      String money(int cents) => formatCents(cents, currency);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
            child: Text(
              'dashboard.performance'.tr,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'dashboard.metricSubscribers'.tr,
                  value: subs == null ? '—' : '${subs.activeSubscribers}',
                  sub: subs == null
                      ? null
                      : (subs.pendingSubscribers > 0
                          ? 'dashboard.pendingCount'
                              .trParams({'count': '${subs.pendingSubscribers}'})
                          : 'dashboard.activeNow'.tr),
                  icon: Icons.group_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  label: 'dashboard.metricRevenue'.tr,
                  value: subs == null ? '—' : money(subs.lifetimeRevenueCents),
                  sub: subs == null
                      ? null
                      : 'dashboard.lifetimeActive'
                          .trParams({'amount': money(subs.activeRevenueCents)}),
                  icon: Icons.payments_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'dashboard.metricLikes'.tr,
                  value: eng == null ? '—' : '${eng.likes}',
                  sub: eng == null ? null : 'dashboard.acrossYourPosts'.tr,
                  icon: Icons.favorite_outline_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCard(
                  label: 'dashboard.metricComments'.tr,
                  value: eng == null ? '—' : '${eng.comments}',
                  sub: eng == null
                      ? null
                      : 'dashboard.savesShares'.trParams(
                          {'saves': '${eng.saves}', 'shares': '${eng.shares}'}),
                  icon: Icons.chat_bubble_outline_rounded,
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      fontSize: 10,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 3.2 — pricing tile. Shows the expert's current monthly + yearly
// prices and opens the EditPricingSheet on tap.
// ─────────────────────────────────────────────────────────────────────────────

class _PricingTile extends StatelessWidget {
  final ExpertDashboardController controller;
  const _PricingTile({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Obx(() {
      final dash = controller.dashboard;
      final currency = dash?.currency ?? 'usd';
      final monthlyLabel =
          dash == null ? '—' : formatCents(dash.monthlyPriceCents, currency);
      final yearlyLabel =
          dash == null ? '—' : formatCents(dash.yearlyPriceCents, currency);
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: dash == null
              ? null
              : () => EditPricingSheet.show(
                    context,
                    controller: controller,
                    initialMonthlyCents: dash.monthlyPriceCents,
                    initialYearlyCents: dash.yearlyPriceCents,
                  ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.local_offer_outlined,
                      color: cs.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'dashboard.pricingTitle'.tr,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'dashboard.pricingValue'.trParams(
                            {'monthly': monthlyLabel, 'yearly': yearlyLabel}),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                DirectionalIcon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 3.3 — earnings tile. Routes to the full earnings screen.
// ─────────────────────────────────────────────────────────────────────────────

class _EarningsTile extends StatelessWidget {
  final ExpertDashboardController controller;
  const _EarningsTile({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticUtils.lightTap();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EarningsScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.tertiary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.show_chart_rounded,
                  color: cs.tertiary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'dashboard.earningsTitle'.tr,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'dashboard.earningsSubtitle'.tr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              DirectionalIcon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
