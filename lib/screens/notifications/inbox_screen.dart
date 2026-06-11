import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/notifications_controller.dart';
import '../../controllers/realtime_controller.dart';
import '../../localization/locale_format.dart';
import '../../models/inbox_item.dart';
import '../../services/inbox_service.dart';
import '../../services/realtime_service.dart';
import '../social/social_tokens.dart';

/// Unified notification inbox.
///
/// Replaces the older split between `NotificationsScreen` (stock
/// alerts) and `UserNotificationsScreen` (social/sub events). One
/// screen, two tabs (All / Unread), color + icon driven by the
/// row's `kind`. Read items stay in the list — we never delete on
/// read; the row just dims to ~40% opacity so the user can scroll
/// back through history.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<InboxItem> _items = const [];
  int _unread = 0;
  StreamSubscription<RealtimeEvent>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) HapticFeedback.selectionClick();
    });
    _load();
    _wireRealtime();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final res = await InboxService.list();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = res.items ?? const [];
      _unread = res.unreadCount;
      _error = res.error;
    });
    _syncBadge();
  }

  /// Keep the bell badge (NotificationsController) in lock-step with the
  /// inbox's unread count — one source of truth, so the two places that
  /// show the count never drift and the badge clears the instant a row is
  /// read here.
  void _syncBadge() {
    try {
      Get.find<NotificationsController>().setUnreadCount(_unread);
    } catch (_) {
      // Controller not registered — ignore; the bell reconciles on its
      // own next reload.
    }
  }

  /// Listen for `notification_created` events so the inbox updates
  /// without a full refetch when a new row lands. Soft refresh —
  /// we just re-pull the list rather than diff in-place.
  void _wireRealtime() {
    final RealtimeController rt;
    try {
      rt = Get.find<RealtimeController>();
    } catch (_) {
      return;
    }
    _realtimeSub = rt.events.listen((ev) {
      if (ev.type == 'notification_created' ||
          ev.type == 'subscription_active' ||
          ev.type == 'subscription_rejected' ||
          ev.type == 'subscription_expired') {
        _load();
      }
    });
  }

  Future<void> _markRead(InboxItem item) async {
    if (item.isRead) return;
    HapticFeedback.lightImpact();
    // Optimistic patch.
    setState(() {
      _items = _items
          .map((x) => x.id == item.id && x.source == item.source
              ? x.copyMarkedRead()
              : x)
          .toList();
      _unread = (_unread - 1).clamp(0, 1 << 30);
    });
    _syncBadge();
    final ok = await InboxService.markRead(item.source, item.id);
    if (!ok && mounted) {
      // Rollback the optimistic patch — the row stays unread.
      _load();
    }
  }

  Future<void> _markAllRead() async {
    if (_unread == 0) return;
    HapticFeedback.selectionClick();
    setState(() {
      _items = _items
          .map((x) => x.isRead ? x : x.copyMarkedRead())
          .toList();
      _unread = 0;
    });
    _syncBadge();
    final ok = await InboxService.markAllRead();
    if (!ok && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'inbox.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
        actions: [
          if (_unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                'inbox.markAllRead'.tr,
                style: TextStyle(
                  color: SocialTokens.cyan,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: TabBar(
            controller: _tabs,
            indicatorColor: SocialTokens.cyan,
            indicatorWeight: 3,
            labelColor: palette.textPrimary,
            unselectedLabelColor: palette.textMuted,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800),
            tabs: [
              Tab(text: 'inbox.tabAll'.tr),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('inbox.tabUnread'.tr),
                    if (_unread > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: SocialTokens.cyan.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: SocialTokens.cyan.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          _unread > 99 ? '99+' : '$_unread',
                          style: TextStyle(
                            color: SocialTokens.cyan,
                            fontWeight: FontWeight.w900,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildList(palette, _items),
          _buildList(palette, _items.where((i) => !i.isRead).toList()),
        ],
      ),
    );
  }

  Widget _buildList(SocialPalette palette, List<InboxItem> rows) {
    if (_loading && rows.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: palette.textMuted),
      );
    }
    if (_error != null && rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                color: palette.textMuted,
                size: 40,
              ),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textPrimary),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _load,
                child: Text('common.retry'.tr),
              ),
            ],
          ),
        ),
      );
    }
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_none_rounded,
                size: 56,
                color: palette.textMuted,
              ),
              const SizedBox(height: 14),
              Text(
                'inbox.emptyTitle'.tr,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'inbox.emptySubtitle'.tr,
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator.adaptive(
      color: SocialTokens.cyan,
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _InboxRow(
          item: rows[i],
          palette: palette,
          onTap: () => _markRead(rows[i]),
        ),
      ),
    );
  }
}

