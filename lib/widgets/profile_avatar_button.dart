// =============================================================================
// profile_avatar_button.dart
//
// The signed-in user's initial, as a circular button for the top-right of a
// tab screen's app bar. Tapping it opens the Profile screen as a pushed
// route, so the system back gesture returns to wherever the user was.
//
// Why this exists: Profile used to occupy one of the four bottom-nav slots,
// which forced Indexes and Feed to share the remaining contextual slot — so
// whichever one you were not on was invisible. Moving Profile up here frees
// that slot and lets both Indexes and Feed have a permanent home in the bar.
//
// Extracted from a private copy that lived in feed_screen.dart, which was the
// only screen that had it. That copy opened EditProfileScreen; this one opens
// the full ProfileScreen, because Profile is no longer reachable any other
// way and edit-profile is only one thing inside it.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/social/social_tokens.dart';
import '../utils/haptic_utils.dart';

/// Circular initials button that opens the Profile screen.
class ProfileAvatarButton extends StatelessWidget {
  /// Diameter in logical pixels. The default matches the 34px circle the
  /// Feed screen already used, which sits comfortably in a Material app bar
  /// without enlarging it.
  final double size;

  const ProfileAvatarButton({super.key, this.size = 34});

  /// First character of the display name, falling back to the email, then to
  /// a neutral placeholder. Uses `characters` rather than `substring` so a
  /// name starting with an emoji or a combined Arabic glyph is not split
  /// mid-grapheme.
  String _initial(AuthController auth) {
    final user = auth.user;
    final source = (user?.name ?? user?.email ?? '?').trim();
    return (source.characters.firstOrNull ?? '?').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();

    return Obx(() {
      // Touching the observable registers this widget for rebuilds on
      // sign-in / sign-out / profile rename.
      auth.userObservable.value;

      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Semantics(
          button: true,
          label: 'nav.profile'.tr,
          child: InkWell(
            onTap: () {
              HapticUtils.tap();
              Get.to(() => const ProfileScreen());
            },
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    SocialTokens.cyan,
                    SocialTokens.cyan.withValues(alpha: 0.6),
                  ],
                ),
                border: Border.all(
                  color: SocialTokens.cyan.withValues(alpha: 0.55),
                  width: 1.4,
                ),
              ),
              child: Text(
                _initial(auth),
                style: TextStyle(
                  // Dark ink on the cyan fill in both themes — the gradient
                  // is a constant brand colour, so the text on top of it must
                  // be too, or it fails contrast in one mode or the other.
                  color: const Color(0xFF0A1628),
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.41,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}
