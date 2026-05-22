import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/saved_controller.dart';
import '../../models/expert_post.dart';

/// Bookmark icon — outlined when not saved, filled when saved. Tap toggles
/// via [SavedController.toggle], which handles the optimistic update +
/// network call + rollback on failure.
///
/// Reads the saved state reactively from SavedController — that means a
/// post saved on the profile screen lights up immediately on the feed
/// card too, with no manual refresh.
class SaveButton extends StatelessWidget {
  final ExpertPost post;
  /// Color used for the filled bookmark + count text when saved.
  final Color accent;
  /// Outline color when not saved. Defaults to onSurfaceVariant.
  final Color? mutedColor;
  final bool enabled;

  const SaveButton({
    super.key,
    required this.post,
    required this.accent,
    this.mutedColor,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final muted = mutedColor ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final ctrl = Get.find<SavedController>();

    return Obx(() {
      // SavedController is the live source of truth — fall back to the
      // post's initial server-provided `saved` flag for the very first
      // paint before the controller has fetched.
      final saved = ctrl.fetchedOk
          ? ctrl.isSaved(post.id)
          : (ctrl.isSaved(post.id) || post.saved);
      final color = saved ? accent : muted;

      return Opacity(
        opacity: enabled ? 1.0 : 0.55,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: enabled
              ? () async {
                  HapticFeedback.lightImpact();
                  await ctrl.toggle(post);
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Icon(
              saved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
              size: 18,
              color: color,
            ),
          ),
        ),
      );
    });
  }
}
