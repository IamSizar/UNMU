import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/expert_post.dart';
import '../../services/post_interaction_service.dart';

/// Heart icon + count. Tap toggles like/unlike with an optimistic update —
/// flips state + bumps count immediately, then calls the backend; on
/// failure, reverts.
///
/// The widget owns its own mutable state (initial value comes from
/// `post.liked` / `post.likes`) so the parent list doesn't have to rebuild
/// when the user taps. Realtime events from other clients are routed
/// through controller-level reloads, which rebuild this widget with new
/// initial values — that's fine.
class LikeButton extends StatefulWidget {
  final ExpertPost post;
  /// Color used for the filled heart + count text when liked.
  final Color accent;
  /// Optional muted color for the outline state. Defaults to the local
  /// theme's onSurfaceVariant so it inherits dark/light contrast.
  final Color? mutedColor;
  /// Disable in cases where the post is locked (subscribers only).
  final bool enabled;
  /// When false, the count beside the heart is hidden — used by the
  /// Instagram-style article card which renders "23 likes" as its own
  /// dedicated line below the action row.
  final bool showCount;
  /// Override the icon size if the caller wants a chunkier or skinnier
  /// heart. Default 18 matches the existing inline-card look.
  final double iconSize;

  const LikeButton({
    super.key,
    required this.post,
    required this.accent,
    this.mutedColor,
    this.enabled = true,
    this.showCount = true,
    this.iconSize = 18,
  });

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton>
    with SingleTickerProviderStateMixin {
  late bool _liked;
  late int _likes;
  bool _busy = false;
  late final AnimationController _bump;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.liked;
    _likes = widget.post.likes;
    _bump = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didUpdateWidget(covariant LikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload-driven rebuild — sync local state from the freshly fetched
    // post, but don't override an in-flight optimistic toggle.
    if (oldWidget.post.id != widget.post.id) {
      _liked = widget.post.liked;
      _likes = widget.post.likes;
    } else if (!_busy) {
      _liked = widget.post.liked;
      _likes = widget.post.likes;
    }
  }

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy || !widget.enabled) return;
    HapticFeedback.lightImpact();
    final wasLiked = _liked;
    setState(() {
      _liked = !wasLiked;
      _likes += wasLiked ? -1 : 1;
      if (_likes < 0) _likes = 0;
      _busy = true;
    });
    _bump
      ..value = 0
      ..forward();

    final newCount = wasLiked
        ? await PostInteractionService.unlike(widget.post.id)
        : await PostInteractionService.like(widget.post.id);

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (newCount == null) {
        // Revert.
        _liked = wasLiked;
        _likes = widget.post.likes;
      } else {
        _likes = newCount;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final muted = widget.mutedColor ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    final color = _liked ? widget.accent : muted;
    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.55,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: widget.enabled ? _toggle : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: Tween<double>(begin: 1.0, end: 1.25).animate(
                  CurvedAnimation(parent: _bump, curve: Curves.elasticOut),
                ),
                child: Icon(
                  _liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: widget.iconSize,
                  color: color,
                ),
              ),
              if (widget.showCount) ...[
                const SizedBox(width: 5),
                Text(
                  '$_likes',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
