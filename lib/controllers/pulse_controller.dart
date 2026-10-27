import 'dart:async';

import 'package:get/get.dart';

import '../models/pulse_item.dart';
import '../services/pulse_service.dart';
import 'auth_controller.dart';

/// =============================================================================
/// PulseController — state for UNMU Pulse (نبض أنمو).
///
/// Holds, and is the single source of truth for:
///   * [day]        today's Pulse (up to four items) and its load state
///   * saved state  which items the user saved ([isSaved]) + the saved list
///   * analytics    fire-and-forget events (opens, reads, shares…), de-duplicated
///
/// Loading never blanks the screen: a refresh keeps the last content visible
/// and only flags [refreshFailed] when it could not update, so a flaky
/// connection degrades to "slightly stale" instead of an empty page.
///
/// The backend is reached through [PulseApi], so tests pass a fake.
/// =============================================================================
class PulseController extends GetxController {
  PulseController({PulseApi? api}) : _api = api ?? HttpPulseApi();

  final PulseApi _api;

  // ── Today ───────────────────────────────────────────────────────────
  final Rxn<PulseDay> day = Rxn<PulseDay>();
  final RxBool loading = false.obs;

  /// Why the LAST load failed; null after a success.
  final Rxn<PulseFailure> failure = Rxn<PulseFailure>();

  /// True when a refresh failed but older content is still on screen.
  bool get refreshFailed => failure.value != null && day.value != null;

  // ── Saved ───────────────────────────────────────────────────────────
  final RxSet<int> _savedIds = <int>{}.obs;
  final RxList<PulseItem> savedItems = <PulseItem>[].obs;
  final RxBool savedLoading = false.obs;
  final Rxn<PulseFailure> savedFailure = Rxn<PulseFailure>();
  final RxBool savedHasMore = false.obs;
  bool _savedLoaded = false;

  // ── Analytics de-duplication ────────────────────────────────────────
  final Set<String> _sentOnce = <String>{};

  StreamSubscription<dynamic>? _authSub;

  @override
  void onInit() {
    super.onInit();
    _wireAuthLifecycle();
    if (Get.isRegistered<AuthController>() &&
        Get.find<AuthController>().isAuthenticated) {
      loadToday();
    }
  }

  @override
  void onClose() {
    _authSub?.cancel();
    super.onClose();
  }

  /// Signing out clears everything (another account must never see this one's
  /// saves); signing in loads Pulse for the new account.
  void _wireAuthLifecycle() {
    if (!Get.isRegistered<AuthController>()) return;
    final auth = Get.find<AuthController>();
    _authSub = auth.userObservable.stream.listen((user) {
      if (user == null) {
        day.value = null;
        failure.value = null;
        _savedIds.clear();
        savedItems.clear();
        savedHasMore.value = false;
        _savedLoaded = false;
        _sentOnce.clear();
      } else {
        loadToday();
      }
    });
  }

  // ── Today ───────────────────────────────────────────────────────────

  /// Loads today's Pulse. With [silent] the existing content stays visible and
  /// [loading] is not raised (used by pull-to-refresh, which has its own
  /// spinner).
  Future<void> loadToday({bool silent = false}) async {
    if (!silent) loading.value = true;
    final res = await _api.today();
    if (res.ok) {
      day.value = res.data;
      failure.value = null;
      _rememberSaved(res.data!.items);
    } else {
      failure.value = res.failure;
    }
    loading.value = false;
  }

  /// Pull-to-refresh entry point.
  Future<void> refreshToday() => loadToday(silent: true);

  // ── Single item ─────────────────────────────────────────────────────

  /// Loads one item with full details (used by the detail screen).
  Future<PulseResult<PulseItem>> loadItem(int id) async {
    final res = await _api.item(id);
    if (res.ok) _rememberSaved([res.data!]);
    return res;
  }

  // ── Archive ─────────────────────────────────────────────────────────

  Future<PulseResult<PulsePage>> loadArchive({
    String? from,
    String? to,
    String? query,
    int offset = 0,
  }) async {
    final res = await _api.archive(
      from: from,
      to: to,
      query: query,
      offset: offset,
    );
    if (res.ok) _rememberSaved(res.data!.items);
    return res;
  }

  // ── Saved ───────────────────────────────────────────────────────────

  bool isSaved(int itemId) => _savedIds.contains(itemId);

  /// Makes the saved ids match what the server just told us for these items.
  void _rememberSaved(List<PulseItem> items) {
    for (final it in items) {
      if (it.isSaved) {
        _savedIds.add(it.id);
      } else {
        _savedIds.remove(it.id);
      }
    }
  }

  /// Loads the first page of the user's saved items.
  Future<void> loadSaved() async {
    savedLoading.value = true;
    final res = await _api.saved();
    if (res.ok) {
      savedItems.assignAll(res.data!.items);
      savedHasMore.value = res.data!.hasMore;
      savedFailure.value = null;
      _savedLoaded = true;
      for (final it in res.data!.items) {
        _savedIds.add(it.id);
      }
    } else {
      savedFailure.value = res.failure;
    }
    savedLoading.value = false;
  }

  Future<void> loadMoreSaved() async {
    if (!savedHasMore.value || savedLoading.value) return;
    savedLoading.value = true;
    final res = await _api.saved(offset: savedItems.length);
    if (res.ok) {
      savedItems.addAll(res.data!.items);
      savedHasMore.value = res.data!.hasMore;
      for (final it in res.data!.items) {
        _savedIds.add(it.id);
      }
    }
    savedLoading.value = false;
  }

  /// Saves / unsaves with an optimistic update (the bookmark flips at once)
  /// and reverts if the server refuses. Returns the resulting saved state.
  Future<bool> toggleSave(PulseItem item) async {
    final wasSaved = isSaved(item.id);
    _applySaved(item, !wasSaved);

    final ok = wasSaved ? await _api.unsave(item.id) : await _api.save(item.id);
    if (!ok) {
      _applySaved(item, wasSaved); // revert
      return wasSaved;
    }
    track(wasSaved ? PulseEvent.unsave : PulseEvent.save, itemId: item.id);
    return !wasSaved;
  }

  void _applySaved(PulseItem item, bool saved) {
    if (saved) {
      _savedIds.add(item.id);
      if (_savedLoaded && !savedItems.any((i) => i.id == item.id)) {
        savedItems.insert(0, item.copyWith(isSaved: true));
      }
    } else {
      _savedIds.remove(item.id);
      savedItems.removeWhere((i) => i.id == item.id);
    }
  }

  // ── Analytics ───────────────────────────────────────────────────────

  /// Reports an event without waiting for it. With [once] the same event for
  /// the same item (and [scope], e.g. a date) is sent at most once per app
  /// session, so scrolling back and forth cannot inflate "read to the end".
  void track(
    String event, {
    int? itemId,
    bool once = false,
    String scope = '',
  }) {
    if (once && !_sentOnce.add('$event:${itemId ?? '-'}:$scope')) return;
    unawaited(_api.recordEvent(event, itemId: itemId));
  }

  /// "Pulse screen was shown" — once per Pulse day per app session.
  void trackDayViewed(String date) =>
      track(PulseEvent.viewDay, once: true, scope: date);
}
