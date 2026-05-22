import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'package:get/get.dart';

import '../screens/expert/expert_welcome_dialog.dart';
import '../services/realtime_service.dart';
import 'auth_controller.dart';

/// Glue between [RealtimeService] (raw WebSocket events) and the rest of the
/// GetX controllers. Splits incoming events into typed Rx streams the app
/// can react to.
///
/// Reactive surface:
///
///   * [isConnected]       — true when the WS is open
///   * [latestEvent]       — fires for every event, useful for global toasts
///   * [onApplicationApproved], [onApplicationRejected], [onUserRoleChanged],
///     [onApplicationSubmitted], [onPostPublished]
///       — narrow streams for screens that only care about specific events
class RealtimeController extends GetxController {
  final RealtimeService _service = RealtimeService();
  StreamSubscription<RealtimeEvent>? _sub;

  final RxBool _isConnected = false.obs;
  bool get isConnected => _isConnected.value;

  final Rxn<RealtimeEvent> _latestEvent = Rxn<RealtimeEvent>();
  RealtimeEvent? get latestEvent => _latestEvent.value;

  /// Per-event-type broadcast streams. Screens / other controllers `.listen`
  /// to whichever ones they care about.
  final _appApproved = StreamController<RealtimeEvent>.broadcast();
  final _appRejected = StreamController<RealtimeEvent>.broadcast();
  final _appSubmitted = StreamController<RealtimeEvent>.broadcast();
  final _userRoleChanged = StreamController<RealtimeEvent>.broadcast();
  final _postPublished = StreamController<RealtimeEvent>.broadcast();
  /// Community-proposal lifecycle (added with the expert "Propose a
  /// community" flow). Backend emits these on the proposer's user channel
  /// when an admin approves or rejects in the dashboard.
  final _communityProposalApproved = StreamController<RealtimeEvent>.broadcast();
  final _communityProposalRejected = StreamController<RealtimeEvent>.broadcast();
  /// Generic broadcast — fires for *every* event regardless of type. Use
  /// this when you want to filter on `event.type` yourself (e.g. the
  /// SubscriptionController watches several `subscription_*` types).
  final _all = StreamController<RealtimeEvent>.broadcast();

  Stream<RealtimeEvent> get onApplicationApproved => _appApproved.stream;
  Stream<RealtimeEvent> get onApplicationRejected => _appRejected.stream;
  Stream<RealtimeEvent> get onApplicationSubmitted => _appSubmitted.stream;
  Stream<RealtimeEvent> get onUserRoleChanged => _userRoleChanged.stream;
  Stream<RealtimeEvent> get onPostPublished => _postPublished.stream;
  Stream<RealtimeEvent> get onCommunityProposalApproved =>
      _communityProposalApproved.stream;
  Stream<RealtimeEvent> get onCommunityProposalRejected =>
      _communityProposalRejected.stream;
  Stream<RealtimeEvent> get events => _all.stream;

  @override
  void onInit() {
    super.onInit();
    _sub = _service.events.listen(_dispatch);
    _wireAuthLifecycle();
  }

  /// Connect when the user logs in, disconnect when they log out. Watches
  /// the AuthController's user reactively.
  void _wireAuthLifecycle() {
    final auth = Get.find<AuthController>();
    // Initial state.
    if (auth.isAuthenticated) {
      connect();
    }
    // React to login / logout.
    ever<dynamic>(auth.userObservable, (user) {
      if (user != null) {
        connect();
      } else {
        disconnect();
      }
    });
  }

  Future<void> connect() async {
    await _service.connect();
    _isConnected.value = _service.isConnected;
  }

  void disconnect() {
    _service.disconnect();
    _isConnected.value = false;
  }

  void _dispatch(RealtimeEvent ev) {
    _latestEvent.value = ev;
    _all.add(ev);
    _isConnected.value = _service.isConnected;

    switch (ev.type) {
      case 'application_approved':
        _appApproved.add(ev);
        // Celebratory popup — fires once per approval, regardless of which
        // screen the user is on. The dialog itself guards against duplicates.
        ExpertWelcomeDialog.show();
        break;
      case 'application_rejected':
        _appRejected.add(ev);
        // Friendly inline notice — uses the reason if the server sent one.
        final reason = ev.data['rejectionReason']?.toString();
        Get.snackbar(
          'Application not approved',
          reason ?? 'Your expert application was reviewed and not approved.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 6),
        );
        break;
      case 'application_submitted':
        _appSubmitted.add(ev);
        break;
      case 'user_role_changed':
        _userRoleChanged.add(ev);
        // Refresh user data first so the dialog/snackbar reads fresh role.
        Get.find<AuthController>().refreshFromBackend();
        // If a dialog is already open (e.g. ExpertWelcomeDialog from the
        // sibling application_approved event), don't double-up — the dialog
        // owns the restart UX. Otherwise show a brief notice + restart so
        // every controller/widget re-bootstraps with the new role.
        if (!(Get.isDialogOpen ?? false)) {
          _scheduleSilentRestart(ev);
        }
        break;
      case 'post_published':
        _postPublished.add(ev);
        break;
      case 'community_proposal_approved':
        // An expert's proposed community was approved. Backend emits this
        // on the proposer's user channel; the studio already re-fetches on
        // re-entry so we just nudge with a snackbar deep-linking to the
        // new community.
        _communityProposalApproved.add(ev);
        Get.snackbar(
          '🎉 Community approved',
          'Your community "${ev.data['name'] ?? ''}" is now live. Open Studio to manage it.',
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 6),
        );
        break;
      case 'community_proposal_rejected':
        // Calmer notice with the admin-provided reason (if any) so the
        // expert understands what to change before resubmitting.
        _communityProposalRejected.add(ev);
        final reason = ev.data['rejectionReason']?.toString();
        Get.snackbar(
          'Community proposal rejected',
          reason ?? 'Your proposal was reviewed and not approved.',
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 6),
        );
        break;
    }
  }

  /// Show a brief snackbar that the role changed, then restart the app via
  /// Phoenix so all controllers and widgets re-bootstrap. Used when the role
  /// changes outside an explicit celebration flow (e.g. admin demotes /
  /// promotes a user). 2.5s delay gives the snackbar time to be read.
  void _scheduleSilentRestart(RealtimeEvent ev) {
    final newRole = ev.data['newRole']?.toString().toUpperCase() ?? 'updated';
    Get.snackbar(
      'Account updated',
      'Your role is now $newRole. Restarting…',
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFF0A1628),
      colorText: const Color(0xFF00D9FF),
      margin: const EdgeInsets.all(12),
      borderRadius: 12,
    );
    Future.delayed(const Duration(milliseconds: 2500), () {
      final ctx = Get.context;
      if (ctx != null) Phoenix.rebirth(ctx);
    });
  }

  @override
  void onClose() {
    _sub?.cancel();
    _service.disconnect();
    _appApproved.close();
    _appRejected.close();
    _appSubmitted.close();
    _userRoleChanged.close();
    _postPublished.close();
    _communityProposalApproved.close();
    _communityProposalRejected.close();
    _all.close();
    super.onClose();
  }
}
