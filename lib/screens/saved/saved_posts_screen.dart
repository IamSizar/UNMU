import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/saved_controller.dart';
import '../../models/expert_post.dart';
import '../../utils/responsive.dart';
import '../../widgets/common/app_network_image.dart';
import '../../widgets/social/comment_button.dart';
import '../../widgets/social/like_button.dart';
import '../../widgets/social/save_button.dart';
import '../reels/reel_player_screen.dart';
import '../social/expert_profile_screen.dart';
import '../social/social_tokens.dart';

/// "Saved" screen — every post the user has bookmarked, newest first.
///
/// Reads everything from [SavedController] (registered permanent in
/// main.dart). Saving / unsaving anywhere in the app reflects here live.
class SavedPostsScreen extends StatelessWidget {
  const SavedPostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final ctrl = Get.find<SavedController>();

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'saved.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'common.refresh'.tr,
            icon: Icon(Icons.refresh_rounded, color: palette.textPrimary),
            onPressed: () {
              HapticFeedback.lightImpact();
              ctrl.reload();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Obx(() {
          final posts = ctrl.posts;
          final loading = ctrl.loading;
          final fetched = ctrl.fetchedOk;

          if (loading && posts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: SocialTokens.cyan),
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
                  _EmptyState(palette: palette, fetched: fetched),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: SocialTokens.cyan,
            onRefresh: ctrl.reload,
            child: responsiveCardList(
              context: context,
              // iPad: 2 columns of saved cards (capped at 2 even on large —
              // post cards carry media and read better wider). Phone: single
              // column, identical to the previous ListView.separated.
              tablet: 2,
              large: 2,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              itemCount: posts.length,
              itemBuilder: (_, i) =>
                  _SavedPostCard(post: posts[i], palette: palette),
            ),
          );
        }),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final SocialPalette palette;
  final bool fetched;
  const _EmptyState({required this.palette, required this.fetched});

  @override
  Widget build(BuildContext context) {
    final title =
        fetched ? 'saved.emptyTitle'.tr : 'saved.errorTitle'.tr;
    final subtitle =
        fetched ? 'saved.emptySubtitle'.tr : 'saved.errorSubtitle'.tr;
    final icon =
        fetched ? Icons.bookmark_outline_rounded : Icons.cloud_off_rounded;
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

class _SavedPostCard extends StatelessWidget {
  final ExpertPost post;
  final SocialPalette palette;
  const _SavedPostCard({required this.post, required this.palette});

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
                    const SizedBox(height: 12),
                    Container(height: 1, color: palette.subtleDivider),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        LikeButton(
                            post: post,
                            accent: _accent,
                            mutedColor: palette.textMuted),
                        const SizedBox(width: 12),
                        CommentButton(
                            post: post,
                            accent: _accent,
                            mutedColor: palette.textMuted),
                        const Spacer(),
                        SaveButton(
                            post: post,
                            accent: _accent,
                            mutedColor: palette.textMuted),
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

  Widget _attribution(BuildContext context) {
    void openProfile() =>
        ExpertProfileScreen.openForExpertId(context, post.expertId);
    return Row(
      children: [
        GestureDetector(
          onTap: openProfile,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                colors: [_accent, _accent.withValues(alpha: 0.55)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
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
                      ? 'saved.expertFallback'.tr
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
                Text(
                  _typeLabel(post.postType),
                  style: TextStyle(color: palette.textMuted, fontSize: 10.5),
                ),
              ],
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
              AppNetworkImage(
                cover,
                fit: BoxFit.cover,
                placeholderColor: palette.surfaceElevated,
                errorWidget: Container(color: palette.surfaceElevated),
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
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 28),
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
        return 'saved.typeArticle'.tr;
      case PostType.video:
        return 'saved.typeVideo'.tr;
      case PostType.reel:
        return 'saved.typeReel'.tr;
    }
  }
}
