/// Arabic / English localization map for the *notifications* surface:
///   * the unified notification inbox (All / Unread tabs, mark-all-read,
///     kind-driven default titles, empty/error states) — inbox_screen.dart
///   * the legacy stock-alert notifications list (login gate, empty state,
///     relative timestamps) — notifications_screen.dart
///   * the per-user social notifications screen (likes/comments lines,
///     empty state, mark-all-read) — user_notifications_screen.dart
///   * the bell icon + unread badge — notification_bell.dart
///
/// This file is OWNED by the notifications localization worker. The central
/// table at `app_translations.dart` merges these two maps in — do NOT add
/// these keys there directly.
///
/// Namespaces used here (avoids collisions with other workers):
///   inbox.  notifications.  userNotifs.  notifBell.
///
/// `common.*` keys are intentionally NOT redefined — they live centrally
/// (common.retry, common.ok, …).
///
/// NEVER translated (DATA, not UI): the actual notification title / body /
/// message text from the server or notification model, user/expert/community
/// NAMES, post titles, stock TICKERS, the brand "UNMU", and all
/// NUMBERS / timestamps. Only the static UI chrome lives here. Digits stay
/// Western even in AR; relative time is produced by `LocaleFormat.relative`.
///
/// INVARIANT: `notificationsEn` and `notificationsAr` MUST contain the exact
/// same set of keys. A missing Arabic key would leak English in RTL.
library;

const Map<String, String> notificationsEn = {
  // ── Inbox screen (inbox_screen.dart) ──
  'inbox.title': 'Notifications',
  'inbox.markAllRead': 'Mark all read',
  'inbox.tabAll': 'All',
  'inbox.tabUnread': 'Unread',
  'inbox.emptyTitle': 'You\'re all caught up.',
  'inbox.emptySubtitle': 'New notifications will land here.',
  // Kind-driven default titles (UI fallbacks, not server data).
  'inbox.kind.postLiked': 'New like',
  'inbox.kind.postCommented': 'New comment',
  'inbox.kind.subscriptionActive': 'Subscription active',
  'inbox.kind.subscriptionRejected': 'Subscription declined',
  'inbox.kind.subscriptionExpired': 'Subscription expired',
  'inbox.kind.communityMemberAdded': 'Joined community',
  'inbox.kind.communitySubscriptionActive': 'Joined community',
  'inbox.kind.communityOwnerChanged': 'Ownership changed',
  'inbox.kind.statusChange': 'Shariah status changed',
  'inbox.kind.purificationChange': 'Purification updated',
  'inbox.kind.fallback': 'Notification',
  'inbox.kind.communitySubscriptionRejected': 'Subscription declined',
  'inbox.kind.communitySubscriptionExpired': 'Subscription expired',
  'inbox.kind.communityJoinRequest': 'New join request',
  // Localized bodies for subscription / community lifecycle events.
  'inbox.body.communitySubscriptionActive':
      'Your request to join was approved.',
  'inbox.body.subscriptionActive': 'Your subscription is now active.',
  'inbox.body.subscriptionRejected': 'Your subscription request was declined.',
  'inbox.body.subscriptionExpired': 'Your subscription has expired.',
  'inbox.body.communitySubscriptionRejected':
      'Your request to join was declined.',
  'inbox.body.communitySubscriptionExpired':
      'Your community subscription has expired.',
  'inbox.body.communityJoinRequest': 'Requested to join @community',
  // Steps 6+7 — new subscriber / member / support reply.
  'inbox.kind.expertNewSubscriber': 'New subscriber',
  'inbox.body.expertNewSubscriber': 'Subscribed to you.',
  'inbox.kind.communityNewMember': 'New member',
  'inbox.body.communityNewMember': 'Joined @community',
  'inbox.kind.supportReply': 'Support reply',
  'inbox.body.supportReply': 'You have a new reply.',

  // ── Legacy stock-alert notifications list (notifications_screen.dart) ──
  'notifications.title': 'Notifications',
  'notifications.loginRequired': 'Please log in to view notifications',
  'notifications.empty': 'No notifications',

  // ── Per-user social notifications (user_notifications_screen.dart) ──
  'userNotifs.title': 'Notifications',
  'userNotifs.markAllRead': 'Mark all read',
  'userNotifs.emptyTitle': 'You\'re all caught up',
  'userNotifs.emptySubtitle':
      'New likes and comments on your posts will show up here.',
  'userNotifs.actorFallback': 'Someone',
  'userNotifs.verbLiked': ' liked your post',
  'userNotifs.verbCommented': ' commented on your post',
  'userNotifs.verbInteracted': ' interacted with your post',

  // ── Notification bell (notification_bell.dart) ──
  'notifBell.tooltip': 'Notifications',
};

