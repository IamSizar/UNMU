import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/realtime_controller.dart';
import '../../localization/locale_format.dart';
import '../../models/post_comment.dart';
import '../../services/post_interaction_service.dart';
import '../../services/realtime_service.dart';
import '../../screens/social/social_tokens.dart';
import '../../utils/haptic_utils.dart';
import '../dismiss_keyboard_on_tap.dart';
import 'report_sheet.dart';

/// Modal bottom sheet — comments thread for a single post.
///
/// Visual upgrades over the v1 sheet:
///   * Frosted-blur header with a wider drag handle.
///   * Larger cyan-gradient avatars matching the rest of the app.
///   * Threaded conversation rhythm — name + time inline above the body,
///     body in a subtly tinted bubble.
///   * Compose row anchored at the bottom with the user's own avatar on
///     the left and a paper-airplane send button that animates in only
///     when there's text.
///   * Cleaner empty state with an illustrated icon.
///
/// Use [show] to open it from anywhere — slides up to ~85% of screen,
/// keyboard-aware, dismisses on tap-outside.
class CommentsSheet extends StatefulWidget {
  final int postId;
  final String? postOwnerExpertId;
  final Color accent;

  const CommentsSheet({
    super.key,
    required this.postId,
    required this.accent,
    this.postOwnerExpertId,
  });

