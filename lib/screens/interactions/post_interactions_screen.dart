import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/realtime_controller.dart';
import '../../localization/locale_format.dart';
import '../../models/expert_post.dart';
import '../../models/liker.dart';
import '../../models/post_comment.dart';
import '../../services/post_interaction_service.dart';
import '../../services/realtime_service.dart';
import '../../utils/haptic_utils.dart';
import '../social/social_tokens.dart';

/// Sarah's "who interacted with this post?" view.
///
/// Two tabs:
///   * **Likes**    — list of users who liked, newest first. Owner / admin
///                    only (gated server-side too).
///   * **Comments** — same thread the public sees, but with inline
///                    delete on every row (post owner moderates her
///                    thread; admins can moderate anywhere).
///
/// Driven by realtime: `post_liked` / `post_comment_*` events for this
/// post id reload the relevant list automatically while Sarah is on
/// the screen.
class PostInteractionsScreen extends StatefulWidget {
  final ExpertPost post;
  /// Which tab to land on. Defaults to Likes — that's the new info; the
  /// public tap-on-comment-icon already shows comments.
  final int initialTab;

  const PostInteractionsScreen({
    super.key,
    required this.post,
    this.initialTab = 0,
  });

  @override
  State<PostInteractionsScreen> createState() => _PostInteractionsScreenState();
}

class _PostInteractionsScreenState extends State<PostInteractionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  List<Liker>? _likers; // null = loading or error
  List<PostComment>? _comments;
  bool _likesLoading = true;
  bool _commentsLoading = true;
  String? _likesError;
  StreamSubscription<RealtimeEvent>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _tab.addListener(() {
      if (_tab.indexIsChanging) HapticUtils.pick();
    });
    _loadLikes();
    _loadComments();
    _wireRealtime();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadLikes() async {
    setState(() {
      _likesLoading = true;
      _likesError = null;
    });
    final list = await PostInteractionService.listLikers(widget.post.id);
    if (!mounted) return;
    setState(() {
      _likesLoading = false;
      if (list == null) {
        _likesError = 'interactions.likesLoadError'.tr;
      } else {
        _likers = list;
      }
    });
  }

  Future<void> _loadComments() async {
    setState(() => _commentsLoading = true);
    final list = await PostInteractionService.listComments(widget.post.id);
    if (!mounted) return;
    setState(() {
      _commentsLoading = false;
      if (list != null) _comments = list;
    });
  }

  void _wireRealtime() {
    final RealtimeController rt;
    try {
      rt = Get.find<RealtimeController>();
    } catch (_) {
      return;
    }
    _realtimeSub = rt.events.listen((ev) {
      final pid = (ev.data['postId'] as num?)?.toInt();
      if (pid != widget.post.id) return;
      switch (ev.type) {
        case 'post_liked':
        case 'post_unliked':
          _loadLikes();
          break;
        case 'post_comment_created':
        case 'post_comment_deleted':
          _loadComments();
          break;
      }
    });
  }

  Future<void> _deleteComment(PostComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('interactions.deleteCommentTitle'.tr),
        content: Text('interactions.deleteCommentBody'.tr),
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
    final err = await PostInteractionService.deleteComment(
      widget.post.id,
      c.id,
    );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() {
      _comments = (_comments ?? []).where((x) => x.id != c.id).toList();
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
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'interactions.title'.tr,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
                fontSize: 18,
              ),
            ),
            if (widget.post.title != null && widget.post.title!.isNotEmpty)
              Text(
                widget.post.title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: palette.background,
            child: TabBar(
              controller: _tab,
              indicatorColor: SocialTokens.cyan,
              indicatorWeight: 3,
              labelColor: palette.textPrimary,
              unselectedLabelColor: palette.textMuted,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
              ),
              tabs: [
                _tabLabel(
                  icon: Icons.favorite_rounded,
                  label: 'interactions.tabLikes'.tr,
                  count: _likers?.length ?? widget.post.likes,
                ),
                _tabLabel(
                  icon: Icons.chat_bubble_rounded,
                  label: 'interactions.tabComments'.tr,
                  count: _comments?.length ?? widget.post.comments,
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _LikesTab(
            likers: _likers,
            loading: _likesLoading,
            error: _likesError,
            onRetry: _loadLikes,
          ),
          _CommentsTab(
            comments: _comments,
            loading: _commentsLoading,
            onDelete: _deleteComment,
          ),
        ],
      ),
    );
  }

  Widget _tabLabel({
    required IconData icon,
    required String label,
    required int count,
  }) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
            decoration: BoxDecoration(
              color: SocialTokens.cyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: SocialTokens.cyan.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: SocialTokens.cyan,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Likes tab — a list of who liked. Pull to refresh.
// ============================================================================
class _LikesTab extends StatelessWidget {
  final List<Liker>? likers;
  final bool loading;
  final String? error;
  final Future<void> Function() onRetry;

  const _LikesTab({
    required this.likers,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    if (loading && likers == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: SocialTokens.cyan),
        ),
      );
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded,
                  color: palette.textMuted, size: 36),
              const SizedBox(height: 12),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textMuted, fontSize: 13.5),
              ),
              const SizedBox(height: 14),
              FilledButton(onPressed: onRetry, child: Text('common.retry'.tr)),
            ],
          ),
        ),
      );
    }
    final list = likers ?? const <Liker>[];
    if (list.isEmpty) {
      return RefreshIndicator.adaptive(
        color: SocialTokens.cyan,
        onRefresh: onRetry,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 80, 32, 60),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF3B5C).withValues(alpha: 0.12),
                      border: Border.all(
                        color: const Color(0xFFFF3B5C).withValues(alpha: 0.4),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.favorite_outline_rounded,
                      size: 32,
                      color: Color(0xFFFF3B5C),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'interactions.noLikesTitle'.tr,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'interactions.noLikesBody'.tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator.adaptive(
      color: SocialTokens.cyan,
      onRefresh: onRetry,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _LikerTile(liker: list[i]),
      ),
    );
  }
}

