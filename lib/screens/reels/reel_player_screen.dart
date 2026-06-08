import 'package:flutter/material.dart';

import '../../widgets/video/unmu_video_player.dart';

/// Fullscreen single-video player — opens whenever a reel or video card
/// is tapped from the post viewer / community detail / expert profile.
///
/// As of the gesture-pack upgrade this screen is a thin wrapper around
/// [UnmuVideoPlayer], which handles:
///
///   * Tap to play / pause
///   * Double-tap right / left  → +5 s / −5 s seek with ripple animation
///   * Long-press anywhere       → 2× speed (TikTok-style)
///   * Rotate icon               → landscape fullscreen
///   * Pull-down in landscape    → return to portrait
///   * Lock icon in landscape    → freeze gestures
///   * Auto-hide controls after 3 s of inactivity
///   * Resume from last position (per-video, 30-day TTL)
///   * Buffering spinner + clear "video couldn't load" retry state
///
/// We keep the screen's own job small: pass the URL down, and inject
/// the author + title strip into the player's `bottomOverlay` slot so
/// the bottom chrome still reads "Sizar · my reel title" the way it
/// always has.
class ReelPlayerScreen extends StatelessWidget {
  final String mediaUrl;
  final String? coverUrl;
  final String? title;
  final String authorName;

  /// True for short reels (loop is the format expectation), false for
  /// long-form videos (a 30-minute clip looping forever is annoying).
  /// Caller picks based on PostType — defaults to true to preserve the
  /// legacy behavior of every existing call site.
  final bool loop;

  /// Quality renditions for the in-player quality gear. Maps label → URL
  /// (e.g. {"720p": "…"}); "Auto" = [mediaUrl]. Empty hides the gear.
  final Map<String, String> qualityVariants;

  /// Post's recorded duration (seconds), forwarded to [UnmuVideoPlayer] so it
  /// can reject a truncated transcoded variant and fall back to [mediaUrl].
  final int? expectedDurationSeconds;

  const ReelPlayerScreen({
    super.key,
    required this.mediaUrl,
    required this.authorName,
    this.coverUrl,
    this.title,
    this.loop = true,
    this.qualityVariants = const {},
    this.expectedDurationSeconds,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: UnmuVideoPlayer(
        url: mediaUrl,
        coverUrl: coverUrl,
        title: title,
        autoPlay: true,
        loop: loop,
        qualityVariants: qualityVariants,
        expectedDurationSeconds: expectedDurationSeconds,
        onClose: () => Navigator.of(context).pop(),
        bottomOverlay: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                authorName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 0.2,
                ),
              ),
              if (title != null && title!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  title!,
                  style: const TextStyle(
                    color: Color(0xFFE6EBF2),
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
