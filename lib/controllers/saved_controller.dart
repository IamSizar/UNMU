import 'dart:async';

import 'package:get/get.dart';

import '../models/expert_post.dart';
import '../services/save_service.dart';
import '../services/realtime_service.dart';
import 'auth_controller.dart';
import 'realtime_controller.dart';

/// Single source of truth for "is post X saved?" across every screen.
///
/// Holds:
///   * [savedIds] — RxSet of post ids currently bookmarked (drives the
///                  filled-vs-outlined bookmark icon on every card)
///   * [posts]    — RxList of full Post objects for the saved-posts screen
///   * [loading]  — true during the initial fetch
///   * [fetchedOk]— flips true after the first successful 200 so the
///                  empty list can be distinguished from "couldn't fetch"
///
/// Optimistic updates flow through [toggle]: the icon flips immediately,
/// the network call follows, and on failure the change reverts.
class SavedController extends GetxController {
  final RxSet<int> _savedIds = <int>{}.obs;
  final RxList<ExpertPost> _posts = <ExpertPost>[].obs;
  final RxBool _loading = false.obs;
  final RxBool _fetchedOk = false.obs;

  StreamSubscription<RealtimeEvent>? _realtimeSub;
  StreamSubscription<dynamic>? _authSub;

  Set<int> get savedIds => _savedIds;
  List<ExpertPost> get posts => _posts;
  bool get loading => _loading.value;
  bool get fetchedOk => _fetchedOk.value;

  /// Quickly check if a post is saved without rebuilding everything.
  /// Use inside Obx to react to changes.
  bool isSaved(int postId) => _savedIds.contains(postId);

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

  /// Pull the saved-posts list + ids from the backend.
  Future<void> reload() async {
    _loading.value = true;
    final res = await SaveService.list();
    if (res == null) {
      _loading.value = false;
      return;
    }
    _posts.assignAll(res);
    _savedIds
      ..clear()
      ..addAll(res.map((p) => p.id));
    _fetchedOk.value = true;
    _loading.value = false;
  }

  /// Toggle save state with an optimistic update. Returns the new state
  /// (true = saved). Reverts on network failure and shows nothing — the
  /// caller can decide whether to surface a snackbar.
  Future<bool> toggle(ExpertPost post) async {
    final wasSaved = _savedIds.contains(post.id);
    // Optimistic update.
    if (wasSaved) {
      _savedIds.remove(post.id);
      _posts.removeWhere((p) => p.id == post.id);
    } else {
      _savedIds.add(post.id);
      // Prepend the freshly-saved post to the visible list so the saved
      // screen reflects it instantly.
      _posts.insert(0, post);
    }

    final ok = wasSaved
        ? await SaveService.unsave(post.id)
        : await SaveService.save(post.id);

    if (!ok) {
      // Revert.
      if (wasSaved) {
        _savedIds.add(post.id);
        _posts.insert(0, post);
      } else {
        _savedIds.remove(post.id);
        _posts.removeWhere((p) => p.id == post.id);
      }
      return wasSaved;
    }
    return !wasSaved;
  }

  void _wireAuthLifecycle() {
    final auth = Get.find<AuthController>();
    _authSub = auth.userObservable.stream.listen((user) {
      if (user == null) {
        _savedIds.clear();
        _posts.clear();
        _fetchedOk.value = false;
      } else {
        reload();
      }
    });
  }

  /// If the post was edited / hidden / deleted on the backend, our cached
  /// copy in [_posts] could be stale. Cheapest correct path: refetch.
  void _wireRealtime() {
    final RealtimeController rt;
    try {
      rt = Get.find<RealtimeController>();
    } catch (_) {
      return;
    }
    _realtimeSub = rt.events.listen((ev) {
      switch (ev.type) {
        case 'post_edited':
        case 'post_hidden':
        case 'post_deleted':
          if (_savedIds.isEmpty) return;
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