class _LikerTile extends StatelessWidget {
  final Liker liker;
  const _LikerTile({required this.liker});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          _Avatar(name: liker.displayName, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        liker.displayName,
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
                    if (liker.isExpert) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: SocialTokens.cyan.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: SocialTokens.cyan.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          'interactions.expertBadge'.tr,
                          style: const TextStyle(
                            color: SocialTokens.cyan,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'interactions.likedAt'
                      .trParams({'time': LocaleFormat.relative(liker.likedAt)}),
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.favorite_rounded,
            size: 16,
            color: Color(0xFFFF3B5C),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Comments tab — full-screen thread with inline delete on every row
// (this screen is owner / admin only, so all comments are deletable).
// ============================================================================
class _CommentsTab extends StatelessWidget {
  final List<PostComment>? comments;
  final bool loading;
  final void Function(PostComment) onDelete;

  const _CommentsTab({
    required this.comments,
    required this.loading,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    if (loading && comments == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: SocialTokens.cyan),
        ),
      );
    }
    final list = comments ?? const <PostComment>[];
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SocialTokens.cyan.withValues(alpha: 0.12),
                  border: Border.all(
                    color: SocialTokens.cyan.withValues(alpha: 0.4),
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: SocialTokens.cyan,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'interactions.noCommentsTitle'.tr,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'interactions.noCommentsBody'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final c = list[i];
        return _CommentRow(comment: c, onDelete: () => onDelete(c));
      },
    );
  }
}

class _CommentRow extends StatelessWidget {
  final PostComment comment;
  final VoidCallback onDelete;
  const _CommentRow({required this.comment, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(name: comment.authorName, size: 36),
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
                        comment.authorName.isEmpty
                            ? 'interactions.memberFallback'.tr
                            : comment.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('·',
                        style: TextStyle(
                            color: palette.textMuted, fontSize: 11)),
                    const SizedBox(width: 6),
                    Text(
                      LocaleFormat.relative(comment.createdAt),
                      style:
                          TextStyle(color: palette.textMuted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.body,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'common.delete'.tr,
            splashRadius: 18,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: palette.textMuted,
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              onDelete();
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Avatar — same cyan-gradient initials disc used elsewhere.
// ============================================================================
class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  const _Avatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            SocialTokens.cyan,
            SocialTokens.cyan.withValues(alpha: 0.55),
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
          fontSize: size * 0.4,
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

