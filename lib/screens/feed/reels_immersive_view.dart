import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../controllers/feed_controller.dart';
import '../../controllers/saved_controller.dart';
import '../../models/expert_post.dart';
import '../../services/events_service.dart';
import '../../services/post_interaction_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/social/animated_like_heart.dart';
import '../../widgets/social/comments_sheet.dart';
import '../social/expert_profile_screen.dart';
import '../social/social_tokens.dart';

/// Instagram-style immersive vertical reels viewer, embedded inside the
/// Feed tab. Renders one reel per page in a vertical PageView; swipe up
/// = next reel, swipe down = previous.
///
/// Memory hygiene: keeps at most three [VideoPlayerController]s alive
/// (current + one neighbour each side). Disposes anything further away.
/// Mute state is sticky across swipes — toggle it once and every reel in
/// this session honours it.
///
/// Pulls its reels straight from the [FeedController] (filtered to
/// `PostType.reel`), so realtime publishing / hiding / deleting refreshes
/// the strip live without manual reload.
class ReelsImmersiveView extends StatefulWidget {
  const ReelsImmersiveView({super.key});

  @override
  State<ReelsImmersiveView> createState() => _ReelsImmersiveViewState();
}

class _ReelsImmersiveViewState extends State<ReelsImmersiveView>
    with WidgetsBindingObserver {
  /// Page-to-controller map. Sparse — only entries near the active page
  /// are populated. Disposing an entry removes it.
  final Map<int, VideoPlayerController> _controllers = {};
  /// Indexes whose controller failed to initialize (bad URL, codec
  /// error, network drop, or 10s init timeout). The page renders a
  /// "Tap to retry" overlay instead of an infinite spinner. Removing an
  /// index from this set on the next [_spinUpController] call is what
  /// lets retry actually retry.
  final Set<int> _failedIndices = <int>{};
  /// Per-controller-init timeout. Without this, a half-broken stream
  /// (server hung, DNS slow, codec init wedged on a malformed file)
  /// would leave the page on an infinite spinner forever.
  static const Duration _initTimeout = Duration(seconds: 10);
  int _activeIndex = 0;
  bool _muted = false;
  /// User-toggled fullscreen — when true the active reel uses BoxFit.cover,
  /// every overlay (top exit bar, right rail, caption, scrubber) is hidden
  /// except a small floating exit button, the bottom navbar collapses, and
  /// the system UI (status bar / nav buttons) goes into immersive mode.
  /// Sticky across page swipes so the user can keep flicking through reels
  /// without re-entering fullscreen for each one.
  bool _fullscreen = false;
  late final PageController _pageController;

  /// True when this widget is currently visible on screen. Flips false
  /// when the user switches to a different bottom-nav tab (IndexedStack
  /// keeps us alive but offstage), or when the OS backgrounds the app.
  /// While false every controller is force-paused so audio doesn't keep
  /// playing in the background.
  bool _visible = true;

  /// Snapshot of which controller was playing when visibility was lost,
  /// so we can resume the right one (and only that one) when we come
  /// back into view. Avoids accidentally resuming a manually-paused reel.
  bool _wasPlayingBeforeHide = false;

  /// Worker subscription on [FeedController.isFeedTabActive] — the
  /// reliable signal the user has left the bottom-nav Feed tab. The
  /// existing VisibilityDetector can't catch this on its own because
  /// IndexedStack uses Offstage for inactive tabs, which suppresses
  /// the rendering layer VisibilityDetector hooks into.
  Worker? _tabActiveWatcher;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    // Spin up the first controllers once the first frame has laid out so
    // we know how many reels exist in FeedController.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureWindow(0));

    // Watch the Feed-tab-active flag so we pause the moment the user
    // taps a different bottom-nav tab (Profile, Watchlist, etc.). The
    // VisibilityDetector path covers swipe-out / app-background; this
    // covers the IndexedStack-tab-flip path that VisibilityDetector
    // misses.
    final feed = Get.find<FeedController>();
    _tabActiveWatcher = ever<bool>(feed.isFeedTabActive, (active) {
      if (!active) {
        // Capture playback state for the active reel BEFORE pausing
        // so when the user returns we resume the right one — same
        // logic as _onVisibilityChanged so the two paths converge.
        final c = _controllers[_activeIndex];
        _wasPlayingBeforeHide = c?.value.isPlaying ?? false;
        _pauseAll();
        // Force-exit fullscreen on tab leave so the bottom navbar
        // reappears when the user lands on the next tab.
        if (_fullscreen) {
          _fullscreen = false;
          _exitFullscreenSideEffects();
          if (mounted) setState(() {});
        }
      } else {
        // Returning to the Feed tab — only resume if the controller
        // was playing before AND VisibilityDetector currently sees us
        // (defensive against weird race conditions).
        if (_wasPlayingBeforeHide && _visible) {
          _syncPlayback();
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabActiveWatcher?.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    _pageController.dispose();
    // Belt-and-braces: if we somehow leave the screen still in fullscreen
    // (back-gesture mid-toggle, app suspend during animation, etc.) make
    // sure we restore the system UI + tell the bottom-nav scaffold to
    // bring its bar back. Otherwise the user is stuck with no navbar.
    if (_fullscreen) {
      _exitFullscreenSideEffects();
    }
    super.dispose();
  }

  /// App lifecycle — called when the OS backgrounds / foregrounds us.
  /// Mirrors the visibility-detector path so audio never leaks when the
  /// user switches apps either.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Foregrounded — only resume if we're still the visible tab.
      if (_visible) _syncPlayback();
    } else {
      // Inactive / paused / hidden / detached — pause everything.
      _pauseAll();
    }
  }

  /// Called by the VisibilityDetector when our render rect changes
  /// fraction-of-screen. Flips [_visible] + reconciles playback.
  /// Threshold: <50% → treat as gone (paused); >=50% → resume.
  void _onVisibilityChanged(VisibilityInfo info) {
    final nowVisible = info.visibleFraction >= 0.5;
    if (nowVisible == _visible) return;
    _visible = nowVisible;
    if (!_visible) {
      // Capture playing state for the active controller so we can
      // restore it on return without spuriously playing a paused reel.
      final c = _controllers[_activeIndex];
      _wasPlayingBeforeHide = c?.value.isPlaying ?? false;
      _pauseAll();
      // If the user left while in fullscreen (tapped a different tab),
      // force-exit so the bottom navbar isn't hidden the next time
      // they're elsewhere in the app — otherwise they'd be stuck.
      if (_fullscreen) {
        _fullscreen = false;
        _exitFullscreenSideEffects();
        if (mounted) setState(() {});
      }
    } else {
      // Returning into view — only resume the active controller, and
      // only if it was playing before.
      if (_wasPlayingBeforeHide) {
        _syncPlayback();
      }
    }
  }

  /// Pause every initialised controller. Used when leaving the tab or
  /// backgrounding the app.
  void _pauseAll() {
    for (final c in _controllers.values) {
      if (c.value.isInitialized && c.value.isPlaying) {
        c.pause();
      }
    }
  }

  /// Ensure controllers exist for [center - 1, center, center + 1] and that
  /// neighbouring reels are primed (first frame decoded) so swiping into
  /// them feels instant — no buffer pause, no black flash.
  ///
  /// Disposes anything outside that window. Idempotent — safe to call
  /// repeatedly while a previous invocation is still in flight.
  Future<void> _ensureWindow(int center) async {
    final reels = _reels;
    if (reels.isEmpty) return;
    final keep = <int>{};
    for (final i in [center - 1, center, center + 1]) {
      if (i >= 0 && i < reels.length) keep.add(i);
    }

    // 1. Drop neighbours that left the window.
    final toDrop = _controllers.keys.where((k) => !keep.contains(k)).toList();
    for (final k in toDrop) {
      final c = _controllers.remove(k);
      if (c == null) continue;
      try {
        await c.pause();
      } catch (_) {/* already disposed */}
      try {
        await c.dispose();
      } catch (_) {/* already disposed */}
    }

    // 2. Spin up missing controllers in **parallel** so the active page
    //    and its neighbours prime simultaneously instead of in a chain.
    //    The old sequential await-per-controller meant neighbours weren't
    //    ready by the time the user swiped — that's the buffer pause.
    final pending = <Future<void>>[];
    for (final i in keep) {
      if (_controllers.containsKey(i)) continue;
      pending.add(_spinUpController(i, reels[i]));
    }
    if (pending.isNotEmpty) {
      await Future.wait(pending);
    }

    // 3. Sync playback so exactly one controller plays (the active one),
    //    every neighbour stays paused at frame 0.
    _syncPlayback();
  }

  /// Initialize one controller for reel index [i]. Adds the controller
  /// to [_controllers] eagerly so concurrent [_ensureWindow] calls see
  /// it and don't double-init. On error or [_initTimeout] exceeded the
  /// index is added to [_failedIndices] so the page can render a
  /// tap-to-retry overlay instead of spinning forever.
  Future<void> _spinUpController(int i, ExpertPost post) async {
    final url = post.mediaUrl?.trim() ?? '';
    if (url.isEmpty) return;
    // Clear any prior failure flag — this might be a retry.
    _failedIndices.remove(i);
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _controllers[i] = c;
    try {
      // Race init against a 10s wall clock. If init never completes
      // (broken stream, DNS storm, etc.) we throw and fall through to
      // the "failed" branch instead of leaving the user staring at a
      // forever-spinner.
      await c.initialize().timeout(_initTimeout);
      await c.setLooping(true);
      await c.setVolume(_muted ? 0.0 : 1.0);
      // Seek to the start so the first frame is decoded right now —
      // when the user swipes here later, playback resumes from a
      // fully-rendered frame instead of black.
      await c.seekTo(Duration.zero);
    } catch (e) {
      // Network / codec / timeout. Mark this index failed so the page
      // shows a retry chip; keep the controller in the map (disposed
      // on retry) so we know we already tried.
      _failedIndices.add(i);
      // Best-effort admin instrumentation — surfaces "this reel won't
      // load" trends in the dashboard. Errors here are swallowed
      // inside EventsService.
      unawaited(EventsService.logReelLoadFailed(
        postId: post.id,
        errorKind: e is TimeoutException ? 'timeout' : 'init',
      ));
    }
    if (mounted) setState(() {});
  }

  /// Tap-to-retry handler — disposes the failed controller and spins up
  /// a fresh one. Driven by the [_RetryOverlay] inside [_ReelPage].
  Future<void> _retryController(int i) async {
    final reels = _reels;
    if (i < 0 || i >= reels.length) return;
    HapticUtils.tap();
    final old = _controllers.remove(i);
    if (old != null) {
      try {
        await old.dispose();
      } catch (_) {/* already disposed */}
    }
    if (!mounted) return;
    setState(() {});
    await _spinUpController(i, reels[i]);
    if (i == _activeIndex) _syncPlayback();
  }

  /// Reconcile playback state with [_activeIndex]. Exactly one initialised
  /// controller plays at a time; everyone else is paused. Idempotent.
  ///
  /// While the screen is hidden ([_visible] == false), this only ever
  /// pauses — never plays — so audio can't leak when the user is on
  /// another tab or has backgrounded the app.
  void _syncPlayback() {
    for (final entry in _controllers.entries) {
      final c = entry.value;
      if (!c.value.isInitialized) continue;
      if (entry.key == _activeIndex && _visible) {
        if (!c.value.isPlaying) c.play();
      } else {
        if (c.value.isPlaying) c.pause();
      }
    }
  }

  List<ExpertPost> get _reels {
    final ctrl = Get.find<FeedController>();
    return ctrl.posts.where((p) => p.postType == PostType.reel).toList();
  }

  void _onPageChanged(int index) {
    HapticUtils.pick();
    _activeIndex = index;
    // Reset every non-active controller to frame 0 so revisiting feels
    // fresh. The active one is left untouched — _syncPlayback hands it
    // play() in the next step.
    for (final entry in _controllers.entries) {
      if (entry.key != index && entry.value.value.isInitialized) {
        entry.value.seekTo(Duration.zero);
      }
    }
    // Flip playback immediately so the new page plays, even before any
    // newly-needed neighbours finish loading.
    _syncPlayback();
    // Top up the window — disposes the off-window neighbour, primes the
    // newly-in-window neighbour. Runs in the background.
    _ensureWindow(index);
    // Pagination — when the active index is within 3 pages of the end of
    // the loaded list, fire a paginated fetch so the next reels are
    // ready by the time the user swipes to them. The controller debounces
    // duplicate calls and stops when the backend returns short.
    final reels = _reels;
    if (reels.length - index <= 3) {
      Get.find<FeedController>().loadMore();
    }
    setState(() {});
  }

  void _toggleMute() {
    // `pick` matches the "flipping a switch" mental model — snappier
    // than `tap` for binary state toggles.
    HapticUtils.pick();
    setState(() => _muted = !_muted);
    for (final c in _controllers.values) {
      c.setVolume(_muted ? 0.0 : 1.0);
    }
  }

  /// True when the active reel's natural frame is wider than tall —
  /// e.g. a 16:9 podcast clip filmed on a tripod. Used by the fullscreen
  /// toggle to decide whether to rotate the phone to landscape.
  /// Returns false when the controller isn't ready yet (cover-fit on a
  /// loading reel does no harm).
  bool get _activeIsLandscape {
    final c = _controllers[_activeIndex];
    if (c == null || !c.value.isInitialized) return false;
    final s = c.value.size;
    if (s.height <= 0) return false;
    return s.width / s.height > 1.0;
  }

  /// Flip windowed ↔ fullscreen. Drives four things in lockstep:
  ///   1. Per-reel rendering — `_fullscreen` is forwarded into each
  ///      [_ReelPage] so it can swap BoxFit + hide chrome.
  ///   2. The bottom navbar — broadcast via [FeedController.reelsFullscreen]
  ///      so [MainTabScaffold] collapses the bar.
  ///   3. The system UI — status-bar + Android nav buttons go into
  ///      immersive sticky mode while fullscreen.
  ///   4. **Device orientation** — landscape clips force the phone to
  ///      rotate to landscape (either side) so the wide frame fills the
  ///      wide screen, YouTube-style. Portrait / square clips stay
  ///      locked portrait.
  void _toggleFullscreen() {
    HapticUtils.pick();
    final goingFullscreen = !_fullscreen;
    // Snapshot the orientation choice BEFORE flipping state so the
    // setState/build call has the right `_fullscreen` while the system
    // chrome + orientation calls fire concurrently.
    final wantLandscape = goingFullscreen && _activeIsLandscape;
    setState(() => _fullscreen = goingFullscreen);
    if (goingFullscreen) {
      _enterFullscreenSideEffects(landscape: wantLandscape);
    } else {
      _exitFullscreenSideEffects();
    }
  }

  void _enterFullscreenSideEffects({required bool landscape}) {
    Get.find<FeedController>().reelsFullscreen.value = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Landscape clips: allow EITHER landscape side so the user can hold
    // the phone whichever way is comfortable (left- or right-handed),
    // matching YouTube. Portrait/square clips keep portrait lock.
    SystemChrome.setPreferredOrientations(
      landscape
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp],
    );
  }

  void _exitFullscreenSideEffects() {
    // Best-effort — controller may already be torn down on app exit.
    try {
      Get.find<FeedController>().reelsFullscreen.value = false;
    } catch (_) {}
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    // Always snap back to portrait when leaving fullscreen — the rest of
    // the app is portrait-only, so a stray landscape lock would leave
    // the user wedged sideways on the next screen.
    SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.portraitUp],
    );
  }

  void _togglePlayPause() {
    final c = _controllers[_activeIndex];
    if (c == null || !c.value.isInitialized) return;
    HapticUtils.tap();
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // VisibilityDetector wraps the whole view so we get a callback the
    // moment the user switches to a different bottom-nav tab — that's
    // what kills the audio bleed-through.
    return VisibilityDetector(
      key: const Key('reels-immersive-view'),
      onVisibilityChanged: _onVisibilityChanged,
      child: Obx(() {
        final reels = _reels;
        if (reels.isEmpty) {
          return _EmptyReelsState();
        }
        return Container(
          color: Colors.black,
          child: Stack(
            children: [
              PageView.builder(
                scrollDirection: Axis.vertical,
                controller: _pageController,
                itemCount: reels.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (_, i) => _ReelPage(
                  post: reels[i],
                  controller: _controllers[i],
                  isActive: i == _activeIndex,
                  muted: _muted,
                  fullscreen: _fullscreen,
                  failed: _failedIndices.contains(i),
                  onTapVideo: _togglePlayPause,
                  onToggleMute: _toggleMute,
                  onToggleFullscreen: _toggleFullscreen,
                  onRetry: () => _retryController(i),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ============================================================================
// Single reel page — video + overlay UI.
//
// Owns the like state (lifted up from the right rail) so the double-tap
// gesture on the video can flip it AND spawn floating-heart animations
// at the tap position. Both surfaces — the rail icon and the floating
// heart — stay in sync because they read from the same parent state.
// ============================================================================
class _ReelPage extends StatefulWidget {
  final ExpertPost post;
  final VideoPlayerController? controller;
  final bool isActive;
  final bool muted;
  /// True while the user has toggled fullscreen on the strip. Switches
  /// the video from BoxFit.contain → BoxFit.cover, hides every overlay
  /// (top exit bar, right rail, caption, scrubber) except a small
  /// floating exit button in the corner.
  final bool fullscreen;
  /// True when this reel's controller failed to initialize (bad URL,
  /// codec error, timeout). Drives the [_RetryOverlay] — replaces the
  /// infinite loading spinner with a tappable retry chip.
  final bool failed;
  final VoidCallback onTapVideo;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onRetry;

  const _ReelPage({
    required this.post,
    required this.controller,
    required this.isActive,
    required this.muted,
    required this.fullscreen,
    required this.failed,
    required this.onTapVideo,
    required this.onToggleMute,
    required this.onToggleFullscreen,
    required this.onRetry,
  });

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  late bool _liked;
  late int _likes;
  bool _likeBusy = false;

  /// Active floating-heart animations spawned by recent double-taps.
  /// Each entry is a small record (id + page-local position). They self-
  /// remove via [_removeHeart] when the animation completes.
  final List<_HeartPop> _hearts = [];
  int _heartIdCounter = 0;

  /// Press-and-hold immersive mode: while [_immersive] is true the video
  /// is paused and every overlay (rail, captions, progress bar, mute,
  /// floating hearts) fades out so the user sees just the frame.
  /// Releasing the finger restores everything.
  bool _immersive = false;
  /// Whether the video was playing right before the user started holding —
  /// so releasing a hold on an already-paused reel doesn't accidentally
  /// resume it.
  bool _wasPlayingBeforeHold = false;

  /// Press-and-hold-on-edge fast-forward mode: when the user holds the
  /// LEFT or RIGHT 20% of the video, playback speed jumps to 2× until
  /// they release. The middle 60% triggers immersive mode instead.
  bool _speedMode = false;
  /// Captures the playback speed before we bumped it to 2× so we can
  /// restore exactly what the user had before (in case we ever expose a
  /// custom default speed setting).
  double _speedBefore = 1.0;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.liked;
    _likes = widget.post.likes;
  }

  @override
  void didUpdateWidget(covariant _ReelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Different reel (PageView re-used the slot) — pull fresh state.
    if (oldWidget.post.id != widget.post.id) {
      _liked = widget.post.liked;
      _likes = widget.post.likes;
      _likeBusy = false;
      _hearts.clear();
    }
  }

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    final wasLiked = _liked;
    setState(() {
      _liked = !wasLiked;
      _likes += wasLiked ? -1 : 1;
      if (_likes < 0) _likes = 0;
      _likeBusy = true;
    });
    final newCount = wasLiked
        ? await PostInteractionService.unlike(widget.post.id)
        : await PostInteractionService.like(widget.post.id);
    if (!mounted) return;
    setState(() {
      _likeBusy = false;
      if (newCount == null) {
        // Network error — revert to server-known state.
        _liked = wasLiked;
        _likes = widget.post.likes;
      } else {
        _likes = newCount;
      }
    });
  }

  /// Double-tap on the video — Instagram-style. Spawns a floating heart
  /// at the tap position; if the post wasn't already liked, also flips
  /// the like state. Double-tapping a liked post just shows the heart
  /// (it doesn't unlike — that matches Instagram).
  void _onDoubleTapDown(TapDownDetails details) {
    HapticUtils.tap();
    final id = ++_heartIdCounter;
    setState(() {
      _hearts.add(_HeartPop(id: id, position: details.localPosition));
    });
    if (!_liked) _toggleLike();
  }

  void _removeHeart(int id) {
    if (!mounted) return;
    setState(() => _hearts.removeWhere((h) => h.id == id));
  }

  /// User started a long-press on the video. Two zones:
  ///   * Left  20% or right 20% → fast-forward at 2× speed, no pause
  ///   * Middle 60%             → pause + immersive (fade overlays)
  ///
  /// The decision is made from `details.localPosition.dx` against the
  /// page's width so the bands feel right on every screen size.
  void _onLongPressStart(LongPressStartDetails details) {
    final c = widget.controller;
    if (c == null || !c.value.isInitialized) return;

    final width = MediaQuery.of(context).size.width;
    final x = details.localPosition.dx;
    final onEdge = x < width * 0.20 || x > width * 0.80;

    if (onEdge) {
      // 2× speed mode — keep playing, just faster. A `pick` haptic feels
      // right for "switching to a mode" — lighter and snappier than the
      // deliberate pause haptic below.
      HapticUtils.pick();
      _speedBefore = c.value.playbackSpeed;
      c.setPlaybackSpeed(2.0);
      setState(() => _speedMode = true);
    } else {
      // Pause + immersive mode. `confirm` haptic — heavier — because
      // pausing a video is a deliberate "I want to look at this frame"
      // action that deserves a substantive thump.
      HapticUtils.confirm();
      _wasPlayingBeforeHold = c.value.isPlaying;
      c.pause();
      setState(() => _immersive = true);
    }
  }

  /// Long-press lifted (or system-cancelled). Restores whichever mode
  /// was active: speed back to 1×, or resume video + fade chrome in.
  /// Safe to call when neither mode is active — it's a no-op.
  void _exitHoldMode() {
    final wasInAMode = _speedMode || _immersive;
    if (_speedMode) {
      setState(() => _speedMode = false);
      final c = widget.controller;
      if (c != null && c.value.isInitialized) {
        c.setPlaybackSpeed(_speedBefore == 0 ? 1.0 : _speedBefore);
      }
    }
    if (_immersive) {
      setState(() => _immersive = false);
      final c = widget.controller;
      if (c != null && c.value.isInitialized && _wasPlayingBeforeHold) {
        c.play();
      }
    }
    // Soft tap on release so the user feels the gesture finishing — only
    // if they were actually in a mode (not on a stray cancel).
    if (wasInAMode) HapticUtils.tap();
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        widget.controller != null && widget.controller!.value.isInitialized;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Background: cover image while loading, video once ready ──
        // Always cover-fit so there's never a letterbox on either side.
        if (!ready &&
            widget.post.coverUrl != null &&
            widget.post.coverUrl!.isNotEmpty)
          Positioned.fill(
            child: Image.network(
              widget.post.coverUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Colors.black),
            ),
          )
        else if (!ready)
          Positioned.fill(child: Container(color: Colors.black)),
        // Video. Two fits depending on fullscreen state:
        //   * Windowed (default) — BoxFit.contain, so the whole frame is
        //     visible. Horizontal/landscape clips get clean letterbox
        //     bars on top/bottom instead of having a chunk cropped out.
        //   * Fullscreen — BoxFit.cover, classic Instagram/TikTok feel:
        //     fills every pixel, may crop the long edge of off-aspect
        //     clips, but no black bars anywhere.
        if (ready)
          Positioned.fill(
            child: FittedBox(
              fit: widget.fullscreen ? BoxFit.cover : BoxFit.contain,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: widget.controller!.value.size.width,
                height: widget.controller!.value.size.height,
                child: VideoPlayer(widget.controller!),
              ),
            ),
          ),

        // ── Single + double-tap + long-press area covering the whole
        // video ──
        //
        // RawGestureDetector instead of GestureDetector so we can give
        // the long-press recogniser a custom 200ms duration (default is
        // 500ms which feels sluggish for the pause/2× hold). Tap and
        // double-tap stay on the default recognisers — the gesture
        // arena disambiguates them naturally.
        //
        // Behaviour:
        //   * Single tap  → toggle play/pause.
        //   * Double tap  → like + spawn the floating heart at position.
        //   * Long-press CENTER → pause + hide all overlays (immersive).
        //   * Long-press LEFT/RIGHT edge → 2× playback speed.
        //   * Releasing   → restore (speed back to 1×, or fade chrome
        //                   back in + resume).
        Positioned.fill(
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                () => TapGestureRecognizer(),
                (TapGestureRecognizer r) {
                  r.onTap = widget.onTapVideo;
                },
              ),
              DoubleTapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                      DoubleTapGestureRecognizer>(
                () => DoubleTapGestureRecognizer(),
                (DoubleTapGestureRecognizer r) {
                  r.onDoubleTapDown = _onDoubleTapDown;
                  // Empty handler so the arena treats the gesture as a
                  // genuine double-tap — without it, only the down
                  // callback fires and double-tap can lose the arena.
                  r.onDoubleTap = () {};
                },
              ),
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                      LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: const Duration(milliseconds: 200),
                ),
                (LongPressGestureRecognizer r) {
                  r.onLongPressStart = _onLongPressStart;
                  r.onLongPressEnd = (_) => _exitHoldMode();
                  r.onLongPressCancel = _exitHoldMode;
                },
              ),
            },
          ),
        ),

        // ── Floating-heart layer — pop-up animations from double-taps.
        // Each heart is its own Positioned widget. The dimmedByImmersive
        // flag fades them out alongside the rest of the chrome.
        for (final h in _hearts)
          _FloatingHeart(
            key: ValueKey(h.id),
            position: h.position,
            dimmed: _immersive,
            onDone: () => _removeHeart(h.id),
          ),

        // ── Centered pause overlay when paused ──
        if (ready && !widget.controller!.value.isPlaying)
          Center(child: _fadeChild(_centeredPauseIcon())),

        // ── Retry overlay (init failed / 10s timeout) OR loading
        // spinner (still initialising). The retry overlay wins
        // whenever we're flagged failed — the spinner only shows
        // while the controller is genuinely still warming up. ──
        if (!ready && widget.failed)
          Center(child: _fadeChild(_RetryOverlay(onRetry: widget.onRetry)))
        else if (!ready)
          Center(
            child: _fadeChild(
              const CircularProgressIndicator(color: Colors.white),
            ),
          ),

        // ── Bottom: scrubber. Sits flush against the top edge of the
        // bottom navbar (TikTok-style "navbar cap"). Tap-to-seek and
        // drag-to-scrub are wired in [_ProgressBar] itself; the visible
        // bar grows from 2.5px → 6px while the user is touching it, and
        // a small floating timestamp pill follows their finger.
        // Hidden in fullscreen so the video can use every pixel.──
        if (ready && !widget.fullscreen)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _fadeChild(
              _ProgressBar(controller: widget.controller!),
            ),
          ),

        // ── Top exit bar — back-arrow (left) + REELS wordmark (center)
        // + mute + fullscreen toggle (right). Sits inside SafeArea so
        // it never collides with the status-bar clock / signal icons.
        // Fades out alongside the rest of the chrome on long-press.
        //
        // Hidden entirely while in fullscreen — the only escape from
        // fullscreen is the small floating exit chip rendered further
        // down the stack.
        //
        // No background scrim — the icons + wordmark each carry their
        // own black-blur text shadow, which is enough contrast on bright
        // video frames without darkening the top of the screen.
        if (!widget.fullscreen)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: _fadeChild(
              Container(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 18),
                child: Row(
                  children: [
                    // Back-arrow exits Reels mode by flipping the Feed
                    // filter back to All — the AppBar reappears + the
                    // card list returns.
                    IconButton(
                      tooltip: 'reelsImmersive.exitReels'.tr,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white,
                        size: 30,
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 12),
                        ],
                      ),
                      onPressed: () {
                        HapticUtils.tap();
                        Get.find<FeedController>().setFilter(null);
                      },
                    ),
                    const Spacer(),
                    Text(
                      'reelsImmersive.reels'.tr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: -0.3,
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 12),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        widget.muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 22,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 12),
                        ],
                      ),
                      onPressed: widget.onToggleMute,
                    ),
                    // Fullscreen toggle — sits right next to mute so the
                    // top-right is a self-contained "playback controls"
                    // cluster (matching YouTube / IG conventions).
                    IconButton(
                      tooltip: 'reelsImmersive.fullscreen'.tr,
                      icon: const Icon(
                        Icons.fullscreen_rounded,
                        color: Colors.white,
                        size: 24,
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 12),
                        ],
                      ),
                      onPressed: widget.onToggleFullscreen,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Right rail: like / comment / save / share ──
        // Hidden in fullscreen so the video face stays uncluttered.
        if (!widget.fullscreen)
          Positioned(
            right: 6,
            bottom: 80,
            child: SafeArea(
              child: _fadeChild(
                _RightRail(
                  post: widget.post,
                  liked: _liked,
                  likes: _likes,
                  onLikeTap: _toggleLike,
                ),
              ),
            ),
          ),

        // ── Bottom-left: author + caption + tickers ──
        // Lifted from bottom:16 → bottom:32 to clear the scrubber's
        // ~28px touch zone, so dragging the bar can never accidentally
        // land on a caption tap. Hidden in fullscreen.
        if (!widget.fullscreen)
          Positioned(
            left: 14,
            right: 80,
            bottom: 32,
            child: SafeArea(
              child: _fadeChild(_BottomMeta(post: widget.post)),
            ),
          ),

        // ── Floating "exit fullscreen" chip ──
        // Only renders while in fullscreen. Small, semi-transparent, in
        // the top-right corner so it stays out of the way but is always
        // available — otherwise the user is stuck in fullscreen.
        if (widget.fullscreen)
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Material(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: widget.onToggleFullscreen,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.fullscreen_exit_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Centred dimmed-disc with a play-icon; shown when the video is
  /// paused. Extracted so the build method reads a bit cleaner.
  Widget _centeredPauseIcon() => IgnorePointer(
        child: Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.45),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.play_arrow_rounded,
              color: Colors.white, size: 56),
        ),
      );

  /// Wraps an overlay's *inner* child with an `AnimatedOpacity` so the
  /// long-press immersive mode cleanly fades it out. Lives inside
  /// `Positioned` / `Center` widgets so we never break the
  /// `Positioned-must-be-direct-child-of-Stack` invariant.
  ///
  /// [IgnorePointer] flips on while faded so an invisible icon can't be
  /// accidentally tapped.
  Widget _fadeChild(Widget child) {
    return IgnorePointer(
      ignoring: _immersive,
      child: AnimatedOpacity(
        opacity: _immersive ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}

/// Plain data record — id + page-local tap position — backing one
/// floating heart in [_ReelPageState._hearts].
class _HeartPop {
  final int id;
  final Offset position;
  const _HeartPop({required this.id, required this.position});
}

// ============================================================================
// Bottom progress bar — thin track that fills as the video plays.
//
// Interactive: tap anywhere on it to seek to that fraction of the clip,
// or drag horizontally to scrub. While dragging, the bar fattens from
// 2.5px → 6px and a small timestamp pill floats above the user's
// finger. The video pauses for the duration of the scrub so the bar
// can lead — playback resumes when the finger lifts.
//
// Hit zone is 28px tall (transparent) even though the visible bar is
// 2.5px — that's enough finger area without crowding the caption strip
// directly above (which has been lifted to bottom:32 to match).
//
// Vertical swipes inside the hit zone fall through to the parent
// PageView (we only listen on `onHorizontalDrag*`), so swipe-up to the
// next reel still works exactly the same.
// ============================================================================
class _ProgressBar extends StatefulWidget {
  final VideoPlayerController controller;
  const _ProgressBar({required this.controller});

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  /// True between drag-start and drag-end. Drives the bar fattening
  /// animation + the floating timestamp pill visibility.
  bool _dragging = false;

  /// 0..1 ratio of the user's last touch position along the bar.
  /// Used while [_dragging] is true so the bar follows the finger
  /// instead of the (lagging) controller position.
  double _dragRatio = 0.0;

  /// Whether the video was playing at drag-start, so we know whether to
  /// resume on drag-end or leave it paused (user hit pause manually
  /// before scrubbing — preserve that intent).
  bool _wasPlaying = false;

  Future<void> _seekToRatio(double ratio) async {
    final dur = widget.controller.value.duration;
    if (dur.inMilliseconds <= 0) return;
    final target = Duration(
      milliseconds: (dur.inMilliseconds * ratio).round(),
    );
    await widget.controller.seekTo(target);
  }

  /// Tap-only entry point — used when the user just taps the bar to
  /// jump to a position without dragging. No pause / resume; the video
  /// keeps playing from the new spot.
  Future<void> _onTap(double localX, double width) async {
    final ratio = (localX / width).clamp(0.0, 1.0);
    HapticUtils.tap();
    await _seekToRatio(ratio);
  }

  Future<void> _onDragStart(double localX, double width) async {
    final ratio = (localX / width).clamp(0.0, 1.0);
    HapticUtils.tap();
    _wasPlaying = widget.controller.value.isPlaying;
    if (_wasPlaying) {
      await widget.controller.pause();
    }
    if (!mounted) return;
    setState(() {
      _dragging = true;
      _dragRatio = ratio;
    });
    await _seekToRatio(ratio);
  }

  void _onDragUpdate(double localX, double width) {
    final ratio = (localX / width).clamp(0.0, 1.0);
    setState(() => _dragRatio = ratio);
    // Fire-and-forget seek on every update — video_player coalesces
    // back-to-back seeks, so even ~60fps drag updates stay smooth.
    _seekToRatio(ratio);
  }

  Future<void> _onDragEnd() async {
    if (!_dragging) return;
    setState(() => _dragging = false);
    if (_wasPlaying) {
      await widget.controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (_, __) {
        final v = widget.controller.value;
        final total = v.duration.inMilliseconds;
        final livePos = v.position.inMilliseconds;
        final progress = _dragging
            ? _dragRatio
            : (total <= 0 ? 0.0 : (livePos / total).clamp(0.0, 1.0));

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final fillWidth = width * progress;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _onTap(d.localPosition.dx, width),
              onHorizontalDragStart: (d) =>
                  _onDragStart(d.localPosition.dx, width),
              onHorizontalDragUpdate: (d) =>
                  _onDragUpdate(d.localPosition.dx, width),
              onHorizontalDragEnd: (_) => _onDragEnd(),
              onHorizontalDragCancel: _onDragEnd,
              child: SizedBox(
                // 28px transparent hit zone; visible bar is anchored to
                // the very bottom so it visually caps the navbar.
                height: 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // ── Track (full-width, dim) ──
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOut,
                        height: _dragging ? 6 : 2.5,
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    // ── Fill (white, sized to current progress) ──
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: AnimatedContainer(
                        // Slow easing on width while idle (smooth fill);
                        // near-instant while dragging (follows finger).
                        duration: Duration(
                          milliseconds: _dragging ? 0 : 180,
                        ),
                        curve: Curves.easeOut,
                        height: _dragging ? 6 : 2.5,
                        width: fillWidth,
                        color: Colors.white,
                      ),
                    ),
                    // ── Floating timestamp pill — only while dragging ──
                    if (_dragging)
                      Positioned(
                        // Center the pill on the finger, but clamp to
                        // the screen edges so it doesn't slide off when
                        // the user scrubs to 0% / 100%.
                        left: (fillWidth - 34).clamp(8.0, width - 76.0),
                        bottom: 14,
                        child: IgnorePointer(
                          child: _TimestampPill(
                            current: Duration(
                              milliseconds:
                                  (total * _dragRatio).round().clamp(0, total),
                            ),
                            total: v.duration,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// Floating timestamp pill — appears above the user's finger while
// scrubbing the progress bar, like Instagram / TikTok / YouTube Shorts.
// Pure presentational — `_ProgressBarState` owns visibility + position.
// ============================================================================
class _TimestampPill extends StatelessWidget {
  final Duration current;
  final Duration total;
  const _TimestampPill({required this.current, required this.total});

  static String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours >= 1) {
      final hh = d.inHours.toString();
      return '$hh:${mm.padLeft(2, '0')}:$ss';
    }
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${_fmt(current)} / ${_fmt(total)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ============================================================================
// Retry overlay — shown when a reel's video controller fails to init or
// takes longer than 10s. Replaces the infinite loading spinner so the
// user is never stuck. Tap → re-initialise the controller from scratch.
// ============================================================================
class _RetryOverlay extends StatelessWidget {
  final VoidCallback onRetry;
  const _RetryOverlay({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.white,
            size: 36,
          ),
          const SizedBox(height: 10),
          Text(
            'reelsImmersive.loadFailed'.tr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onRetry,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh_rounded,
                        color: Colors.black, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'reelsImmersive.tapToRetry'.tr,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Right rail — vertical column of action icons.
//
// Like state is owned by the parent [_ReelPage] now (so the double-tap on
// the video can spawn a floating heart AND flip the rail icon together).
// This widget is purely presentational for the like — it just renders
// `liked` + `likes` and forwards taps via [onLikeTap].
// ============================================================================
class _RightRail extends StatelessWidget {
  final ExpertPost post;
  final bool liked;
  final int likes;
  final VoidCallback onLikeTap;

  const _RightRail({
    required this.post,
    required this.liked,
    required this.likes,
    required this.onLikeTap,
  });

  void _openComments(BuildContext context) {
    HapticUtils.tap();
    CommentsSheet.show(
      context,
      postId: post.id,
      postOwnerExpertId: post.expertId,
      accent: SocialTokens.cyan,
    );
  }

  Future<void> _toggleSave() async {
    // Same toggle-state nuance as mute — `pick` reads as "flipped".
    HapticUtils.pick();
    await Get.find<SavedController>().toggle(post);
  }

  /// Pop the native OS share sheet with a short blurb + a deep-link URL
  /// pointing at this post. The URL won't resolve to the app yet — that
  /// arrives with the deep-link routing in the next Sharing milestone —
  /// but it's already shape-correct so existing shares stay valid once
  /// the routing lands.
  Future<void> _sharePost(BuildContext context) async {
    HapticUtils.tap();
    final title = (post.title ?? '').trim();
    final author = post.authorName.trim().isEmpty
        ? 'reelsImmersive.shareAuthorFallback'.tr
        : post.authorName.trim();
    final body = title.isEmpty
        ? 'reelsImmersive.shareBodyNoTitle'.trParams({'author': author})
        : 'reelsImmersive.shareBodyWithTitle'
            .trParams({'title': title, 'author': author});
    final url = 'https://unmu.app/p/${post.id}';
    // share_plus needs a non-empty box on iPad where the share sheet
    // anchors to a popover — pass the rendered button bounds for that.
    final box = context.findRenderObject() as RenderBox?;
    // Log the tap before the share sheet appears — fire-and-forget,
    // so a slow network won't delay the share dialog.
    unawaited(EventsService.logShare(post.id));
    await Share.share(
      '$body\n\n$url',
      subject: title.isEmpty ? 'reelsImmersive.shareSubject'.tr : title,
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Like — animated heart with particle burst ──
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedLikeHeart(
              liked: liked,
              size: 30,
              onTap: onLikeTap,
            ),
            Text(
              _format(likes),
              style: TextStyle(
                color: liked ? const Color(0xFFFF3B5C) : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // ── Comment — tap opens the sheet, long-press pops up the
        // emoji-reaction pill (👏 😲 🔥 😍). Drag onto an emoji and
        // release → it's posted as a comment.
        _CommentReactionButton(
          post: post,
          label: _format(post.comments),
          color: Colors.white,
          onTap: () => _openComments(context),
        ),
        const SizedBox(height: 14),
        // ── Save — bouncy bookmark ──
        Obx(() {
          final saved =
              Get.find<SavedController>().isSaved(post.id) || post.saved;
          return _RailButton(
            icon: saved
                ? Icons.bookmark_rounded
                : Icons.bookmark_outline_rounded,
            label: saved
                ? 'reelsImmersive.saved'.tr
                : 'reelsImmersive.save'.tr,
            color: saved ? SocialTokens.cyan : Colors.white,
            onTap: _toggleSave,
          );
        }),
        const SizedBox(height: 14),
        // ── Share — iOS share-box, more universally recognized than the
        // old paper airplane. Pops the native OS share sheet via
        // `share_plus` (UIActivityViewController on iOS,
        // Intent.ACTION_SEND on Android). ──
        _RailButton(
          icon: Icons.ios_share_rounded,
          label: 'reelsImmersive.share'.tr,
          color: Colors.white,
          onTap: () => _sharePost(context),
        ),
      ],
    );
  }

  static String _format(int n) {
    if (n < 1000) return '$n';
    if (n < 1_000_000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1_000_000).toStringAsFixed(1)}M';
  }
}

class _RailButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bump;

  @override
  void initState() {
    super.initState();
    _bump = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  void _handleTap() {
    _bump
      ..value = 0
      ..forward();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _bump,
            builder: (_, child) {
              // Bouncy press: scale dips slightly on touch then springs
              // up past 1 before settling — Instagram-feel.
              final t = _bump.value;
              final scale = t == 0
                  ? 1.0
                  : 1.0 + math.sin(t * math.pi) * 0.18;
              return Transform.scale(scale: scale, child: child);
            },
            // Modernized — no circular background, just the icon with a
            // strong drop shadow so it stays legible against any video
            // frame. Matches the Instagram / TikTok rail aesthetic.
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                widget.icon,
                color: widget.color,
                size: 30,
                shadows: const [
                  Shadow(
                    color: Colors.black87,
                    blurRadius: 14,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.label,
            style: TextStyle(
              color: widget.color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              shadows: const [
                Shadow(color: Colors.black54, blurRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Bottom-left meta — author, caption, tickers, REEL pill.
// ============================================================================
class _BottomMeta extends StatefulWidget {
  final ExpertPost post;
  const _BottomMeta({required this.post});

  @override
  State<_BottomMeta> createState() => _BottomMetaState();
}

class _BottomMetaState extends State<_BottomMeta> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.45),
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'reelsImmersive.reelPill'.tr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Author row — small avatar circle + name, Instagram-style.
          // The avatar uses the expert's first initial on a cyan-gradient
          // disc so it matches the avatar treatment everywhere else in
          // the app.
          // Avatar + name → tap opens the expert's profile so the
          // reel-watcher can see their bio and full post catalog.
          GestureDetector(
            onTap: () =>
                ExpertProfileScreen.openForExpertId(context, p.expertId),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AuthorAvatar(name: p.authorName, size: 32),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    p.authorName.isEmpty
                        ? 'reelsImmersive.expert'.tr
                        : p.authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                      letterSpacing: -0.2,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (p.title != null && p.title!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              p.title!,
              maxLines: _expanded ? 6 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                height: 1.35,
                shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
              ),
            ),
          ],
          if (p.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                p.body,
                maxLines: _expanded ? 8 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 13,
                  height: 1.35,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 6),
                  ],
                ),
              ),
            ),
          ],
          if (p.tickers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: p.tickers
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: SocialTokens.cyan.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: SocialTokens.cyan.withValues(alpha: 0.55),
                          ),
                        ),
                        child: Text(
                          '\$$t',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 10.5,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// Empty state — shown inside the immersive view if zero reels available.
// ============================================================================
class _EmptyReelsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SocialTokens.cyan.withValues(alpha: 0.15),
                  border: Border.all(
                      color: SocialTokens.cyan.withValues(alpha: 0.4)),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.movie_creation_outlined,
                    size: 32, color: SocialTokens.cyan),
              ),
              const SizedBox(height: 16),
              Text(
                'reelsImmersive.emptyTitle'.tr,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'reelsImmersive.emptyBody'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// _AuthorAvatar — small initials disc shown next to the author name in the
// bottom-left meta panel. Same visual language as the user avatar in the
// Feed app bar — cyan gradient, dark navy initial.
// ============================================================================
class _AuthorAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _AuthorAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final letters = _initials(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            SocialTokens.cyan,
            SocialTokens.cyan.withValues(alpha: 0.55),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 1.4,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letters,
        style: TextStyle(
          color: const Color(0xFF0A1628),
          fontWeight: FontWeight.w900,
          fontSize: size * 0.42,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

// ============================================================================
// Floating heart — Instagram-style pop-up shown at the spot the user just
// double-tapped.
//
// Choreography (~900ms):
//   * 0–225ms  : scale 0 → 1.6, fade in
//   * 225–500ms: dwell at scale ~1.4 with full opacity
//   * 500–900ms: shrink slightly, drift up ~40px, fade to 0
//
// Self-removes via [onDone] when the animation completes — the parent
// drops the entry from its list so the widget is detached cleanly.
// ============================================================================
class _FloatingHeart extends StatefulWidget {
  final Offset position;
  final VoidCallback onDone;
  /// When true (immersive mode), the heart is hidden alongside other
  /// overlays. Multiplies into the animation-driven opacity so a half-
  /// faded heart still hides cleanly.
  final bool dimmed;
  const _FloatingHeart({
    super.key,
    required this.position,
    required this.onDone,
    this.dimmed = false,
  });

  @override
  State<_FloatingHeart> createState() => _FloatingHeartState();
}

class _FloatingHeartState extends State<_FloatingHeart>
    with SingleTickerProviderStateMixin {
  static const _heartSize = 130.0;
  static const _driftPx = -40.0; // negative = upward

  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  late final Animation<double> _drift;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.6).chain(
          CurveTween(curve: Curves.easeOutBack),
        ),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.6, end: 1.4),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.4, end: 1.0),
        weight: 45,
      ),
    ]).animate(_ctrl);
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 45),
    ]).animate(_ctrl);
    _drift = Tween<double>(begin: 0, end: _driftPx)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        // When immersive mode kicks in we squash to zero so the heart
        // disappears alongside the rest of the chrome.
        final immersiveMul = widget.dimmed ? 0.0 : 1.0;
        return Positioned(
          left: widget.position.dx - _heartSize / 2,
          top: widget.position.dy - _heartSize / 2 + _drift.value,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              opacity: (_opacity.value.clamp(0.0, 1.0)) * immersiveMul,
              child: Transform.scale(
                scale: _scale.value,
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFFFF3B5C),
                  size: _heartSize,
                  shadows: [
                    Shadow(color: Colors.black54, blurRadius: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// _CommentReactionButton — long-press to react with a quick emoji.
//
// UX:
//   * Tap            → opens the comments sheet (existing behaviour).
//   * Long-press     → a small pill appears above the icon with four
//                      preset emojis: 👏 😲 🔥 😍.
//   * Drag finger    → emoji under the finger highlights (scales up).
//   * Release on emoji → that emoji is posted as a comment on the post.
//   * Release elsewhere or cancel → picker closes, nothing posted.
//
// Implementation notes:
//   * Uses `Stack(clipBehavior: Clip.none)` so the pill can render above
//     the button's bounds without being clipped.
//   * Hit-testing is done in local coordinates against pre-computed
//     emoji slot positions (no GlobalKey gymnastics, deterministic).
//   * Each hover transition fires a `pick` haptic so the user feels
//     the snap as they slide across.
// ============================================================================
class _CommentReactionButton extends StatefulWidget {
  final ExpertPost post;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CommentReactionButton({
    required this.post,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_CommentReactionButton> createState() => _CommentReactionButtonState();
}

class _CommentReactionButtonState extends State<_CommentReactionButton>
    with SingleTickerProviderStateMixin {
  // Quick-reaction set requested by the brief.
  static const _emojis = ['👏', '😲', '🔥', '😍'];

  // Geometry for the picker. The picker is anchored to the right edge
  // of the button so it never overflows past the right side of the
  // screen (the rail is on the right). It hangs left.
  static const double _pickerWidth = 240;
  static const double _pickerHeight = 56;
  static const double _emojiSlotWidth = _pickerWidth / 4; // 60
  /// Vertical gap between the picker's bottom edge and the button's top.
  static const double _verticalGap = 14;

  bool _open = false;
  int? _hovered; // index of emoji under the finger, or null
  bool _busy = false;

  late final AnimationController _appear;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _appear.dispose();
    super.dispose();
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (_busy) return;
    HapticUtils.tap();
    setState(() {
      _open = true;
      _hovered = null;
    });
    _appear
      ..value = 0
      ..forward();
  }

  /// Map the finger's local position (relative to the button) to the
  /// hovered emoji index, or null if the finger isn't currently over
  /// the picker pill.
  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_open) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final buttonW = box.size.width;
    final buttonH = box.size.height;

    // Picker pill rectangle in local coords:
    //   right edge   = buttonW (anchored to button right)
    //   left edge    = buttonW - _pickerWidth
    //   bottom edge  = -_verticalGap                  (above the button)
    //   top edge     = -_verticalGap - _pickerHeight
    final pickerLeft = buttonW - _pickerWidth;
    final pickerRight = buttonW;
    final pickerTop = -_verticalGap - _pickerHeight;
    final pickerBottom = -_verticalGap;

    final p = details.localPosition;

    // Add a tiny grace zone around the pill (8px in each direction) so
    // a slightly off-target finger still registers a hover.
    const grace = 8.0;
    final inPicker = p.dx >= pickerLeft - grace &&
        p.dx <= pickerRight + grace &&
        p.dy >= pickerTop - grace &&
        p.dy <= pickerBottom + grace;

    int? newHovered;
    if (inPicker) {
      final relX = (p.dx - pickerLeft).clamp(0.0, _pickerWidth - 0.001);
      newHovered = (relX / _emojiSlotWidth).floor().clamp(0, _emojis.length - 1);
    }

    if (newHovered != _hovered) {
      // Snap haptic on each new emoji, like Instagram.
      if (newHovered != null) HapticUtils.pick();
      setState(() => _hovered = newHovered);
    }

    // Suppress the unused-variable warning for buttonH while keeping
    // the calculation explicit for future tweaks.
    assert(buttonH > 0);
  }

  Future<void> _onLongPressEnd(LongPressEndDetails details) async {
    final selected = _hovered;
    setState(() {
      _open = false;
      _hovered = null;
    });
    _appear.reverse();
    if (selected == null) return;
    await _postEmoji(_emojis[selected]);
  }

  void _onLongPressCancel() {
    setState(() {
      _open = false;
      _hovered = null;
    });
    _appear.reverse();
  }

  Future<void> _postEmoji(String emoji) async {
    setState(() => _busy = true);
    HapticUtils.confirm();
    final res =
        await PostInteractionService.addComment(widget.post.id, emoji);
    if (!mounted) return;
    setState(() => _busy = false);
    final messenger = ScaffoldMessenger.of(context);
    if (res.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(res.error!)));
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Text('reelsImmersive.reactedWith'.trParams({'emoji': emoji})),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: _onLongPressCancel,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // The visible button — same layout as _RailButton so it sits
          // flush in the right rail column without realigning.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: widget.color,
                  size: 30,
                  shadows: const [
                    Shadow(
                      color: Colors.black87,
                      blurRadius: 14,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.color,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 4),
                  ],
                ),
              ),
            ],
          ),

          // The picker pill — only laid out when open. Anchored to the
          // button's right edge so it hangs leftward and never goes off
          // the right side of the screen.
          if (_open)
            Positioned(
              right: 0,
              bottom: 56 + _verticalGap, // button height + gap
              child: AnimatedBuilder(
                animation: _appear,
                builder: (_, child) {
                  return Opacity(
                    opacity: _appear.value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - _appear.value) * 12),
                      child: Transform.scale(
                        scale: 0.9 + 0.1 * _appear.value,
                        alignment: Alignment.bottomRight,
                        child: child,
                      ),
                    ),
                  );
                },
                child: _ReactionPickerPill(
                  emojis: _emojis,
                  hovered: _hovered,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReactionPickerPill extends StatelessWidget {
  final List<String> emojis;
  final int? hovered;

  const _ReactionPickerPill({required this.emojis, required this.hovered});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _CommentReactionButtonState._pickerWidth,
      height: _CommentReactionButtonState._pickerHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1628).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(emojis.length, (i) {
          final isHovered = hovered == i;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: 44,
            height: 44,
            alignment: Alignment.center,
            transformAlignment: Alignment.center,
            transform: isHovered
                ? (Matrix4.identity()..scale(1.45))
                : Matrix4.identity(),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isHovered
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.transparent,
            ),
            child: Text(
              emojis[i],
              style: const TextStyle(fontSize: 26),
            ),
          );
        }),
      ),
    );
  }
}

