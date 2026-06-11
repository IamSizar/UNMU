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

  /// Per-filter result cache. Keyed by [_filterKey] ('all' | 'article' |
  /// 'video' | 'reel'). Lets a filter switch render the previously-loaded
  /// list INSTANTLY (no spinner, no wait) while a silent background refresh
  /// fetches fresh data. This is the difference between the Articles/Videos
  /// tabs feeling instant vs re-hitting the network on every tap.
  final Map<String, List<ExpertPost>> _cacheByFilter = {};
  final Map<String, bool> _hasMoreByFilter = {};

  String get _filterKey => _filter.value?.wireValue ?? 'all';

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

  /// Reload the feed for the current filter. Called on initial mount, on
  /// every realtime event that could affect the list, and via pull-to-
  /// refresh.
  ///
  /// Only flips the [loading] spinner when there's nothing already on
  /// screen for this filter — a refresh that has cached content to show
  /// stays silent so the list never flashes a spinner over real content.
  Future<void> reload() async {
    final key = _filterKey;
    final hasCached = (_cacheByFilter[key]?.isNotEmpty ?? false);
    if (!hasCached) _loading.value = true;
    final res = await FeedService.myFeed(
      type: _filter.value,
      limit: _pageSize,
    );
    if (res == null) {
      // Network error — keep what we have, don't lie about success.
      _loading.value = false;
      return;
    }
    // Guard against a filter switch that happened while this fetch was in
    // flight — don't clobber the now-active filter's list with stale data.
    if (key != _filterKey) {
      _cacheByFilter[key] = res;
      _hasMoreByFilter[key] = res.length >= _pageSize;
      return;
    }
    _cacheByFilter[key] = res;
    _hasMoreByFilter[key] = res.length >= _pageSize;
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
      // Keep the per-filter cache in sync so returning to this filter shows
      // the full paginated list, not just the first page.
      _cacheByFilter[_filterKey] = List<ExpertPost>.from(_posts);
      // If we got back less than a full page, there's nothing more to
      // fetch — stop trying.
      if (res.length < _pageSize) {
        _hasMore.value = false;
        _hasMoreByFilter[_filterKey] = false;
      }
    } finally {
      _loadingMore = false;
    }
  }

  /// Switch the active type filter. If we've loaded this filter before,
  /// show its cached list INSTANTLY (no spinner) and refresh in the
  /// background. Only the first visit to a filter pays a loading wait.
  Future<void> setFilter(PostType? type) async {
    if (_filter.value == type) return;
    _filter.value = type;
    final key = _filterKey;
    final cached = _cacheByFilter[key];
    if (cached != null) {
      // Instant: paint the cached page, no spinner, then refresh quietly.
      _posts.assignAll(cached);
      _hasMore.value = _hasMoreByFilter[key] ?? true;
      _loading.value = false;
      unawaited(reload());
      return;
    }
    // First time on this type filter. If the "all" feed is already loaded,
    // seed an instant view by filtering it client-side — so the tab paints
    // immediately with what we already have (zero extra perceived wait),
    // then the background fetch fills in the complete type page. This is
    // the "modern, not many requests" path: the user sees content instantly
    // and only one network request runs.
    if (type != null) {
      final allCache = _cacheByFilter['all'];
      if (allCache != null && allCache.isNotEmpty) {
        final seed = allCache.where((p) => p.postType == type).toList();
        if (seed.isNotEmpty) {
          _cacheByFilter[key] = seed; // keeps reload() spinner-free
          _posts.assignAll(seed);
          _hasMore.value = true;
          _loading.value = false;
          unawaited(reload());
          return;
        }
      }
    }
    // No cache and nothing to seed — do a normal (spinner) load.
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
        _cacheByFilter.clear();
        _hasMoreByFilter.clear();
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
