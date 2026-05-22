import 'dart:async';

import 'package:get/get.dart';

import '../models/expert_post.dart';
import '../services/expert_post_service.dart';
import '../services/realtime_service.dart';
import 'realtime_controller.dart';
import 'subscription_controller.dart';

/// One per Expert Profile screen — holds the posts + subscription state for
/// that specific expert.
///
/// Use [Get.put] with `tag: expertId` so multiple profiles can coexist
/// (e.g. when navigating back-and-forth) and one screen's data doesn't
/// stomp on another's:
///
///   final ctrl = Get.put(
///     ExpertProfileController(expertId: expertId),
///     tag: expertId,
///     permanent: false,
///   );
///
/// Then in [State.dispose] do `Get.delete<ExpertProfileController>(tag: expertId)`.
///
/// Reactive surface:
///   * [posts]      — newest-first list of posts for this expert
///   * [subscribed] — true when the backend says this user has access
///                    (active subscription OR is the expert themself)
///   * [loading]    — true during the initial fetch
class ExpertProfileController extends GetxController {
  final String expertId;
  ExpertProfileController({required this.expertId});

  final RxList<ExpertPost> _posts = <ExpertPost>[].obs;
  final RxBool _subscribed = false.obs;
  final RxBool _loading = true.obs;
  /// True after the most recent fetch succeeded (HTTP 200), even if the
  /// list came back empty. Lets the view differentiate "real expert with
  /// no visible posts" (show empty state) from "couldn't reach backend"
  /// (show mock fallback for unseeded demo experts).
  final RxBool _fetched = false.obs;

  StreamSubscription<RealtimeEvent>? _realtimeSub;

  List<ExpertPost> get posts => _posts;
  bool get subscribed => _subscribed.value;
  bool get loading => _loading.value;
  bool get fetchedOk => _fetched.value;

  @override
  void onInit() {
    super.onInit();
    reload();
    _wireRealtime();
  }

  /// Re-fetch from the backend. Called on initial load, after a subscription
  /// becomes active (so the locked teasers reveal), and when a new post is
  /// published on this expert's profile.
  Future<void> reload() async {
    _loading.value = true;
    final res = await ExpertPostService.listForExpert(expertId);
    if (res == null) {
      // Network error / 5xx — keep whatever we had cached, don't lie to
      // the UI about success. The view will fall back to mock data for
      // demo experts when fetchedOk has never flipped true.
      _loading.value = false;
      return;
    }
    _posts.assignAll(res.posts);
    _subscribed.value = res.subscribed;
    _fetched.value = true;
    _loading.value = false;

    // Keep the subscription side-controller in sync so the Subscribe CTA on
    // the hero immediately reflects the access we just learned about. This
    // is a no-op when the user already has a row cached.
    try {
      Get.find<SubscriptionController>().refreshExpert(expertId);
    } catch (_) {
      // Controller may not be registered in test environments.
    }
  }

  /// Listen on the global realtime event stream and refresh when something
  /// happens that could affect what this screen shows. Limiting to events
  /// for *this* expert avoids unnecessary refetches when other experts
  /// publish.
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
          // The server includes expertId in the payload so we only refresh
          // when the post belongs to *this* profile.
          final eid = ev.data['expertId']?.toString();
          if (eid == null || eid == expertId) reload();
          break;
        case 'subscription_active':
        case 'subscription_expired':
        case 'subscription_cancelled':
        case 'subscription_rejected':
          // Subscription transitions can flip access — but only refresh if
          // the event references this expert (to avoid thrashing).
          final eid = ev.data['expertId']?.toString();
          if (eid == null || eid == expertId) reload();
          break;
      }
    });
  }

  @override
  void onClose() {
    _realtimeSub?.cancel();
    super.onClose();
  }
}
