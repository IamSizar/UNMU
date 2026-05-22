import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../localization/locale_format.dart';
import '../../models/expert_post.dart';
import '../../services/events_service.dart';
import '../../services/expert_post_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/social/like_button.dart';
import '../../widgets/social/comment_button.dart';
import '../../widgets/social/markdown_body.dart';
import '../../widgets/social/post_history_sheet.dart';
import '../../widgets/social/source_badge.dart';
import '../../widgets/social/save_button.dart';
import '../reels/reel_player_screen.dart';
import '../social/expert_profile_screen.dart';
import '../social/social_tokens.dart';

/// Single-post viewer reached via deep-link route resolution.
///
/// Two construction paths:
///   * [PostViewerScreen.forPost]      — caller already has the post
///                                        (e.g. tapped a feed row).
///   * [PostViewerScreen.forId]        — caller only has an id, e.g. the
///                                        DeepLinkService just received
///                                        `unmu.app/p/123`. The screen
///                                        fetches the post itself, with
///                                        a loading + not-found state.
///
/// Locked-teaser handling: if the post comes back with `isLocked: true`
/// (subscriber-only viewed by a non-subscriber), the body and media are
/// blanked out by the backend; this screen renders a "Subscribe to see
/// the rest" card and a tappable author header that jumps to the expert
/// profile.
class PostViewerScreen extends StatefulWidget {
  /// Either a pre-fetched post OR a bare id — exactly one is used.
  final ExpertPost? initialPost;
  final int? postId;

  const PostViewerScreen.forPost(ExpertPost post, {super.key})
      : initialPost = post,
        postId = null;

  const PostViewerScreen.forId(int id, {super.key})
      : initialPost = null,
        postId = id;

  @override
  State<PostViewerScreen> createState() => _PostViewerScreenState();
}

class _PostViewerScreenState extends State<PostViewerScreen> {
  static const _accent = SocialTokens.cyan;

  ExpertPost? _post;
  bool _loading = false;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPost != null) {
      _post = widget.initialPost;
    } else {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _notFound = false;
    });
    final p = await ExpertPostService.getById(widget.postId!);
    if (!mounted) return;
    setState(() {
      _post = p;
      _loading = false;
      _notFound = p == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        foregroundColor: palette.textPrimary,
        title: Text(
          'postViewer.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _buildBody(palette),
    );
  }

  Widget _buildBody(SocialPalette palette) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_notFound || _post == null) {
      return _NotFoundState(onRetry: widget.postId == null ? null : _fetch);
    }
    return _PostContent(post: _post!, palette: palette);
  }
}

// ─────────────────────────────────────────────────────────────────────
// Body — author header → cover/media → title/body → action bar
// ─────────────────────────────────────────────────────────────────────

class _PostContent extends StatelessWidget {
  final ExpertPost post;
  final SocialPalette palette;
  static const _accent = SocialTokens.cyan;

