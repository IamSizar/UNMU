import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'mock_social_data.dart';
import 'social_tokens.dart';

/// =============================================================================
/// Full-screen Video Player viewer — EDGE-TO-EDGE immersive.
///
/// No AppBar. The 16:9 video frame extends from the very top of the screen
/// (under the status bar). Floating glass overlay button (back) sits in
/// the safe area on top of the video. Below the frame, the description
/// and metadata scroll, and a sticky action bar pins to the bottom.
/// =============================================================================
class VideoPlayerScreen extends StatefulWidget {
  final ExpertVideo video;
  final Community community;
  const VideoPlayerScreen({
    super.key,
    required this.video,
    required this.community,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  bool _playing = false;
  bool _liked = false;
  bool _saved = false;
  bool _subscribed = false;

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final video = widget.video;
    final community = widget.community;
    final accent = SocialTokens.regionColor(community.regionCode);
    final hue = (video.thumbnailSeed * 47) % 360;
    final base = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.34).toColor();
    final accent2 =
        HSLColor.fromAHSL(1, ((hue + 35) % 360).toDouble(), 0.7, 0.55).toColor();
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          // ── Edge-to-edge video frame ──
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _playing = !_playing);
            },
            child: Stack(
              children: [
                Container(
                  // Full-bleed: width = screen width, height keeps 16:9 below
                  // the status-bar inset so the controls float comfortably.
                  height: MediaQuery.of(context).size.width * 9 / 16 +
                      topInset,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [base, accent2, base],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                // Decorative orb
                Positioned(
                  right: -50,
                  top: -50,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.10),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Bottom dark scrim for chip legibility
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.10),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ),
                // Center play / pause
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: _playing ? 64 : 84,
                    height: _playing ? 64 : 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 1.6,
                      ),
                    ),
                    child: Icon(
                      _playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: _playing ? 32 : 42,
                    ),
                  ),
                ),
                // Floating top-left back button (in the safe area)
                Positioned(
                  top: topInset + 8,
                  left: 12,
                  child: _GlassIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                // Top-right glass actions
                Positioned(
                  top: topInset + 8,
                  right: 12,
                  child: Row(
                    children: [
                      _GlassIconButton(
                        icon: Icons.cast_rounded,
                        onTap: () {},
                      ),
                      const SizedBox(width: 8),
                      _GlassIconButton(
                        icon: Icons.more_vert_rounded,
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
                // Bottom-left chips: MASTERCLASS + duration + community
                Positioned(
                  left: 12,
                  bottom: 12,
                  right: 12,
                  child: Row(
                    children: [
                      _glassPill(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.workspace_premium_rounded,
                              size: 11,
                              color: SocialTokens.gold,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'videoView.masterclass'.tr,
                              style: const TextStyle(
                                color: SocialTokens.gold,
                                fontWeight: FontWeight.w900,
                                fontSize: 9.5,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _glassPill(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 11,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              video.duration,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _glassPill(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    accent,
                                    accent.withValues(alpha: 0.55),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Text(
                                community.regionCode.substring(0, 1),
                                style: const TextStyle(
                                  color: Color(0xFF0A1628),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              community.regionCode,
                              style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Body content ──
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Text(
                  video.title,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                    letterSpacing: -0.4,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 13,
                      color: palette.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_compact(video.views)} ${'videoView.viewsSuffix'.tr}',
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.access_time_rounded,
                      size: 13,
                      color: palette.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      video.publishedAgo,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _authorRow(palette, accent),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'videoView.description'.tr,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        video.description,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 14,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _bottomBar(palette),
        ],
      ),
    );
  }

  Widget _glassPill({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  Widget _authorRow(SocialPalette palette, Color accent) {
    final video = widget.video;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [accent, accent.withValues(alpha: 0.55)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Text(
            video.title.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF0A1628),
              fontWeight: FontWeight.w900,
              fontSize: 17,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.community.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '${_compact(widget.community.memberCount)} ${'videoView.membersSuffix'.tr}',
                style: TextStyle(color: palette.textMuted, fontSize: 11.5),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: () {
            HapticFeedback.lightImpact();
            setState(() => _subscribed = !_subscribed);
          },
          icon: Icon(
            _subscribed ? Icons.check_rounded : Icons.add_rounded,
            size: 16,
          ),
          label: Text(
            _subscribed
                ? 'videoView.subscribed'.tr
                : 'videoView.subscribe'.tr,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _subscribed ? Colors.transparent : SocialTokens.cyan,
            foregroundColor:
                _subscribed ? SocialTokens.cyan : const Color(0xFF0A1628),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: SocialTokens.cyan, width: 1.2),
            ),
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(SocialPalette palette) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.subtleDivider)),
        ),
        child: Row(
          children: [
            _action(
              palette,
              icon: _liked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: _liked ? SocialTokens.down : palette.textSecondary,
              label: _compact(((widget.video.views) ~/ 18) + (_liked ? 1 : 0)),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _liked = !_liked);
              },
            ),
            _action(
              palette,
              icon: Icons.mode_comment_outlined,
              color: palette.textSecondary,
              label: _compact(widget.video.views ~/ 60),
              onTap: () {},
            ),
            _action(
              palette,
              icon: Icons.send_outlined,
              color: palette.textSecondary,
              label: 'videoView.share'.tr,
              onTap: () {},
            ),
            const Spacer(),
            _action(
              palette,
              icon: _saved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              color: _saved ? SocialTokens.gold : palette.textSecondary,
              label: _saved ? 'videoView.saved'.tr : 'videoView.save'.tr,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _saved = !_saved);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(
    SocialPalette palette, {
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

// ============================================================================
// Glass overlay icon button — same primitive used by the post detail
// floating overlay row.
// ============================================================================
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
