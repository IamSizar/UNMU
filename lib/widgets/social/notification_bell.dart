import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/notifications_controller.dart';
import '../../screens/notifications/inbox_screen.dart';
import '../../screens/social/social_tokens.dart';

/// Bell icon with an unread red dot — opens the unified InboxScreen
/// on tap. Drop into any AppBar or trailing toolbar slot.
class NotificationBell extends StatelessWidget {
  /// Tooltip + accessibility label. When null, falls back to the localized
  /// "Notifications" label.
  final String? tooltip;
  /// Tint of the bell icon. Defaults to the current theme's primary text.
  final Color? color;

  const NotificationBell({super.key, this.tooltip, this.color});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final iconColor = color ?? palette.textPrimary;
    final tooltipLabel = tooltip ?? 'notifBell.tooltip'.tr;

    return Obx(() {
      final ctrl = Get.find<NotificationsController>();
      final unread = ctrl.unreadCount;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: tooltipLabel,
            icon: Icon(
              unread > 0
                  ? Icons.notifications_rounded
                  : Icons.notifications_none_rounded,
              color: iconColor,
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              Get.to(() => const InboxScreen());
            },
          ),
          if (unread > 0)
            Positioned(
              right: 8,
              top: 8,
              child: IgnorePointer(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: unread > 9 ? 4 : 0,
                    vertical: 0,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 14,
                    minHeight: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65A6E),
                    shape: unread > 9 ? BoxShape.rectangle : BoxShape.circle,
                    borderRadius:
                        unread > 9 ? BorderRadius.circular(7) : null,
                    border: Border.all(color: palette.background, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: unread > 9
                      ? Text(
                          unread > 99 ? '99+' : '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      );
    });
  }
}
