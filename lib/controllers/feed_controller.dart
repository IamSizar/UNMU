import 'dart:async';

import 'package:get/get.dart';

import '../models/expert_post.dart';
import '../services/feed_service.dart';
import '../services/realtime_service.dart';
import 'auth_controller.dart';
import 'realtime_controller.dart';

/// Drives the bottom-nav **Feed** tab — one stream of posts from every
/// expert the user has an active subscription to.
///
/// Reactive surface:
///   * [posts]      — current filtered list, newest-first
///   * [filter]     — null = all types, else PostType.{article,video,reel}
///   * [loading]    — true during the initial load (subsequent reloads
///                    don't flip this so the list doesn't jump)
///   * [fetchedOk]  — true after the first successful 200; lets the UI
///                    distinguish "no subs yet" from "couldn't reach
///                    backend"
class FeedController extends GetxController {
  final RxList<ExpertPost> _posts = <ExpertPost>[].obs;
  final Rxn<PostType> _filter = Rxn<PostType>();
  final RxBool _loading = false.obs;
  final RxBool _fetchedOk = false.obs;
  /// True while the reels viewer is in user-toggled fullscreen mode.
  /// Lifted into the controller so the bottom-nav scaffold can react
  /// (hiding itself) without needing an InheritedWidget plumbing pass.
  /// The reels view owns the toggle — this is just the broadcast channel.
  final RxBool reelsFullscreen = false.obs;

  /// True while the bottom-nav Feed tab is the currently-active tab.
  /// [MainTabScaffold] flips this on every tab change. The reels viewer
  /// subscribes via a [Worker] so it can pause every video the moment
  /// the user leaves the Feed tab — the existing VisibilityDetector
  /// can't be relied on alone because IndexedStack wraps inactive
  /// children in Offstage, which suppresses the rendering layer
  /// VisibilityDetector hooks into.
  final RxBool isFeedTabActive = true.obs;
  /// True when the most recent paginated fetch returned a full page —
  /// signal to the UI that there's likely more content available. Flips
  /// false once the backend returns fewer than [_pageSize] rows, telling
  /// us we've hit the end of the user's accessible feed.
  final RxBool _hasMore = true.obs;
  /// Latch around the in-flight pagination request so rapid scroll
  /// triggers don't fire duplicate fetches. Separate from [_loading]
  /// because we don't want the spinner UI to flash on each loadMore.
  bool _loadingMore = false;

  /// How many posts the backend returns per page. Mirrors the default
  /// `limit` on `/api/me/feed`. Used by [loadMore] to decide whether the
  /// most recent fetch was a full page (meaning probably more available).
  static const int _pageSize = 50;

  StreamSubscription<RealtimeEvent>? _realtimeSub;
  StreamSubscription<dynamic>? _authSub;

  List<ExpertPost> get posts => _posts;
  PostType? get filter => _filter.value;
  bool get loading => _loading.value;
  bool get fetchedOk => _fetchedOk.value;
  bool get hasMore => _hasMore.value;
  bool get loadingMore => _loadingMore;

  @override
  void onInit() {
    super.onInit();
    _wireAuthLifecycle();
    _wireRealtime();
    // Initial load if already authed.
    final auth = Get.find<AuthController>();
    if (auth.isAuthenticated) {
      reload();
    }
  }

  /// Wipe + reload the feed. Called on initial mount, on filter change,
  /// on every realtime event that could affect the list, and via
  /// pull-to-refresh.
  Future<void> reload() async {
    _loading.value = true;
    final res = await FeedService.myFeed(
      type: _filter.value,
      limit: _pageSize,
    );
    if (res == null) {
      // Network error — keep what we have, don't lie about success.
      _loading.value = false;
      return;
    }
    _posts.assignAll(res);
    _fetchedOk.value = true;
    _hasMore.value = res.length >= _pageSize;
    _loading.value = false;
  }

  /// Append-load the next page using the oldest currently-loaded post's
  /// `createdAt` as the keyset cursor. Called by the reels viewer when
  /// the active page is near the end, and by the feed list when the
  /// scroll position approaches the bottom.
  ///
  /// No-ops when:
  ///   * a paginated fetch is already in flight ([_loadingMore]),
  ///   * the previous page returned fewer than [_pageSize] rows
  ///     ([_hasMore] is false), or
  ///   * the cache is empty (use [reload] for the first load).
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore.value || _posts.isEmpty) return;
    _loadingMore = true;
    try {
      final cursor = _posts.last.createdAt;
      final res = await FeedService.myFeed(
        type: _filter.value,
        before: cursor,
        limit: _pageSize,
      );
      if (res == null) {
        // Network error on a paginated fetch — leave _hasMore alone so
        // the next user-triggered loadMore tries again.
        return;
      }
      // Filter out anything we already have (defensive — same created_at
      // microsecond on two posts is rare but possible).
      final existingIds = _posts.map((p) => p.id).toSet();
      final fresh = res.where((p) => !existingIds.contains(p.id)).toList();
      _posts.addAll(fresh);
      // If we got back less than a full page, there's nothing more to
      // fetch — stop trying.
      if (res.length < _pageSize) {
        _hasMore.value = false;
      }
    } finally {
      _loadingMore = false;
    }
  }

  /// Switch the active type filter and re-fetch.
  Future<void> setFilter(PostType? type) async {
    if (_filter.value == type) return;
    _filter.value = type;
    // New filter = fresh page space; assume more available until the
    // first page returns short.
    _hasMore.value = true;
    await reload();
  }

  /// On login → load. On logout → clear so a stale list doesn't leak into
  /// the next session.
  void _wireAuthLifecycle() {
    final auth = Get.find<AuthController>();
    _authSub = auth.userObservable.stream.listen((user) {
      if (user == null) {
        _posts.clear();
        _fetchedOk.value = false;
      } else {
        reload();
      }
    });
  }

  /// Listen on every realtime event and reload whenever something happens
  /// that could change the feed contents:
  ///
  ///   * `post_published` from any expert the user has an active sub to
  ///   * `post_edited`, `post_hidden`, `post_deleted` — same
  ///   * subscription transitions (active / expired / cancelled / rejected)
  ///     since they expand or shrink which experts feed into the list
  ///
  /// We don't try to be clever about diffing — the list is small (<= 50)
  /// and a fresh backend query is cheap. Simpler beats clever here.
  void _wireRealtime() {
    final RealtimeController rt;
    try {
      rt = Get.find<RealtimeController>();
    } catch (_) {
      return;
    }
    _realtimeSub = rt.events.listen((ev) {
      switch (ev.type) {
        case 'post_published':
        case 'post_edited':
        case 'post_hidden':
        case 'post_deleted':
        case 'subscription_active':
        case 'subscription_expired':
        case 'subscription_cancelled':
        case 'subscription_rejected':
          reload();
          break;
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