  /// Convenience — opens the sheet using the standard transition.
  static Future<void> show(
    BuildContext context, {
    required int postId,
    String? postOwnerExpertId,
    Color accent = SocialTokens.cyan,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      useSafeArea: true,
      builder: (_) => CommentsSheet(
        postId: postId,
        postOwnerExpertId: postOwnerExpertId,
        accent: accent,
      ),
    );
  }

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  List<PostComment> _comments = [];
  bool _loading = true;
  bool _sending = false;
  String? _loadError;
  StreamSubscription<RealtimeEvent>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _composer.addListener(() {
      // Repaint the send button when text presence flips.
      if (mounted) setState(() {});
    });
    // Repaint the input chrome (border glow + soft shadow) whenever
    // focus enters / leaves so the focused state animates in cleanly.
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
    _wireRealtime();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _composer.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await PostInteractionService.listComments(widget.postId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (list == null) {
        _loadError = 'comments.loadError'.tr;
      } else {
        _comments = list;
        _loadError = null;
      }
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
      if (ev.type != 'post_comment_created' &&
          ev.type != 'post_comment_deleted') {
        return;
      }
      final pid = (ev.data['postId'] as num?)?.toInt();
      if (pid != widget.postId) return;
      _load();
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    HapticUtils.tap();
    setState(() => _sending = true);
    final result = await PostInteractionService.addComment(widget.postId, text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error!)),
        );
        return;
      }
      if (result.comment != null) {
        _comments = [..._comments, result.comment!];
        _composer.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent + 80,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  /// Open the abuse-report sheet for a comment authored by someone
  /// else. Self-reports are blocked at the caller (we don't show the
  /// chip for your own comments).
  Future<void> _report(PostComment c) async {
    HapticUtils.lightTap();
    final ok = await ReportSheet.show(
      context,
      targetType: 'comment',
      targetId: c.id.toString(),
      targetLabel: 'comments.thisComment'.tr,
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('comments.reportThanks'.tr)),
      );
    }
  }

  Future<void> _edit(PostComment c) async {
    final controller = TextEditingController(text: c.body);
    final newBody = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('comments.editTitle'.tr),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          maxLength: 2000,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'comments.editHint'.tr,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text('common.save'.tr),
          ),
        ],
      ),
    );
    if (newBody == null || newBody.isEmpty || newBody == c.body) return;
    final result =
        await PostInteractionService.editComment(widget.postId, c.id, newBody);
    if (!mounted) return;
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error!)),
      );
      return;
    }
    final updated = result.comment;
    if (updated == null) return;
    setState(() {
      _comments = _comments
          .map((x) => x.id == updated.id ? updated : x)
          .toList();
    });
  }

  Future<void> _delete(PostComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('comments.deleteTitle'.tr),
        content: Text('comments.deleteBody'.tr),
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
    final err = await PostInteractionService.deleteComment(widget.postId, c.id);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() {
      _comments = _comments.where((x) => x.id != c.id).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final auth = Get.find<AuthController>();
    final myId = auth.user?.id ?? 0;
    final amOwner = widget.postOwnerExpertId != null &&
        auth.user?.expertId == widget.postOwnerExpertId;
    final amAdmin = (auth.user?.role ?? '').toString().toUpperCase() == 'ADMIN';

    final viewInsets = MediaQuery.of(context).viewInsets;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return DismissKeyboardOnTap(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: palette.background.withValues(alpha: 0.92),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                      width: 0.6,
                    ),
                  ),
                ),
                padding: EdgeInsets.only(bottom: viewInsets.bottom),
                child: Column(
                  children: [
                    _buildHeader(palette),
                    Expanded(
                      child: _buildBody(
                        palette,
                        scrollCtrl,
                        myId,
                        amOwner,
                        amAdmin,
                      ),
                    ),
                    _buildComposer(palette, auth),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Header — slim drag handle, title + soft count chip, subtitle, and a
  /// chip-style close affordance. Two-line layout reads more like a
  /// dedicated screen than a "modal with a label".
  Widget _buildHeader(SocialPalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Slimmer drag handle — 36×3.5 reads cleaner than 44×4 and
          // matches modern iOS sheet conventions.
          Center(
            child: Container(
              width: 36,
              height: 3.5,
              decoration: BoxDecoration(
                color: palette.textMuted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          'comments.title'.tr,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 19,
                            letterSpacing: -0.4,
                          ),
                        ),
                        if (!_loading && _comments.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          // Soft no-border chip — heavy outline read as
                          // "alert" before; this reads as a secondary
                          // metadata pill.
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: widget.accent.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${_comments.length}',
                              style: TextStyle(
                                color: widget.accent,
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (!_loading)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _comments.isEmpty
                              ? 'comments.startConversation'.tr
                              : _comments.length == 1
                                  ? 'comments.onePersonJoined'.tr
                                  : 'comments.peopleJoined'.trParams(
                                      {'count': '${_comments.length}'},
                                    ),
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Chip-style close — a circle on a soft tint reads as
              // "tappable" without screaming for attention the way a
              // raw IconButton does.
              Material(
                color: palette.surface.withValues(alpha: 0.6),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.close_rounded,
                      color: palette.textPrimary,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    SocialPalette palette,
    ScrollController outerScroll,
    int myId,
    bool amOwner,
    bool amAdmin,
  ) {
    if (_loading) {
      // Skeleton placeholders feel more "modern app" than a generic
      // spinner — gives the sheet visible structure during the fetch.
      return _SkeletonList(palette: palette);
    }
    if (_loadError != null) {
      return _ErrorState(message: _loadError!, palette: palette);
    }
    if (_comments.isEmpty) {
      return _EmptyState(palette: palette, accent: widget.accent);
    }
    return ListView.separated(
      controller: outerScroll,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      itemCount: _comments.length,
      // Slightly larger gap between bubbles — 12px reads as breathing
      // room without losing the "conversation feel".
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final c = _comments[i];
        // Author can edit + delete; owner/admin can only delete
        // (editing someone else's words is a moderation footgun).
        // Anyone signed in who is NOT the author can report.
        final isAuthor = c.authorId == myId;
        final canDelete = isAuthor || amOwner || amAdmin;
        final canReport = myId != 0 && !isAuthor;
        return _CommentTile(
          // Keying by id lets AnimatedSwitcher (or future reorder) work
          // properly when realtime inserts arrive.
          key: ValueKey('comment-${c.id}'),
          comment: c,
          accent: widget.accent,
          canEdit: isAuthor,
          canDelete: canDelete,
          canReport: canReport,
          onEdit: () => _edit(c),
          onDelete: () => _delete(c),
          onReport: () => _report(c),
        );
      },
    );
  }

  /// Compose row — user avatar + rounded text input + send button.
  /// Glass-style elevated bottom strip with a hairline divider so it
  /// reads as a separate surface from the thread above.
  Widget _buildComposer(SocialPalette palette, AuthController auth) {
    final hasText = _composer.text.trim().isNotEmpty;
    final myName = auth.user?.name ?? auth.user?.email ?? '?';
    final isFocused = _focus.hasFocus;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.92),
        // Single hairline divider, no heavy border — keeps the glass
        // backdrop feel instead of looking like two stacked cards.
        border: Border(
          top: BorderSide(
            color: palette.border.withValues(alpha: 0.6),
            width: 0.6,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Avatar(name: myName, size: 34, accent: widget.accent),
          const SizedBox(width: 10),
          Expanded(
            // AnimatedContainer drives a soft glow when the field is
            // focused — feels more responsive than a hard border swap.
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: palette.surfaceElevated,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isFocused
                      ? widget.accent.withValues(alpha: 0.55)
                      : palette.border.withValues(alpha: 0.7),
                  width: isFocused ? 1.4 : 0.7,
                ),
                boxShadow: isFocused
                    ? [
                        BoxShadow(
                          color: widget.accent.withValues(alpha: 0.18),
                          blurRadius: 10,
                          spreadRadius: -2,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: TextField(
                controller: _composer,
                focusNode: _focus,
                minLines: 1,
                maxLines: 5,
                maxLength: 2000,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 14,
                  height: 1.35,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'comments.addCommentHint'.tr,
                  hintStyle: TextStyle(
                    color: palette.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  counterText: '',
                  // No filled / border — the AnimatedContainer above
                  // owns the visual chrome so we get smooth transitions.
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Send button only renders (with a slide-in) when there's text.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: hasText || _sending
                ? Material(
                    key: const ValueKey('send'),
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _sending ? null : _send,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              widget.accent,
                              widget.accent.withValues(alpha: 0.7),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: widget.accent.withValues(alpha: 0.45),
                              blurRadius: 12,
                              spreadRadius: -2,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: _sending
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF0A1628),
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                size: 18,
                                color: Color(0xFF0A1628),
                              ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('empty')),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// _CommentTile — single row in the thread. Stateful so we can drive a
// short fade-up entrance on first paint (incoming-realtime comments
// land softly instead of popping in) and toggle the inline delete chip
// on long-press.
// ============================================================================
class _CommentTile extends StatefulWidget {
  final PostComment comment;
  final Color accent;
  final bool canEdit;
  final bool canDelete;
  final bool canReport;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  const _CommentTile({
    super.key,
    required this.comment,
    required this.accent,
    required this.canEdit,
    required this.canDelete,
    required this.canReport,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
  });

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile>
    with SingleTickerProviderStateMixin {
  // Entrance animation — drives both opacity (0→1) and a tiny
  // translate-up so a freshly-arrived comment feels alive without a
  // jarring slide-in from far away.
  late final AnimationController _entry;

  // While true, the inline action chips (Edit / Delete) are visible.
  // Toggled on long-press so casual taps don't reveal destructive UI.
  bool _showActions = false;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final c = widget.comment;
    return AnimatedBuilder(
      animation: _entry,
      builder: (_, child) {
        final t = Curves.easeOut.transform(_entry.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 6),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        // Long-press to reveal actions keeps casual scrolling clean.
        // Tap-to-hide so the user can dismiss without action.
        behavior: HitTestBehavior.opaque,
        onLongPress: (widget.canDelete || widget.canEdit || widget.canReport)
            ? () => setState(() => _showActions = true)
            : null,
        onTap: _showActions ? () => setState(() => _showActions = false) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(name: c.authorName, size: 36, accent: widget.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Body — soft single-radius bubble. The old
                  // asymmetric corner ("speech tail" on the top-left)
                  // read as dated messenger UI; uniform rounded reads
                  // cleaner and matches modern social apps.
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 9, 14, 11),
                    decoration: BoxDecoration(
                      color: palette.surface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: palette.border.withValues(alpha: 0.6),
                        width: 0.7,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                c.authorName.isEmpty
                                    ? 'comments.member'.tr
                                    : c.authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _relativeTime(c.createdAt),
                              style: TextStyle(
                                color: palette.textMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (c.wasEdited) ...[
                              const SizedBox(width: 4),
                              Text(
                                '· ${'comments.edited'.tr}',
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 10.5,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.body,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 13.5,
                            height: 1.42,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Inline action chips (Edit + Delete) — reveal on
                  // long-press, dismissable by tapping the bubble.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    child: !_showActions
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsetsDirectional.only(top: 6, start: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.canEdit)
                                  _ActionChip(
                                    label: 'comments.actionEdit'.tr,
                                    icon: Icons.edit_outlined,
                                    color: widget.accent,
                                    onTap: widget.onEdit,
                                  ),
                                if (widget.canEdit && widget.canDelete)
                                  const SizedBox(width: 6),
                                if (widget.canDelete)
                                  _ActionChip(
                                    label: 'comments.actionDelete'.tr,
                                    icon: Icons.delete_outline_rounded,
                                    color: const Color(0xFFFF6B7A),
                                    onTap: widget.onDelete,
                                  ),
                                if (widget.canReport &&
                                    (widget.canEdit || widget.canDelete))
                                  const SizedBox(width: 6),
                                if (widget.canReport)
                                  _ActionChip(
                                    label: 'comments.actionReport'.tr,
                                    icon: Icons.flag_outlined,
                                    color: const Color(0xFFE65A6E),
                                    onTap: widget.onReport,
                                  ),
                              ],
                            ),
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

  String _relativeTime(DateTime t) => LocaleFormat.relative(t);
}

// ============================================================================
// Avatar — cyan-gradient initials disc shared by both the comment tiles
// and the composer's "your avatar" slot.
// ============================================================================
class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  final Color accent;
  const _Avatar({required this.name, required this.size, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
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
        _initials(name),
        style: TextStyle(
          color: const Color(0xFF0A1628),
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
// Empty state — shown when there are zero comments. Inviting, not bare.
// ============================================================================
class _EmptyState extends StatelessWidget {
  final SocialPalette palette;
  final Color accent;
  const _EmptyState({required this.palette, required this.accent});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 60),
          child: Column(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.12),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 32,
                  color: accent,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'comments.beFirstTitle'.tr,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'comments.beFirstBody'.tr,
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
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final SocialPalette palette;
  const _ErrorState({required this.message, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: palette.textMuted, size: 36),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// _SkeletonList — placeholder shown while comments are loading. Three
// shimmer rows that visually mirror the real tile layout (avatar disc +
// stacked text lines) so the sheet doesn't snap from "spinner" to
// "rendered list" — feels much more "modern app loading" than a generic
// CircularProgressIndicator.
// ============================================================================
class _SkeletonList extends StatefulWidget {
  final SocialPalette palette;
  const _SkeletonList({required this.palette});

  @override
  State<_SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<_SkeletonList>
    with SingleTickerProviderStateMixin {
  // Subtle shimmer driven by a 1.4s ping-pong animation. We use the
  // controller value directly to interpolate a base / highlight color
  // — no Shimmer package needed.
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      itemCount: 4,
      physics: const NeverScrollableScrollPhysics(),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _SkeletonRow(
        palette: widget.palette,
        shimmer: _shimmer,
        // Stagger row widths so the skeleton doesn't look like a
        // perfect grid — feels more organic.
        bodyShortLine: i.isEven ? 0.65 : 0.85,
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  final SocialPalette palette;
  final Animation<double> shimmer;
  final double bodyShortLine; // 0..1 fraction of width for the 2nd line

  const _SkeletonRow({
    required this.palette,
    required this.shimmer,
    required this.bodyShortLine,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmer,
      builder: (_, __) {
        // Lerp between base + highlight tones. The same alpha is reused
        // for every shape in the row so they all pulse together.
        final base = palette.surface.withValues(alpha: 0.55);
        final highlight = palette.surface.withValues(alpha: 0.85);
        final color = Color.lerp(base, highlight, shimmer.value)!;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar placeholder.
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                decoration: BoxDecoration(
                  color: palette.surface.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: palette.border.withValues(alpha: 0.4),
                    width: 0.7,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Name placeholder
                    Container(
                      width: 80,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Body placeholder line 1 (full width).
                    Container(
                      width: double.infinity,
                      height: 9,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Body placeholder line 2 (partial).
                    LayoutBuilder(
                      builder: (_, c) => Container(
                        width: c.maxWidth * bodyShortLine,
                        height: 9,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// _ActionChip — pill-shaped tappable chip used for the inline Edit /
// Delete actions revealed on long-press in the comment thread.
class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
