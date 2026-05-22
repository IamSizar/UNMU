import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/expert_post.dart';
import 'comments_sheet.dart';

/// Comment icon + count. Tap opens the bottom-sheet thread.
///
/// Like [LikeButton], the count is held locally and synced from props on
/// rebuild. The sheet itself wires up live updates.
class CommentButton extends StatelessWidget {
  final ExpertPost post;
  final Color accent;
  final Color? mutedColor;
  final bool enabled;
  /// When false, the count beside the icon is hidden — used by the
  /// Instagram-style article card which renders comments as a "View
  /// all 12 comments" link below the caption instead.
  final bool showCount;
  /// Icon size — caller can size up for the new article card.
  final double iconSize;

  const CommentButton({
    super.key,
    required this.post,
    required this.accent,
    this.mutedColor,
    this.enabled = true,
    this.showCount = true,
    this.iconSize = 17,
  });

  @override
  Widget build(BuildContext context) {
    final muted = mutedColor ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                CommentsSheet.show(
                  context,
                  postId: post.id,
                  postOwnerExpertId: post.expertId,
                  accent: accent,
                );
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mode_comment_outlined, size: iconSize, color: muted),
              if (showCount) ...[
                const SizedBox(width: 5),
                Text(
                  '${post.comments}',
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
