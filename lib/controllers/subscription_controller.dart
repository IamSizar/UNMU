import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/expert_subscription.dart';
import '../services/expert_subscription_service.dart';
import 'auth_controller.dart';
import 'realtime_controller.dart';

/// State for the user's subscription flow (Step 4).
///
/// One singleton controller — keeps a per-expert cache of the current
/// subscription so the expert profile screen, paywall card, and My
/// Subscriptions screen all read the same fresh state. Realtime
/// `subscription_*` events refresh the cache so admin actions show up in
/// the user's app without a manual reload.
class SubscriptionController extends GetxController {
  /// expertId → current subscription (or null if user has none).
  final RxMap<String, ExpertSubscription?> _byExpert =
      <String, ExpertSubscription?>{}.obs;

  /// All subs (any expert) for the My Subscriptions screen.
  final RxList<ExpertSubscription> _all = <ExpertSubscription>[].obs;
  final RxBool _isLoadingAll = false.obs;

  // Loading flags per-expert so a Subscribe / Cancel doesn't get fired twice.
  final RxSet<String> _busy = <String>{}.obs;

  // Realtime listeners. Cancelled in onClose.
  final List<StreamSubscription<dynamic>> _subs = [];

  List<ExpertSubscription> get all => _all;
  bool get isLoadingAll => _isLoadingAll.value;
  bool isBusy(String expertId) => _busy.contains(expertId);

  /// Latest known subscription for an expert. Returns null if we've never
  /// fetched it (caller should call [refreshExpert]).
  ExpertSubscription? forExpert(String expertId) => _byExpert[expertId];

  @override
  void onInit() {
    super.onInit();

    // Hook into realtime events so the cache stays fresh.
    final rt = Get.find<RealtimeController>();
    _subs.addAll([
      // Submitted by us (server confirms back even though we already have it)
      rt.events.where((e) => e.type == 'subscription_submitted').listen(_handleEvent),
      // Admin accepted → status flips to active, expires_at set
      rt.events.where((e) => e.type == 'subscription_active').listen(_handleEvent),
      // Admin rejected
      rt.events.where((e) => e.type == 'subscription_rejected').listen(_handleEvent),
      // User-initiated cancel
      rt.events.where((e) => e.type == 'subscription_cancelled').listen(_handleEvent),
      // Background expiry job flipped it
      rt.events.where((e) => e.type == 'subscription_expired').listen(_handleEvent),
    ]);

    // Reload everything when the user changes (account switch / login).
    ever<dynamic>(
      Get.find<AuthController>().userObservable,
      (_) {
        _byExpert.clear();
        _all.clear();
      },
    );
  }

  @override
  void onClose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.onClose();
  }

  /// Pull the latest subscription for an expert and cache it.
  Future<ExpertSubscription?> refreshExpert(String expertId) async {
    final sub = await ExpertSubscriptionService.currentForExpert(expertId);
    _byExpert[expertId] = sub; // null is meaningful — "no subscription"
    return sub;
  }

  /// Pull every subscription the user has — drives the My Subs screen.
  Future<void> refreshAll() async {
    _isLoadingAll.value = true;
    try {
      final list = await ExpertSubscriptionService.mySubscriptions();
      _all.assignAll(list);
      // Also rebuild the per-expert cache from this list so any open
      // expert profile screen reads the same row.
      final next = <String, ExpertSubscription?>{};
      for (final s in list) {
        final existing = next[s.expertId];
        if (existing == null || s.createdAt.isAfter(existing.createdAt)) {
          next[s.expertId] = s;
        }
      }
      _byExpert.assignAll(next);
    } finally {
      _isLoadingAll.value = false;
    }
  }

  /// User taps Subscribe in the modal.
  Future<({ExpertSubscription? sub, String? error})> subscribe({
    required String expertId,
    required SubPlan plan,
    required PaymentMethod method,
    String? paymentRef,
    String? receiptUrl,
    String? note,
    String? promoCode,
  }) async {
    if (_busy.contains(expertId)) {
      return (sub: null, error: 'Please wait — request in progress');
    }
    _busy.add(expertId);
    try {
      final result = await ExpertSubscriptionService.subscribe(
        expertId: expertId,
        plan: plan,
        method: method,
        paymentRef: paymentRef,
        receiptUrl: receiptUrl,
        note: note,
        promoCode: promoCode,
      );
      if (result.sub != null) {
        _byExpert[expertId] = result.sub;
      }
      return result;
    } finally {
      _busy.remove(expertId);
    }
  }

  /// User taps Cancel from the expert profile or My Subs screen.
  Future<({ExpertSubscription? sub, String? error})> cancel(
    int id, {
    String? expertId,
  }) async {
    final result = await ExpertSubscriptionService.cancel(id);
    if (result.sub != null) {
      final s = result.sub!;
      _byExpert[s.expertId] = s;
      // Patch the all-list in place so the My Subs screen updates instantly.
      final i = _all.indexWhere((x) => x.id == s.id);
      if (i >= 0) {
        _all[i] = s;
      }
    }
    return result;
  }

  // ───────────────────────────────────────────────────────────────────────
  // Realtime handler — refresh whatever the event touched, and for
  // human-relevant transitions (admin accepted / rejected your
  // request) pop an in-app snackbar so the user finds out without
  // having to open the My Subs screen.
  // ───────────────────────────────────────────────────────────────────────
  void _handleEvent(dynamic ev) {
    final type = (ev as dynamic).type as String?;
    final data = (ev as dynamic).data as Map<String, dynamic>?;
    if (data == null) return;
    final expertId = data['expertId']?.toString();
    if (expertId != null && expertId.isNotEmpty) {
      // Don't await — cheap fire-and-forget refresh.
      refreshExpert(expertId);
    }
    // Refresh the full list too so My Subs stays accurate.
    refreshAll();

    // ── Notify the user on the lifecycle events that matter ──
    // We only toast for `active` and `rejected` because those are
    // admin-driven transitions the user wouldn't otherwise know
    // about. `submitted` / `cancelled` are the user's own actions —
    // they already saw the inline confirmation.
    final expertName = data['expertName']?.toString() ??
        'subscription.expertFallback'.tr;
    if (type == 'subscription_active') {
      _toast(
        title: 'subscription.activeToastTitle'.tr,
        message: 'subscription.activeToastBody'.trParams({'name': expertName}),
        accent: const Color(0xFF10B981), // green for success
      );
    } else if (type == 'subscription_rejected') {
      final reason = data['reason']?.toString() ?? '';
      _toast(
        title: 'subscription.declinedToastTitle'.tr,
        message: reason.isNotEmpty
            ? 'subscription.declinedToastBodyReason'
                .trParams({'name': expertName, 'reason': reason})
            : 'subscription.declinedToastBody'.trParams({'name': expertName}),
        accent: const Color(0xFFFF6B7A), // rose for negative
      );
    }
  }

  /// Single shared snackbar helper so accept / reject styling stays
  /// consistent and we don't duplicate the long Get.snackbar config.
  void _toast({
    required String title,
    required String message,
    required Color accent,
  }) {
    if (Get.isSnackbarOpen) {
      Get.closeAllSnackbars();
    }
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 4),
      backgroundColor: const Color(0xFF0E1726).withValues(alpha: 0.97),
      colorText: Colors.white,
      borderColor: accent.withValues(alpha: 0.45),
      borderWidth: 1,
      borderRadius: 14,
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      shouldIconPulse: false,
      icon: Icon(
        Icons.workspace_premium_rounded,
        color: accent,
        size: 22,
      ),
    );
  }
}
