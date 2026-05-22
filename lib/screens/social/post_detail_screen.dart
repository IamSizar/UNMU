import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../models/post_comment.dart';
import '../../services/post_interaction_service.dart';
import '../../widgets/social/shariah_grade_chip.dart';
import '../../widgets/social/source_badge.dart';
import '../../localization/locale_format.dart';
import 'mock_social_data.dart';
import 'social_tokens.dart';

/// =============================================================================
/// Full-screen Post Detail viewer — EDGE-TO-EDGE immersive.
///
/// No traditional AppBar. The hero block extends under the status bar,
/// and floating glass-style overlay buttons (back / share / save) sit on
/// top in the safe area. Bottom inset is reserved for the sticky action +
/// reply bar.
/// =============================================================================
class PostDetailScreen extends StatefulWidget {
  final CommunityPost post;
  final Community community;
  const PostDetailScreen({
    super.key,
    required this.post,
    required this.community,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  bool _liked = false;
  bool _saved = false;
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();

  // Sprint-B step 16 — real comments loaded from
  // GET /api/posts/:id/comments when the post id is a real backend
  // integer. Falls back to the legacy mock comments only when the
  // entry path is still mock-driven (community_detail_screen ids
  // like "p1"/"p2" — those will go away in a later cleanup).
  List<PostComment>? _comments;
  bool _commentsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    final numericId = int.tryParse(widget.post.id);
    if (numericId == null) {
      // Non-numeric post id ⇒ mock-driven entry; the build method
      // renders mock comments inline when _comments stays null.
      if (mounted) {
        setState(() => _commentsLoading = false);
      }
      return;
    }
    final fresh = await PostInteractionService.listComments(numericId);
    if (!mounted) return;
    setState(() {
      _comments = fresh ?? const [];
      _commentsLoading = false;
    });
  }

  @override
  void dispose() {
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Color get _stanceColor {
    switch (widget.post.stance.toUpperCase()) {
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
    final post = widget.post;
    final community = widget.community;
    final accent = SocialTokens.regionColor(community.regionCode);
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: palette.background,
      // Body extends behind status bar — no AppBar at all.
      body: Stack(
        children: [
          // ── Edge-to-edge scrolling content ──
          ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              // Hero block — bleeds under the status bar
              _Hero(
                palette: palette,
                community: community,
                accent: accent,
                topInset: topInset,
                authorName: post.author,
                timeAgo: post.timeAgo,
              ),
              // Source-attribution badge — tells the viewer this
              // post came from a community (vs. an expert profile).
              // Tappable: pushes the community detail screen.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SourceBadge.large(
                    targetType: 'community',
                    communityId: community.id,
                    communityName: community.name,
                    communityRegionCode: community.regionCode,
                  ),
                ),
              ),
              // Body
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Text(
                  post.title,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                    letterSpacing: -0.6,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Step 27 — hide the stance pill on discussion-style
              // posts with no ticker (Sprint-C step 9 made ticker
              // optional). Default "HOLD" on a non-ticker post was
              // misleading.
              if (post.ticker.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _StancePill(
                    ticker: post.ticker,
                    stance: post.stance,
                    color: _stanceColor,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  post.body,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 16,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _StatsRow(
                  palette: palette,
                  upvotes: post.upvotes + (_liked ? 1 : 0),
                  comments: post.comments,
                ),
              ),
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'post.topDiscussion'.tr,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Sprint-B step 16 — real comments from the backend
              // when the post id is numeric; mock fallback only for
              // legacy mock-driven entry points (community_detail).
              if (_commentsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_comments != null)
                ..._comments!.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                          child: Text(
                            'post.beFirstToComment'.tr,
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ]
                    : _comments!.map(
                        (c) => Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                          child: _CommentTile(
                            palette: palette,
                            author: c.authorName.isEmpty
                                ? 'post.someone'.tr
                                : c.authorName,
                            timeAgo: _relTime(c.createdAt),
                            body: c.body,
                            likes: 0,
                          ),
                        ),
                      )
              else
                ..._mockComments().map(
                  (m) => Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: _CommentTile(
                      palette: palette,
                      author: m['author'] as String,
                      timeAgo: m['timeAgo'] as String,
                      body: m['body'] as String,
                      likes: m['likes'] as int,
                    ),
                  ),
                ),
              // Spacer so the bottom action bar doesn't cover content.
              const SizedBox(height: 96),
            ],
          ),
          // ── Floating top overlay (back + share + save) ──
          Positioned(
            top: topInset + 8,
            left: 12,
            right: 12,
            child: Row(
              children: [
                _GlassIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                _GlassIconButton(
                  icon: Icons.share_rounded,
                  onTap: () {},
                ),
                const SizedBox(width: 8),
                _GlassIconButton(
                  icon: _saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  iconColor: _saved ? SocialTokens.gold : Colors.white,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _saved = !_saved);
                  },
                ),
              ],
            ),
          ),
          // ── Sticky bottom bar ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBar(
              palette: palette,
              liked: _liked,
              onLike: () {
                HapticFeedback.selectionClick();
                setState(() => _liked = !_liked);
              },
              reply: _reply,
              replyFocus: _replyFocus,
            ),
          ),
        ],
      ),
    );
  }

  static String _relTime(DateTime t) => LocaleFormat.relative(t);

  List<Map<String, Object>> _mockComments() {
    return [
      {
        'author': 'Khaled',
        'timeAgo': '8m',
        'body':
            "Solid analysis — I'm holding too. The dividend coverage is the part most analysts miss.",
        'likes': 24,
      },
      {
        'author': 'Mariam',
        'timeAgo': '21m',
        'body':
            'Capex is what worries me. If oil prices dip a bit, the payout ratio gets uncomfortable.',
        'likes': 12,
      },
      {
        'author': 'Bilal',
        'timeAgo': '1h',
        'body':
            'Adding to the position. Risk-reward looks asymmetric to the upside on a 12-month view.',
        'likes': 7,
      },
    ];
  }
}

