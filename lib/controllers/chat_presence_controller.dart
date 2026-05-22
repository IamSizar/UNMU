import 'package:get/get.dart';

/// Tracks which community chat screen the user currently has on
/// screen — drives the global new-message banner: don't pop a
/// notification for messages in a community the user is already
/// reading.
///
/// The chat screen sets [activeCommunityId] in `initState` and
/// clears it in `dispose`. The banner widget reads this on every
/// realtime event and skips the toast when it matches.
///
/// Lifetime: registered as `permanent` in main.dart so multiple
/// chat-screen pushes don't churn its state.
class ChatPresenceController extends GetxController {
  /// id of the community whose chat is currently being viewed, or
  /// null when the user is anywhere else in the app.
  final Rxn<String> _activeCommunityId = Rxn<String>();

  String? get activeCommunityId => _activeCommunityId.value;

  void setActive(String communityId) {
    _activeCommunityId.value = communityId;
  }

  /// Pass the same id you set with [setActive] — the clear is a
  /// no-op if the user has since opened a different community
  /// (avoids races where dispose order is reversed).
  void clearActive(String communityId) {
    if (_activeCommunityId.value == communityId) {
      _activeCommunityId.value = null;
    }
  }
}
