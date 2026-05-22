import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/notifications_controller.dart';
import '../../localization/locale_format.dart';
import '../../models/user_notification.dart';
import '../social/social_tokens.dart';

/// Bell screen — list of every notification for the signed-in user, newest
/// first. "Mark all read" in the app bar zeroes the badge.
class UserNotificationsScreen extends StatelessWidget {
  const UserNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final ctrl = Get.find<NotificationsController>();

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'userNotifs.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          Obx(() => TextButton(
                onPressed: ctrl.unreadCount == 0
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        ctrl.markAllRead();
                      },
                child: Text(
                  'userNotifs.markAllRead'.tr,
                  style: TextStyle(
                    color: ctrl.unreadCount == 0
                        ? palette.textMuted
                        : SocialTokens.cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              )),
        ],
      ),
      body: SafeArea(
        child: Obx(() {
          final list = ctrl.notifications;
          final loading = ctrl.loading;

          if (loading && list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: SocialTokens.cyan),
              ),
            );
          }
          if (list.isEmpty) {
            return RefreshIndicator(
              color: SocialTokens.cyan,
              onRefresh: ctrl.reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 90, 32, 60),
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: SocialTokens.cyan.withValues(alpha: 0.15),
                            border: Border.all(
                                color: SocialTokens.cyan
                                    .withValues(alpha: 0.4)),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.notifications_none_rounded,
                            size: 32,
                            color: SocialTokens.cyan,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'userNotifs.emptyTitle'.tr,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'userNotifs.emptySubtitle'.tr,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 13.5,
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

          return RefreshIndicator(
            color: SocialTokens.cyan,
            onRefresh: ctrl.reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) =>
                  _NotificationTile(item: list[i], controller: ctrl),
            ),
          );
        }),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final UserNotification item;
  final NotificationsController controller;
  const _NotificationTile({required this.item, required this.controller});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final unread = item.unread;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        if (unread) controller.markRead(item.id);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          color: unread
              ? SocialTokens.cyan.withValues(alpha: 0.08)
              : palette.surface,
          border: Border.all(
            color: unread
                ? SocialTokens.cyan.withValues(alpha: 0.45)
                : palette.border,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SocialTokens.cyan.withValues(alpha: 0.15),
              ),
              alignment: Alignment.center,
              child: Icon(_iconForType(item.type),
                  size: 18, color: SocialTokens.cyan),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                      children: _buildLine(palette),
                    ),
                  ),
                  if (item.bodySnippet != null &&
                      item.bodySnippet!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.bodySnippet!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _relativeTime(item.createdAt),
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (unread)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: SocialTokens.cyan,
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'post_liked':
        return Icons.favorite_rounded;
      case 'post_commented':
        return Icons.mode_comment_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  List<TextSpan> _buildLine(SocialPalette palette) {
    final actor = item.actorName ?? 'userNotifs.actorFallback'.tr;
    String verb;
    switch (item.type) {
      case 'post_liked':
        verb = 'userNotifs.verbLiked'.tr;
        break;
      case 'post_commented':
        verb = 'userNotifs.verbCommented'.tr;
        break;
      default:
        verb = 'userNotifs.verbInteracted'.tr;
    }
    return [
      TextSpan(
        text: actor,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      TextSpan(
        text: verb,
        style: TextStyle(color: palette.textSecondary),
      ),
    ];
  }

  String _relativeTime(DateTime t) => LocaleFormat.relative(t);
}