  const _PostContent({required this.post, required this.palette});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _header(context),
        // Source badge — tells the viewer if this came from a
        // community or an expert's personal profile. Auto-hides
        // when neither metadata pair is populated (older mock paths).
        if (post.isFromCommunity || post.isFromExpertProfile) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: SourceBadge.large(
              targetType:
                  post.isFromCommunity ? 'community' : 'expert',
              communityId: post.communityId,
              communityName: post.communityName,
              communityRegionCode: post.communityRegionCode,
              expertId: post.expertId,
              expertName: post.expertName.isEmpty
                  ? post.authorName
                  : post.expertName,
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (post.coverUrl != null && post.coverUrl!.isNotEmpty)
          _cover(context),
        if (post.title != null && post.title!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            post.title!.trim(),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
        ],
        if (post.isLocked)
          _LockedCard(post: post, palette: palette)
        else if (post.body.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          // Step-20 (mig 0020, item 4.17) — render the body as
          // restricted markdown. Falls back to plain text inside
          // the renderer when no markdown syntax is present.
          PostMarkdownBody(post.body.trim()),
        ],
        // Step-20 (mig 0020, item 4.18) — inline image gallery.
        // Sits below the body so the post reads naturally text → images.
        if (!post.isLocked && post.attachments.isNotEmpty) ...[
          const SizedBox(height: 14),
          _InlineAttachmentsGallery(attachments: post.attachments),
        ],
        // Step-20 (mig 0020, item 4.16) — "Edited Xm ago" pill that
        // opens the post-history sheet on tap. Owner + admin only on
        // the server side; everyone else gets a 403 inside the sheet.
        if (post.wasEdited) ...[
          const SizedBox(height: 10),
          _EditedPill(
            updatedAt: post.updatedAt!,
            postId: post.id,
          ),
        ],
        if (post.tickers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: post.tickers
                .map(
                  (t) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _accent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '\$$t',
                      style: const TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 24),
        _actionBar(context),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final initials = post.authorName.trim().isEmpty
        ? '?'
        : post.authorName.trim()[0].toUpperCase();
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () =>
          ExpertProfileScreen.openForExpertId(context, post.expertId),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _accent.withValues(alpha: 0.18),
              child: Text(
                initials,
                style: const TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.authorName,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _relativeTime(post.createdAt),
                    style: TextStyle(
                      color: palette.textPrimary.withValues(alpha: 0.6),
                      fontSize: 12,
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

  Widget _cover(BuildContext context) {
    final url = post.coverUrl!;
    final isPlayable = (post.postType == PostType.reel ||
            post.postType == PostType.video) &&
        post.mediaUrl != null &&
        post.mediaUrl!.isNotEmpty;
    return GestureDetector(
      onTap: !isPlayable
          ? null
          : () => Get.to(
                () => ReelPlayerScreen(
                  mediaUrl: post.mediaUrl!,
                  coverUrl: post.coverUrl,
                  title: post.title,
                  authorName: post.authorName,
                  // Reels are short-loop format; long-form videos should
                  // play once and stop so a 30-minute clip doesn't loop
                  // forever in the user's face.
                  loop: post.postType == PostType.reel,
                ),
              ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: post.postType == PostType.reel ? 9 / 16 : 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: palette.surfaceElevated,
                  child: Icon(
                    Icons.image_outlined,
                    color: palette.textPrimary.withValues(alpha: 0.4),
                  ),
                ),
              ),
              if (isPlayable)
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBar(BuildContext context) {
    return Row(
      children: [
        LikeButton(
          post: post,
          accent: _accent,
          mutedColor: palette.textPrimary,
          iconSize: 26,
        ),
        const SizedBox(width: 10),
        CommentButton(
          post: post,
          accent: _accent,
          mutedColor: palette.textPrimary,
          iconSize: 24,
        ),
        const SizedBox(width: 10),
        Builder(
          builder: (btnContext) => InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _share(btnContext),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.ios_share_rounded,
                size: 24,
                color: palette.textPrimary,
              ),
            ),
          ),
        ),
        const Spacer(),
        SaveButton(
          post: post,
          accent: _accent,
          mutedColor: palette.textPrimary,
        ),
      ],
    );
  }

  Future<void> _share(BuildContext btnContext) async {
    HapticUtils.tap();
    final title = (post.title ?? '').trim();
    final author = post.authorName.trim().isEmpty
        ? 'feedTab.shareExpertFallback'.tr
        : post.authorName.trim();
    final body = title.isEmpty
        ? 'feedTab.shareBodyNoTitle'.trParams({'author': author})
        : 'feedTab.shareBodyWithTitle'
            .trParams({'title': title, 'author': author});
    final url = 'https://unmu.app/p/${post.id}';
    final box = btnContext.findRenderObject() as RenderBox?;
    unawaited(EventsService.logShare(post.id));
    await Share.share(
      '$body\n\n$url',
      subject: title.isEmpty ? 'feedTab.shareSubjectFallback'.tr : title,
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  static String _relativeTime(DateTime t) => LocaleFormat.relative(t);
}

// ─────────────────────────────────────────────────────────────────────
// Locked teaser — subscriber-only post viewed by a non-subscriber.
// ─────────────────────────────────────────────────────────────────────

class _LockedCard extends StatelessWidget {
  final ExpertPost post;
  final SocialPalette palette;
  static const _accent = SocialTokens.cyan;

  const _LockedCard({required this.post, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, color: _accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'postViewer.lockedTitle'.tr,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'postViewer.lockedBody'.trParams({'author': post.authorName}),
            style: TextStyle(
              color: palette.textPrimary.withValues(alpha: 0.85),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _accent),
              onPressed: () => ExpertProfileScreen.openForExpertId(
                context,
                post.expertId,
              ),
              child: Text(
                'postViewer.viewProfile'.tr,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// 404 / network-error empty state.
// ─────────────────────────────────────────────────────────────────────

class _NotFoundState extends StatelessWidget {
  final Future<void> Function()? onRetry;
  const _NotFoundState({this.onRetry});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.link_off_rounded,
              size: 56,
              color: palette.textPrimary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              'postViewer.notFoundTitle'.tr,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'postViewer.notFoundBody'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary.withValues(alpha: 0.65),
                fontSize: 13,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: onRetry,
                child: Text('postViewer.tryAgain'.tr),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Step-20 (mig 0020, item 4.18) — horizontal-scroll gallery for inline
// image attachments. Tap to open a full-screen viewer with pinch zoom.
class _InlineAttachmentsGallery extends StatelessWidget {
  final List<PostAttachment> attachments;
  const _InlineAttachmentsGallery({required this.attachments});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final a = attachments[i];
          return GestureDetector(
            onTap: () {
              HapticUtils.tap();
              showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  insetPadding: const EdgeInsets.all(12),
                  backgroundColor: Colors.black,
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: Image.network(a.url, fit: BoxFit.contain),
                  ),
                ),
              );
            },
            child: Container(
              width: 200,
              decoration: BoxDecoration(
                color: palette.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.border),
                image: DecorationImage(
                  image: NetworkImage(a.url),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Step-20 (mig 0020, item 4.16) — small pill rendered below the body
// when the post has been edited. Tap → open post-history sheet.
class _EditedPill extends StatelessWidget {
  final DateTime updatedAt;
  final int postId;
  const _EditedPill({required this.updatedAt, required this.postId});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final delta = DateTime.now().difference(updatedAt);
    String label;
    if (delta.inMinutes < 60) {
      label = 'postViewer.editedMinuteAgo'
          .trParams({'count': '${delta.inMinutes}'});
    } else if (delta.inHours < 24) {
      label =
          'postViewer.editedHourAgo'.trParams({'count': '${delta.inHours}'});
    } else {
      label = 'postViewer.editedDayAgo'.trParams({'count': '${delta.inDays}'});
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () {
          HapticUtils.tap();
          PostHistorySheet.show(context, postId: postId);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: palette.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded,
                  size: 13, color: palette.textMuted),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