/// Maps a notification kind to its color + icon. Centralised so a
/// new kind only needs one entry here, not per-screen branches.
class _KindStyle {
  final IconData icon;
  final Color color;
  /// Translation KEY for the at-a-glance fallback title (resolved with
  /// `.tr` at render time — see `_InboxRow.build`).
  final String defaultTitleKey;

  /// Optional translation KEY for a localized body. When set, the row
  /// renders this (in the user's language) INSTEAD of the server's
  /// `body_snippet` — used for lifecycle events whose body is a fixed
  /// sentence (e.g. community join approved) that would otherwise leak
  /// English in Arabic. Left null for kinds whose body is real content
  /// (post title, comment text), which must show the server value as-is.
  final String? defaultBodyKey;

  /// Optional GetX `@param` name. When set, [defaultBodyKey] is rendered
  /// with `trParams({bodyParam: item.body})` — i.e. the server stores the
  /// single dynamic value (e.g. the community name) in `body_snippet` and
  /// the localized sentence is built around it on-device.
  final String? bodyParam;

  const _KindStyle({
    required this.icon,
    required this.color,
    required this.defaultTitleKey,
    this.defaultBodyKey,
    this.bodyParam,
  });
}

const _kindStyles = <String, _KindStyle>{
  // Social — post interactions
  'post_liked': _KindStyle(
    icon: Icons.favorite_rounded,
    color: Color(0xFFFF6B7A),
    defaultTitleKey: 'inbox.kind.postLiked',
  ),
  'post_commented': _KindStyle(
    icon: Icons.mode_comment_rounded,
    color: SocialTokens.cyan,
    defaultTitleKey: 'inbox.kind.postCommented',
  ),
  // Subscription lifecycle
  'subscription_active': _KindStyle(
    icon: Icons.check_circle_rounded,
    color: Color(0xFF10B981),
    defaultTitleKey: 'inbox.kind.subscriptionActive',
    defaultBodyKey: 'inbox.body.subscriptionActive',
  ),
  'subscription_rejected': _KindStyle(
    icon: Icons.cancel_rounded,
    color: Color(0xFFFF6B7A),
    defaultTitleKey: 'inbox.kind.subscriptionRejected',
    defaultBodyKey: 'inbox.body.subscriptionRejected',
  ),
  'subscription_expired': _KindStyle(
    icon: Icons.history_toggle_off_rounded,
    color: Color(0xFFF59E0B),
    defaultTitleKey: 'inbox.kind.subscriptionExpired',
    defaultBodyKey: 'inbox.body.subscriptionExpired',
  ),
  // Sent to the expert when someone subscribes — title shows the
  // subscriber (actorName), body is a localized fixed sentence.
  'expert_new_subscriber': _KindStyle(
    icon: Icons.person_add_alt_1_rounded,
    color: Color(0xFF10B981),
    defaultTitleKey: 'inbox.kind.expertNewSubscriber',
    defaultBodyKey: 'inbox.body.expertNewSubscriber',
  ),
  // Community lifecycle
  'community_member_added': _KindStyle(
    icon: Icons.group_add_rounded,
    color: Color(0xFF8B5CF6),
    defaultTitleKey: 'inbox.kind.communityMemberAdded',
  ),
  'community_owner_changed': _KindStyle(
    icon: Icons.workspace_premium_rounded,
    color: SocialTokens.gold,
    defaultTitleKey: 'inbox.kind.communityOwnerChanged',
  ),
  // Community join / subscription approved — body is a fixed sentence,
  // so localize it instead of showing the server's English snippet.
  'community_subscription_active': _KindStyle(
    icon: Icons.group_add_rounded,
    color: Color(0xFF10B981),
    defaultTitleKey: 'inbox.kind.communitySubscriptionActive',
    defaultBodyKey: 'inbox.body.communitySubscriptionActive',
  ),
  'community_subscription_rejected': _KindStyle(
    icon: Icons.cancel_rounded,
    color: Color(0xFFFF6B7A),
    defaultTitleKey: 'inbox.kind.communitySubscriptionRejected',
    defaultBodyKey: 'inbox.body.communitySubscriptionRejected',
  ),
  'community_subscription_expired': _KindStyle(
    icon: Icons.history_toggle_off_rounded,
    color: Color(0xFFF59E0B),
    defaultTitleKey: 'inbox.kind.communitySubscriptionExpired',
    defaultBodyKey: 'inbox.body.communitySubscriptionExpired',
  ),
  // Sent to the community owner — title shows the requester (actorName),
  // body localized around the community name held in body_snippet.
  'community_join_request': _KindStyle(
    icon: Icons.person_add_alt_1_rounded,
    color: Color(0xFF8B5CF6),
    defaultTitleKey: 'inbox.kind.communityJoinRequest',
    defaultBodyKey: 'inbox.body.communityJoinRequest',
    bodyParam: 'community',
  ),
  // Sent to the owner when a new member is approved — title shows the
  // member (actorName), body localized around the community name.
  'community_new_member': _KindStyle(
    icon: Icons.group_add_rounded,
    color: Color(0xFF8B5CF6),
    defaultTitleKey: 'inbox.kind.communityNewMember',
    defaultBodyKey: 'inbox.body.communityNewMember',
    bodyParam: 'community',
  ),
  // Admin replied to a support ticket — body is the reply preview (data),
  // localized fallback when empty.
  'support_reply': _KindStyle(
    icon: Icons.support_agent_rounded,
    color: SocialTokens.cyan,
    defaultTitleKey: 'inbox.kind.supportReply',
    defaultBodyKey: 'inbox.body.supportReply',
  ),
  // Stock-pipeline (legacy `notifications` table)
  'STATUS_CHANGE': _KindStyle(
    icon: Icons.bolt_rounded,
    color: SocialTokens.gold,
    defaultTitleKey: 'inbox.kind.statusChange',
  ),
  'PURIFICATION_CHANGE': _KindStyle(
    icon: Icons.eco_rounded,
    color: Color(0xFF10B981),
    defaultTitleKey: 'inbox.kind.purificationChange',
  ),
};

