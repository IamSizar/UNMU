import 'dart:async';

import 'package:get/get.dart';

import '../models/user_notification.dart';
import '../services/inbox_service.dart';
import '../services/notification_service.dart';
import '../services/realtime_service.dart';
import 'auth_controller.dart';
import 'realtime_controller.dart';

/// Drives the bell icon + Notifications screen.
///
/// Listens on the realtime stream for `notification_created` events and
/// bumps the unread count + prepends to the cached list, so the bell red
/// dot lights up instantly without a poll.
///
/// Reactive surface:
///   * [unreadCount]   — drives the red dot / badge
///   * [notifications] — full list for the screen
///   * [loading]       — initial fetch
class NotificationsController extends GetxController {
  final RxList<UserNotification> _notifications = <UserNotification>[].obs;
  final RxInt _unreadCount = 0.obs;
  final RxBool _loading = false.obs;

  StreamSubscription<RealtimeEvent>? _realtimeSub;
  StreamSubscription<dynamic>? _authSub;

  List<UserNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount.value;
  bool get loading => _loading.value;

  /// Push an authoritative unread count. The unified [InboxScreen] owns the
  /// read actions (mark-one / mark-all via [InboxService]), so it calls this
  /// after every change to keep the bell badge in lock-step with what the
  /// user just did — no refetch round-trip, no drift between the two places
  /// that show the count (the bell + the inbox header).
  void setUnreadCount(int n) => _unreadCount.value = n < 0 ? 0 : n;

  @override
  void onInit() {
    super.onInit();
    _wireAuthLifecycle();
    _wireRealtime();
    final auth = Get.find<AuthController>();
    if (auth.isAuthenticated) {
      reload();
    }
  }

  /// Pull both the list and the unread count from the backend.
  /// The unread count comes from the **unified inbox** endpoint so
  /// the bell badge reflects social + stock notifications combined,
  /// not just social. The list still uses the legacy
  /// `NotificationService.list()` for any consumer that expects
  /// `UserNotification` shape — the InboxScreen itself fetches
  /// directly via [InboxService].
  Future<void> reload() async {
    _loading.value = true;
    final futures = await Future.wait([
      NotificationService.list(),
      InboxService.unreadCount(),
    ]);
    final list = futures[0] as List<UserNotification>?;
    final count = futures[1] as int;
    if (list != null) _notifications.assignAll(list);
    _unreadCount.value = count;
    _loading.value = false;
  }

  Future<void> markAllRead() async {
    // Optimistic: zero the badge, mark every cached row as read in-memory,
    // then reload to confirm.
    final now = DateTime.now();
    final patched = _notifications
        .map((n) => UserNotification(
              id: n.id,
              userId: n.userId,
              actorId: n.actorId,
              actorName: n.actorName,
              type: n.type,
              postId: n.postId,
              commentId: n.commentId,
              bodySnippet: n.bodySnippet,
              readAt: n.readAt ?? now,
              createdAt: n.createdAt,
            ))
        .toList();
    _notifications.assignAll(patched);
    _unreadCount.value = 0;
    await NotificationService.markAllRead();
  }

  Future<void> markRead(int id) async {
    final now = DateTime.now();
    final patched = _notifications.map((n) {
      if (n.id == id && n.readAt == null) {
        return UserNotification(
          id: n.id,
          userId: n.userId,
          actorId: n.actorId,
          actorName: n.actorName,
          type: n.type,
          postId: n.postId,
          commentId: n.commentId,
          bodySnippet: n.bodySnippet,
          readAt: now,
          createdAt: n.createdAt,
        );
      }
      return n;
    }).toList();
    _notifications.assignAll(patched);
    if (_unreadCount.value > 0) _unreadCount.value = _unreadCount.value - 1;
    await NotificationService.markRead(id);
  }

  void _wireAuthLifecycle() {
    final auth = Get.find<AuthController>();
    _authSub = auth.userObservable.stream.listen((user) {
      if (user == null) {
        _notifications.clear();
        _unreadCount.value = 0;
      } else {
        reload();
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
      if (ev.type == 'notification_created') {
        // The payload doesn't carry every field of the row (no created_at,
        // user_id, etc.) — easiest way to keep the UI honest is just to
        // refetch the list + count. Tiny call, only fires per real event.
        reload();
      }
    });
  }

  @override
  void onClose() {
    _realtimeSub?.cancel();
    _authSub?.cancel();
    super.onClose();
  }
}
