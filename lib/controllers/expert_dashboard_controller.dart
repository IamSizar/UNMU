import 'package:get/get.dart';

import '../models/expert_post.dart';
import '../services/expert_post_service.dart';
import '../services/studio_service.dart';

/// State for the Expert Studio (Step 2) — the authenticated expert's own posts.
///
/// Reactive surface:
///   * [posts]       — full list of the expert's posts (current filter)
///   * [activeType]  — null means "all types"; otherwise filters server-side
///   * [isLoading]   — true during refresh
class ExpertDashboardController extends GetxController {
  final RxList<ExpertPost> _posts = <ExpertPost>[].obs;
  final Rxn<PostType> _activeType = Rxn<PostType>();
  final RxBool _isLoading = false.obs;
  final RxnString _error = RxnString();

  List<ExpertPost> get posts => _posts;
  PostType? get activeType => _activeType.value;
  bool get isLoading => _isLoading.value;
  String? get error => _error.value;

  /// Quick counts for the dashboard summary tiles.
  int get articleCount => _posts.where((p) => p.postType == PostType.article).length;
  int get videoCount => _posts.where((p) => p.postType == PostType.video).length;
  int get reelCount => _posts.where((p) => p.postType == PostType.reel).length;

  // ─── Phase 3.1 — studio dashboard metrics ──────────────────────────
  // Cached server response so the metrics tiles can render the moment
  // the studio screen opens. Refreshed alongside the post list.
  final Rxn<StudioDashboard> _dashboard = Rxn<StudioDashboard>();
  final RxBool _dashboardLoading = false.obs;
  StudioDashboard? get dashboard => _dashboard.value;
  bool get dashboardLoading => _dashboardLoading.value;

  /// Pulls the dashboard metrics endpoint. Failures are non-fatal —
  /// the screen falls back to the local post counts if this fails.
  Future<void> refreshDashboard() async {
    _dashboardLoading.value = true;
    try {
      final res = await StudioService.dashboard();
      if (res.dashboard != null) _dashboard.value = res.dashboard;
    } finally {
      _dashboardLoading.value = false;
    }
  }

  /// Apply a fresh pricing pair locally so the dashboard reflects the
  /// change without a full round-trip refresh.
  void applyPricing({required int monthlyCents, required int yearlyCents}) {
    final d = _dashboard.value;
    if (d == null) return;
    _dashboard.value = StudioDashboard(
      expertId: d.expertId,
      expertName: d.expertName,
      monthlyPriceCents: monthlyCents,
      yearlyPriceCents: yearlyCents,
      currency: d.currency,
      subscribers: d.subscribers,
      engagement: d.engagement,
    );
  }

  /// Fetches posts for the active filter (or all types if no filter set).
  Future<void> refreshPosts() async {
    _isLoading.value = true;
    _error.value = null;
    try {
      final list = await ExpertPostService.myPosts(type: _activeType.value);
      _posts.assignAll(list);
    } catch (e) {
      _error.value = e.toString();
    } finally {
      _isLoading.value = false;
    }
  }

  /// Switch the active type filter and re-fetch.
  Future<void> setFilter(PostType? type) async {
    if (_activeType.value == type) return;
    _activeType.value = type;
    await refreshPosts();
  }

  /// Optimistically prepend a freshly-published post so the UI updates without
  /// a full round-trip refresh. Caller already verified the server returned a
  /// valid [ExpertPost].
  void prepend(ExpertPost post) {
    _posts.insert(0, post);
  }

  /// Replace a post by id with the updated version (e.g. after edit / hide).
  /// No-op if the id isn't in the current list (post may have been filtered
  /// out by the active type tab).
  void replace(ExpertPost updated) {
    final idx = _posts.indexWhere((p) => p.id == updated.id);
    if (idx >= 0) _posts[idx] = updated;
  }

  /// Optimistically drop a post from the list (e.g. after delete).
  void removeById(int id) {
    _posts.removeWhere((p) => p.id == id);
  }
}