const _fallbackStyle = _KindStyle(
  icon: Icons.notifications_rounded,
  color: Color(0xFF94A3B8),
  defaultTitleKey: 'inbox.kind.fallback',
);

class _InboxRow extends StatelessWidget {
  final InboxItem item;
  final SocialPalette palette;
  final VoidCallback onTap;

  const _InboxRow({
    required this.item,
    required this.palette,
    required this.onTap,
  });

  String _relTime(DateTime t) => LocaleFormat.relative(t);

  @override
  Widget build(BuildContext context) {
    final style = _kindStyles[item.kind] ?? _fallbackStyle;
    final title = item.title.isNotEmpty
        ? item.title
        : (item.actorName.isNotEmpty
            ? item.actorName
            : style.defaultTitleKey.tr);
    // Body resolution, in priority order:
    //   1. Templated localized body (snippet holds the @param value).
    //   2. Server snippet when present (real data, e.g. a rejection reason).
    //   3. Localized default sentence for fixed-copy lifecycle events.
    //   4. The raw server body (kinds with no localized fallback).
    final String body;
    if (style.defaultBodyKey != null && style.bodyParam != null) {
      body = style.defaultBodyKey!.trParams({style.bodyParam!: item.body});
    } else if (item.body.isNotEmpty) {
      body = item.body;
    } else if (style.defaultBodyKey != null) {
      body = style.defaultBodyKey!.tr;
    } else {
      body = '';
    }
    return Opacity(
      // Read items dim so unread visually pop. Never deleted —
      // history stays scrollable.
      opacity: item.isRead ? 0.55 : 1.0,
      child: Material(
        color: palette.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              // Unread rows get a faint wash of the kind's color (heart-pink
              // for likes, cyan for comments, …) so they're scannable at a
              // glance; read rows stay plain (and are dimmed by the Opacity
              // wrapper above).
              color: item.isRead
                  ? null
                  : style.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: item.isRead
                    ? palette.border.withValues(alpha: 0.4)
                    : style.color.withValues(alpha: 0.45),
                width: item.isRead ? 0.6 : 0.9,
              ),
            ),
            child: Row(
              children: [
                // Color-coded icon disc — at-a-glance kind.
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: style.color.withValues(alpha: 0.16),
                    border: Border.all(
                      color: style.color.withValues(alpha: 0.55),
                      width: 1,
                    ),
                  ),
                  child: Icon(style.icon, size: 18, color: style.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _relTime(item.createdAt),
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 11,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!item.isRead) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: style.color,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