const Map<String, String> notificationsAr = {
  // ── Inbox screen (inbox_screen.dart) ──
  'inbox.title': 'الإشعارات',
  'inbox.markAllRead': 'تعليم الكل كمقروء',
  'inbox.tabAll': 'الكل',
  'inbox.tabUnread': 'غير المقروءة',
  'inbox.emptyTitle': 'لقد اطّلعت على كل شيء.',
  'inbox.emptySubtitle': 'ستظهر الإشعارات الجديدة هنا.',
  // Kind-driven default titles (UI fallbacks, not server data).
  'inbox.kind.postLiked': 'إعجاب جديد',
  'inbox.kind.postCommented': 'تعليق جديد',
  'inbox.kind.subscriptionActive': 'الاشتراك مُفعَّل',
  'inbox.kind.subscriptionRejected': 'تم رفض الاشتراك',
  'inbox.kind.subscriptionExpired': 'انتهى الاشتراك',
  'inbox.kind.communityMemberAdded': 'انضممت إلى المجتمع',
  'inbox.kind.communitySubscriptionActive': 'انضممت إلى المجتمع',
  'inbox.kind.communityOwnerChanged': 'تغيّرت الملكية',
  'inbox.kind.statusChange': 'تغيّرت الحالة الشرعية',
  'inbox.kind.purificationChange': 'تم تحديث التطهير',
  'inbox.kind.fallback': 'إشعار',
  'inbox.kind.communitySubscriptionRejected': 'تم رفض الاشتراك',
  'inbox.kind.communitySubscriptionExpired': 'انتهى الاشتراك',
  'inbox.kind.communityJoinRequest': 'طلب انضمام جديد',
  // Localized bodies for subscription / community lifecycle events.
  'inbox.body.communitySubscriptionActive':
      'تمت الموافقة على طلب انضمامك.',
  'inbox.body.subscriptionActive': 'أصبح اشتراكك نشطاً الآن.',
  'inbox.body.subscriptionRejected': 'تم رفض طلب اشتراكك.',
  'inbox.body.subscriptionExpired': 'انتهى اشتراكك.',
  'inbox.body.communitySubscriptionRejected': 'تم رفض طلب انضمامك.',
  'inbox.body.communitySubscriptionExpired': 'انتهى اشتراكك في المجتمع.',
  'inbox.body.communityJoinRequest': 'طلب الانضمام إلى @community',
  // Steps 6+7 — new subscriber / member / support reply.
  'inbox.kind.expertNewSubscriber': 'مشترك جديد',
  'inbox.body.expertNewSubscriber': 'اشترك لديك.',
  'inbox.kind.communityNewMember': 'عضو جديد',
  'inbox.body.communityNewMember': 'انضم إلى @community',
  'inbox.kind.supportReply': 'رد الدعم',
  'inbox.body.supportReply': 'لديك رد جديد.',

  // ── Legacy stock-alert notifications list (notifications_screen.dart) ──
  'notifications.title': 'الإشعارات',
  'notifications.loginRequired': 'يرجى تسجيل الدخول لعرض الإشعارات',
  'notifications.empty': 'لا توجد إشعارات',

  // ── Per-user social notifications (user_notifications_screen.dart) ──
  'userNotifs.title': 'الإشعارات',
  'userNotifs.markAllRead': 'تعليم الكل كمقروء',
  'userNotifs.emptyTitle': 'لقد اطّلعت على كل شيء',
  'userNotifs.emptySubtitle':
      'ستظهر الإعجابات والتعليقات الجديدة على منشوراتك هنا.',
  'userNotifs.actorFallback': 'شخص ما',
  'userNotifs.verbLiked': ' أعجب بمنشورك',
  'userNotifs.verbCommented': ' علّق على منشورك',
  'userNotifs.verbInteracted': ' تفاعل مع منشورك',

  // ── Notification bell (notification_bell.dart) ──
  'notifBell.tooltip': 'الإشعارات',
};