// ============================================================================
// Hero block — bleeds under the status bar
// ============================================================================
class _Hero extends StatelessWidget {
  final SocialPalette palette;
  final Community community;
  final Color accent;
  final double topInset;
  final String authorName;
  final String timeAgo;

  const _Hero({
    required this.palette,
    required this.community,
    required this.accent,
    required this.topInset,
    required this.authorName,
    required this.timeAgo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // Stretches under the system status bar.
      padding: EdgeInsets.fromLTRB(20, topInset + 64, 20, 18),
      decoration: BoxDecoration(
        gradient: palette.heroGradient(),
        boxShadow: palette.cardShadow(accent: accent),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [accent, accent.withValues(alpha: 0.55)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Text(
              community.regionCode,
              style: const TextStyle(
                color: Color(0xFF0A1628),
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  community.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: SocialTokens.cyan.withValues(alpha: 0.22),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        size: 11,
                        color: SocialTokens.cyan,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      ' · $timeAgo',
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent, width: 1.3),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'post.joined'.tr,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Glass overlay icon button (used for back / share / save floating overlay)
// ============================================================================
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
      ),
    );
  }
}

// ============================================================================
// Stance pill
// ============================================================================
class _StancePill extends StatelessWidget {
  final String ticker;
  final String stance;
  final Color color;
  const _StancePill({
    required this.ticker,
    required this.stance,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
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
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            '${stance.toUpperCase()}  \$$ticker',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 8),
          const ShariahGradeChip(grade: 'A', size: 16),
        ],
      ),
    );
  }
}

// ============================================================================
// Stats row (Upvotes / Replies / Views)
// ============================================================================
class _StatsRow extends StatelessWidget {
  final SocialPalette palette;
  final int upvotes;
  final int comments;
  const _StatsRow({
    required this.palette,
    required this.upvotes,
    required this.comments,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.subtleDivider),
      ),
      child: Row(
        children: [
          Expanded(
            child: _stat(
              palette,
              icon: Icons.arrow_upward_rounded,
              accent: SocialTokens.up,
              value: '$upvotes',
              label: 'post.upvotes'.tr,
            ),
          ),
          Container(width: 1, height: 30, color: palette.subtleDivider),
          Expanded(
            child: _stat(
              palette,
              icon: Icons.mode_comment_outlined,
              accent: SocialTokens.cyan,
              value: '$comments',
              label: 'post.replies'.tr,
            ),
          ),
          Container(width: 1, height: 30, color: palette.subtleDivider),
          Expanded(
            child: _stat(
              palette,
              icon: Icons.visibility_outlined,
              accent: SocialTokens.gold,
              value: '${(upvotes * 8.7).round()}',
              label: 'post.views'.tr,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(
    SocialPalette palette, {
    required IconData icon,
    required Color accent,
    required String value,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: accent),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: -0.3,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Sticky bottom action + reply bar
// ============================================================================
class _BottomBar extends StatelessWidget {
  final SocialPalette palette;
  final bool liked;
  final VoidCallback onLike;
  final TextEditingController reply;
  final FocusNode replyFocus;

  const _BottomBar({
    required this.palette,
    required this.liked,
    required this.onLike,
    required this.reply,
    required this.replyFocus,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.subtleDivider)),
        ),
        child: Row(
          children: [
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onLike,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: liked ? SocialTokens.down : palette.textSecondary,
                    size: 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: palette.border),
                ),
                child: TextField(
                  controller: reply,
                  focusNode: replyFocus,
                  textInputAction: TextInputAction.send,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'post.addReplyHint'.tr,
                    hintStyle: TextStyle(color: palette.textMuted),
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: SocialTokens.cyan,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () {
                  if (reply.text.trim().isEmpty) return;
                  HapticFeedback.lightImpact();
                  reply.clear();
                },
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    color: Color(0xFF0A1628),
                    size: 18,
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
// Comment tile
// ============================================================================
class _CommentTile extends StatelessWidget {
  final SocialPalette palette;
  final String author;
  final String timeAgo;
  final String body;
  final int likes;

  const _CommentTile({
    required this.palette,
    required this.author,
    required this.timeAgo,
    required this.body,
    required this.likes,
  });

  @override
  Widget build(BuildContext context) {
    final hue = author.codeUnits.fold<int>(0, (a, b) => a + b);
    final c = HSLColor.fromAHSL(1, ((hue * 47) % 360).toDouble(), 0.55, 0.62)
        .toColor();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.subtleDivider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [c, c.withValues(alpha: 0.55)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Text(
              author.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF0A1628),
                fontWeight: FontWeight.w900,
                fontSize: 13,
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
                    Text(
                      author,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· $timeAgo',
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.favorite_border_rounded,
                      size: 13,
                      color: palette.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$likes',
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'post.reply'.tr,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
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
}
