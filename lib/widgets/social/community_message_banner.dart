import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/chat_presence_controller.dart';
import '../../controllers/mute_controller.dart';
import '../../controllers/realtime_controller.dart';
import '../../screens/social/community_chat_screen.dart';
import '../../screens/social/mock_social_data.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/community_messages_service.dart';

/// Top-of-app new-message notifier.
///
/// Mounted once at the app root via the MaterialApp `builder` in
/// main.dart. The widget itself renders as a transparent passthrough
/// — its only job is to subscribe to the global realtime stream and
/// fire a `Get.snackbar` whenever a `community_message` event lands
/// that:
///
///   * isn't authored by the current user (no self-toasts),
///   * isn't for the community the user is currently chatting in
///     (already on screen — would be redundant),
///   * isn't for a community the user has muted.
///
/// Why a snackbar instead of a custom-painted banner: the previous
/// implementation rendered its own Material/InkWell stack, which
/// crashed with "No Overlay widget found" because IconButton's
/// tooltip tries to walk up to an Overlay ancestor — and the widget
/// sits OUTSIDE the navigator's Overlay (it wraps MaterialApp's
/// `child`). `Get.snackbar` uses the Navigator's overlay context
/// directly so it has none of those tree-position issues, and it
/// gets free dismiss-on-swipe, focus traversal, and platform-native
/// look as a bonus.
///
/// Tapping the snackbar's "Open" action pushes the matching
/// CommunityChatScreen. Default duration 3s; new messages while a
/// snackbar is already visible replace it via `Get.closeAllSnackbars`
/// then a fresh `Get.snackbar` — no stacking, no queue.
class CommunityMessageBanner extends StatefulWidget {
  final Widget child;
  const CommunityMessageBanner({super.key, required this.child});

  @override
  State<CommunityMessageBanner> createState() =>
      _CommunityMessageBannerState();
}

class _CommunityMessageBannerState extends State<CommunityMessageBanner> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    // Defer until after the first frame so the Navigator (and its
    // Overlay) is fully mounted — Get.snackbar needs the Overlay
    // context, and on a cold start the realtime stream may emit
    // before that's ready.
    WidgetsBinding.instance.addPostFrameCallback((_) => _wireRealtime());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _wireRealtime() {
    final RealtimeController rt;
    try {
      rt = Get.find<RealtimeController>();
    } catch (_) {
      // No realtime in this build (e.g. tests) — notifier stays inert.
      return;
    }
    _sub = rt.events.listen((ev) {
      if (ev.type != 'community_message') return;
      final msg = CommunityMessage.fromJson(ev.data);
      if (!_shouldShow(msg)) return;
      _showSnack(msg);
    });
  }

  bool _shouldShow(CommunityMessage m) {
    final auth = Get.find<AuthController>();
    final myId = auth.user?.id ?? -1;
    if (m.authorId == myId) return false; // own message — skip
    try {
      final presence = Get.find<ChatPresenceController>();
      if (presence.activeCommunityId == m.communityId) return false;
    } catch (_) {/* presence not registered yet — fall through */}
    try {
      final mute = Get.find<MuteController>();
      if (mute.isMuted(m.communityId)) return false;
    } catch (_) {/* mute not registered yet — fall through */}
    return true;
  }

  /// Look up the community in mock data so the snackbar's accent +
  /// "Open" target match the rest of the social UI. Returns null
  /// when the message is from a community we don't know about
  /// (shouldn't happen in practice — backend only broadcasts on
  /// channels we've subscribed to).
  Community? _findCommunity(String id) {
    for (final entry in MockSocialData.communities) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// Region → flag emoji used in the snackbar's tag line. Lets the
  /// user recognize which community a message is from at a glance
  /// even before reading the text. Falls back to a globe glyph for
  /// unknown codes.
  static const Map<String, String> _regionEmoji = {
    'US': '🇺🇸',
    'GCC': '🇸🇦',
    'MENA': '🌐',
    'EU': '🇪🇺',
    'ASIA': '🌏',
    'CN': '🇨🇳',
    'GLOBAL': '🌍',
  };

  void _showSnack(CommunityMessage m) {
    final community = _findCommunity(m.communityId);
    final accent = community == null
        ? SocialTokens.cyan
        : SocialTokens.regionColor(community.regionCode);
    final regionCode = community?.regionCode ?? '';
    final regionGlyph = _regionEmoji[regionCode] ?? '🌐';

    // Body text — for voice messages the body is empty; substitute
    // a sensible label so the snackbar isn't blank.
    final preview = m.body.isNotEmpty
        ? m.body
        : (m.attachmentType == 'audio'
            ? 'msgBanner.voiceMessage'.tr
            : 'msgBanner.newMessage'.tr);

    // Replace any in-flight snackbar so a quick burst of messages
    // doesn't queue up and bury the latest one.
    if (Get.isSnackbarOpen) {
      Get.closeAllSnackbars();
    }
    Get.snackbar(
      // Title/message strings still passed for screen-readers /
      // voice-over even though we render custom titleText/messageText.
      m.authorName,
      preview,
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 3),
      backgroundColor: const Color(0xFF0E1726).withValues(alpha: 0.97),
      colorText: Colors.white,
      borderColor: accent.withValues(alpha: 0.35),
      borderWidth: 1,
      borderRadius: 18,
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      maxWidth: 520,
      shouldIconPulse: false,
      boxShadows: [
        BoxShadow(
          color: accent.withValues(alpha: 0.18),
          blurRadius: 18,
          spreadRadius: -4,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
      // Avatar ring — initials of the author, ringed in the
      // community's region accent. The ring is what carries the
      // region identity here; the rest of the card stays neutral
      // dark so multiple regions in quick succession don't look
      // like a disco.
      icon: _NotificationAvatar(name: m.authorName, accent: accent),
      // Top row: author name + region tag line.
      titleText: Padding(
        padding: const EdgeInsetsDirectional.only(start: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              m.authorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
                letterSpacing: -0.2,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(regionGlyph, style: const TextStyle(fontSize: 11)),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    community?.name ?? 'msgBanner.community'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                if (regionCode.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      regionCode,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 9,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      messageText: Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, top: 4),
        child: Text(
          preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.86),
            fontSize: 12.5,
            height: 1.3,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      // "Open" action — region-tinted pill on the right that pushes
      // the chat. Without this the snackbar would be informational
      // only.
      mainButton: community == null
          ? null
          : TextButton(
              onPressed: () {
                Get.closeAllSnackbars();
                Get.to(() => CommunityChatScreen(community: community));
              },
              style: TextButton.styleFrom(
                backgroundColor: accent.withValues(alpha: 0.18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: accent.withValues(alpha: 0.55),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'msgBanner.open'.tr,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.3,
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pure passthrough — no Stack, no overlay, no IconButton with
    // tooltip. The notification surface is `Get.snackbar` triggered
    // from the realtime listener above.
    return widget.child;
  }
}

/// 40px circular avatar with the author's initials and a glowing
/// ring in the community's region color. This is the strongest
/// identity cue in the snackbar — at a glance the user can tell
/// who's messaging AND which community via the ring color, without
/// needing to read the title row.
class _NotificationAvatar extends StatelessWidget {
  final String name;
  final Color accent;

  const _NotificationAvatar({required this.name, required this.accent});

  String _initials(String n) {
    final parts = n.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.32),
            accent.withValues(alpha: 0.14),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.40),
            blurRadius: 8,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Text(
        _initials(name),
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w900,
          fontSize: 14,
          letterSpacing: -0.4,
        ),
      ),
    );
  }
}
