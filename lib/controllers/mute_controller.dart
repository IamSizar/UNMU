import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device mute state for community chats. Whichever community
/// ids land in the muted set stop producing the global new-message
/// banner — they still arrive in the chat screen normally, the user
/// just doesn't get pinged when they're elsewhere in the app.
///
/// Storage: SharedPreferences (single string list under
/// `muted_community_ids`). Local-only — cross-device sync would
/// require a backend column on `users` and is deferred to v2.
///
/// Lifetime: registered as `permanent` in main.dart, hydrated on
/// first construction so the bell icon renders in its correct
/// state on the first chat-screen build after app launch.
class MuteController extends GetxController {
  static const _kPrefsKey = 'muted_community_ids';

  /// Reactive set of muted community ids. Use [isMuted] in builds
  /// instead of touching this directly so the dependency tracker
  /// re-runs on toggle.
  final RxSet<String> _muted = <String>{}.obs;

  bool _hydrated = false;

  @override
  void onInit() {
    super.onInit();
    _hydrate();
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kPrefsKey) ?? const [];
      _muted.assignAll(list);
    } catch (_) {
      // Storage unavailable — start with an empty set. Toggle
      // operations will retry the persist call so a transient
      // failure resolves on the user's next mute action.
    } finally {
      _hydrated = true;
    }
  }

  /// True if this community id is currently in the muted set.
  /// Reading this getter inside a build subscribes the widget to
  /// changes, so the bell icon updates immediately on toggle.
  bool isMuted(String communityId) => _muted.contains(communityId);

  /// Flip the muted state for [communityId]. Returns the new
  /// `isMuted` value so callers can fire a confirmation snackbar
  /// without a second read.
  Future<bool> toggle(String communityId) async {
    final nowMuted = !_muted.contains(communityId);
    if (nowMuted) {
      _muted.add(communityId);
    } else {
      _muted.remove(communityId);
    }
    // Best-effort persist — the in-memory state already updated.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kPrefsKey, _muted.toList());
    } catch (_) {/* see _hydrate comment */}
    return nowMuted;
  }

  bool get isHydrated => _hydrated;
}
