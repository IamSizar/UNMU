import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../models/expert_post.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/expert_post_service.dart';
import 'create_post_screen.dart';

/// Drafts + scheduled posts authored by the current expert (mig 0020,
/// item 4.15). Reached from the Studio AppBar.
///
/// Each row exposes:
///   * Edit  → opens CreatePostScreen pre-filled with the draft id.
///   * Publish — fires `/me/expert/drafts/:id/publish` (no schedule).
///     For scheduling the user goes through Edit → Save & Schedule.
///   * Delete — permanent, with confirm dialog.
class DraftsScreen extends StatefulWidget {
  const DraftsScreen({super.key});

  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  bool _loading = true;
  String? _error;
  List<ExpertPost> _drafts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ExpertPostService.listDrafts();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _drafts = res.drafts ?? const [];
      _error = res.error;
    });
  }

  Future<void> _publishNow(ExpertPost p) async {
    HapticFeedback.lightImpact();
    final res = await ExpertPostService.publishDraft(draftId: p.id);
    if (!mounted) return;
    if (res.error != null) {
      _snack(res.error!);
      return;
    }
    _snack('drafts.published'.tr);
    _load();
  }

  Future<void> _delete(ExpertPost p) async {
    HapticFeedback.lightImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('drafts.deleteTitle'.tr),
        content: Text(
          (p.title?.isNotEmpty ?? false)
              ? 'drafts.deleteBodyTitled'.trParams({'title': p.title!})
              : 'drafts.deleteBodyUntitled'.tr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: SocialTokens.down),
            child: Text('common.delete'.tr),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await ExpertPostService.deleteDraft(p.id);
    if (!mounted) return;
    if (err != null) {
      _snack(err);
      return;
    }
    _load();
  }

  Future<void> _edit(ExpertPost p) async {
    // Reuse the existing post-edit composer. Drafts use the same
    // partial-update endpoint internally (status stays 'draft' unless
    // the user hits Publish from the drafts row).
    final updated = await Navigator.of(context).push<ExpertPost>(
      MaterialPageRoute(
        builder: (_) => CreatePostScreen.edit(post: p),
      ),
    );
    if (updated != null) _load();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text('drafts.title'.tr),
        actions: [
          IconButton(
            tooltip: 'common.refresh'.tr,
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _body(palette),
    );
  }

  Widget _body(SocialPalette palette) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SocialTokens.down),
          ),
        ),
      );
    }
    if (_drafts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_note_rounded,
                  size: 56, color: palette.textMuted),
              const SizedBox(height: 12),
              Text(
                'drafts.emptyTitle'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator.adaptive(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        itemCount: _drafts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _DraftCard(
          post: _drafts[i],
          onEdit: () => _edit(_drafts[i]),
          onPublish: () => _publishNow(_drafts[i]),
          onDelete: () => _delete(_drafts[i]),
        ),
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  final ExpertPost post;
  final VoidCallback onEdit;
  final VoidCallback onPublish;
  final VoidCallback onDelete;
  const _DraftCard({
    required this.post,
    required this.onEdit,
    required this.onPublish,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final scheduled = post.status == PostStatus.scheduled;
    final accent = scheduled ? SocialTokens.cyan : SocialTokens.gold;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        scheduled
                            ? Icons.schedule_rounded
                            : Icons.edit_note_rounded,
                        size: 13,
                        color: accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        scheduled
                            ? 'drafts.scheduledLabel'
                                .trParams({'when': _short(post.publishAt)})
                            : 'drafts.draftLabel'.tr,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  post.postType.displayName,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                IconButton(
                  iconSize: 18,
                  tooltip: 'drafts.deleteTooltip'.tr,
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded,
                      color: palette.textMuted),
                ),
              ],
            ),
            if ((post.title ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                post.title!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
            if (post.body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                post.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: Text('drafts.edit'.tr),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SocialTokens.cyan,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: onPublish,
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: Text('drafts.publishNow'.tr),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _short(DateTime? t) {
    if (t == null) return '';
    final l = t.toLocal();
    return '${l.month}/${l.day} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
