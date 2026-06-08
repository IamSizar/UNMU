import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../directional_icon.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '../../services/video_resume_service.dart';
import '../common/app_network_image.dart';

/// Shared, self-contained video player used by every "watch a single
/// video" surface — VideoPlayerScreen (long-form), post viewer, expert
/// profile, community detail, etc. Reels keep their own bespoke viewer.
///
/// Gestures (TikTok / Instagram conventions blended for long video):
///
///   * Tap            → toggle play/pause + show/hide controls
///   * Double-tap R   → +5 s seek, ripple animation
///   * Double-tap L   → -5 s seek, ripple animation
///   * Long-press     → 2× speed (anywhere); release returns to 1×
///   * Rotate icon    → enter landscape fullscreen (immersive system UI)
///   * Pull-down in
///     landscape      → exit landscape, return to portrait
///   * Lock icon (in
///     landscape)     → freeze all gestures so an accidental touch
///                      doesn't pause / seek
///
/// Other behaviors:
///
///   * Controls fade out after [_kControlsHideAfter] of inactivity;
///     any tap brings them back.
///   * Resume — saved position is loaded on init; further positions
///     are checkpointed every [_kResumeCheckpointEvery]. End-of-video
///     clears the saved position so a fresh play starts from 0.
///   * Buffering — spinner appears after [_kBufferingShowDelay] of
///     stall, hides as soon as playback advances again.
///   * Errors — if the controller fails to initialize (bad URL,
///     network down, format unsupported), a clear retry card replaces
///     the video surface.
///   * Mute — sticky across the app via a static field. The user
///     muting one video keeps every other muted on first view too,
///     matching Instagram / TikTok feed convention.
class UnmuVideoPlayer extends StatefulWidget {
  /// Network URL of the video. Pre-signed S3 URLs work as-is.
  final String url;

  /// Optional cover image to show before [VideoPlayerController]
  /// finishes initializing (avoids a black frame on slow networks).
  final String? coverUrl;

  /// Quality renditions for the settings-gear quality picker. Maps a label
  /// (e.g. "720p", "480p") to a playable URL. "Auto" is implicit and always
  /// maps to [url] (the original). When empty, the gear icon is hidden and
  /// the player behaves exactly as before.
  final Map<String, String> qualityVariants;

  /// Whether playback should start automatically on init. Single-video
  /// viewers usually want true; admin / preview surfaces want false.
  final bool autoPlay;

  /// Whether playback loops at the end. Reels want true (short clip on
  /// repeat is the format); long-form videos want false (a 30-minute
  /// video looping forever would be annoying).
  final bool loop;

  /// Whether to show the chrome (top back button + bottom controls).
  /// false for embedded previews that don't own the full screen.
  final bool showChrome;

  /// Title rendered in the top bar in landscape mode (helps users
  /// remember which video they're watching). Optional.
  final String? title;

  /// Optional fixed aspect ratio. When null, the controller's reported
  /// aspect ratio is used (after initialization).
  final double? aspectRatio;

  /// Called when the user taps the back arrow. Defaults to Navigator.pop.
  final VoidCallback? onClose;

  /// Optional caller-supplied content rendered inside the bottom chrome,
  /// just ABOVE the scrubber. Used by ReelPlayerScreen to inject the
  /// author + title strip without polluting the generic widget with
  /// reel-specific fields. Fades in/out with the rest of the chrome.
  final Widget? bottomOverlay;

  /// The post's recorded duration in seconds, used to detect a TRUNCATED
  /// transcoded variant (the backend worker has emitted renditions far
  /// shorter than the source). When a variant comes back materially shorter
  /// than this, the player falls back to the original [url] so it never
  /// silently plays a cut-off clip. Null disables the check (a variant is
  /// then only rejected if it fails to initialise at all).
  final int? expectedDurationSeconds;

  const UnmuVideoPlayer({
    super.key,
    required this.url,
    this.coverUrl,
    this.autoPlay = true,
    this.loop = false,
    this.showChrome = true,
    this.title,
    this.aspectRatio,
    this.onClose,
    this.bottomOverlay,
    this.qualityVariants = const {},
    this.expectedDurationSeconds,
  });

  @override
  State<UnmuVideoPlayer> createState() => _UnmuVideoPlayerState();
}

// Tuning knobs — kept private to this file so they're impossible to
// drift between callers.
const Duration _kSeekStep = Duration(seconds: 5);
const Duration _kControlsHideAfter = Duration(seconds: 3);
const Duration _kResumeCheckpointEvery = Duration(seconds: 5);
const Duration _kBufferingShowDelay = Duration(milliseconds: 500);
const Duration _kRippleAnimDuration = Duration(milliseconds: 650);

class _UnmuVideoPlayerState extends State<UnmuVideoPlayer>
    with TickerProviderStateMixin {
  // Mute is sticky across every instance / route. Last user action
  // wins; defaults to UNMUTED on first launch (videos open with sound).
  static bool _appWideMuted = false;

  VideoPlayerController? _video;
  bool _initializing = true;
  bool _hasError = false;
  String? _errorMsg;

  // Chrome visibility — controls fade in/out together via a single
  // AnimationController so the timing is consistent across overlays.
  late final AnimationController _chromeFade;
  Timer? _hideTimer;
  bool get _chromeVisible => _chromeFade.value > 0.01;

  // 2× speed mode: true between onLongPressStart and onLongPressEnd.
  bool _speedMode = false;
  double _speedBefore = 1.0;

  // Landscape + lock — both default off in portrait mode.
  bool _isLandscape = false;
  bool _locked = false;

  // Buffering — true when the controller stalls for > 500 ms.
  bool _buffering = false;
  // Last-seen play/pause flag, so a flip can trigger an immediate rebuild.
  bool? _lastIsPlaying;
  Duration? _lastReportedPosition;
  DateTime? _lastPositionTime;
  // Last whole second we rebuilt the chrome at. Kept SEPARATE from
  // _lastReportedPosition (which the stall detector rewrites every frame) so
  // the time label + scrubber actually advance once per second during
  // playback instead of freezing until the next play/pause flip.
  int? _lastRenderedSec;

  // Seek ripples — keyed by an incrementing id so multiple in-flight
  // ripples don't collide on the screen.
  final List<_SeekRipple> _ripples = [];
  int _rippleIdSeq = 0;

  // Resume checkpoint timer — saves position every N seconds.
  Timer? _resumeSaveTimer;

  // Quality picker (mig 0046). "Auto" = widget.url (the original); other
  // labels come from widget.qualityVariants. _activeUrl is whatever is
  // currently loaded; _switching guards the brief swap while we re-init the
  // controller at a chosen quality.
  static const _autoQuality = 'Auto';
  String _currentQuality = _autoQuality;
  late String _activeUrl;
  bool _switching = false;

  /// Quality to start playback at. The original master (widget.url, shown in
  /// the gear as "Auto") is high-bitrate and slow to begin over the network —
  /// the main reason a video "takes forever to load". When transcoded
  /// renditions exist we boot at 720p (crisp on a phone, a fraction of the
  /// master's bytes, so the first frame arrives far sooner); the viewer can
  /// still bump to Auto / 1080p from the quality gear. Falls back to the
  /// original whenever no renditions exist — i.e. the previous behaviour, so
  /// this is purely additive.
  static const List<String> _initialQualityPreference = ['720p', '480p', '1080p'];

  (String, String) _initialQuality() {
    final variants = widget.qualityVariants;
    for (final label in _initialQualityPreference) {
      final url = variants[label]?.trim();
      if (url != null && url.isNotEmpty) return (label, url);
    }
    return (_autoQuality, widget.url);
  }

  @override
  void initState() {
    super.initState();
    final initial = _initialQuality();
    _currentQuality = initial.$1;
    _activeUrl = initial.$2;
    _chromeFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
    _bootController();
  }

  Future<void> _bootController() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(_activeUrl));
    _video = controller;
    try {
      await controller.initialize();
      // Reject a truncated transcode before wiring anything up. This
      // backend's worker has emitted variants far shorter than the source
      // (e.g. a 6s "720p" of a 59s clip); playing one would silently cut
      // the video off. Throwing here drops into the catch block's
      // original-master fallback below. Only applies to a variant boot
      // (_activeUrl != widget.url) and only when we know the expected length.
      final expected = widget.expectedDurationSeconds ?? 0;
      if (_activeUrl != widget.url &&
          expected > 0 &&
          controller.value.duration.inSeconds < expected - 2) {
        throw StateError(
          'transcoded variant is ${controller.value.duration.inSeconds}s, '
          'expected ~${expected}s — treating as truncated',
        );
      }
      controller.addListener(_onTick);
      await controller.setVolume(_appWideMuted ? 0.0 : 1.0);
      await controller.setLooping(widget.loop);
      final saved = await VideoResumeService.loadPosition(widget.url);
      if (saved != null &&
          saved < (controller.value.duration - const Duration(seconds: 2))) {
        await controller.seekTo(saved);
      }
      if (widget.autoPlay) {
        await controller.play();
      }
      if (!mounted) return;
      setState(() => _initializing = false);
      _scheduleHide();
      _startResumeCheckpointer();
    } catch (e) {
      // The chosen quality failed to initialise. If we booted from a
      // transcoded variant (the fast-start default), fall back to the
      // original master ONCE before surfacing an error — a missing or
      // half-written rendition must never make a video unplayable when the
      // original would have worked. Bounded: the retry sets _activeUrl to
      // the original, so a second failure lands in the error branch below.
      if (_activeUrl != widget.url) {
        try {
          controller.removeListener(_onTick);
          await controller.dispose();
        } catch (_) {/* already dead */}
        if (!mounted) return;
        _activeUrl = widget.url;
        _currentQuality = _autoQuality;
        await _bootController();
        return;
      }
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _hasError = true;
        _errorMsg = e.toString();
      });
    }
  }

  void _onTick() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;

    final pos = c.value.position;
    final now = DateTime.now();

    // ── Buffering indicator ──
    // Trust the platform's own isBuffering flag first: it flips the instant a
    // seek needs to fetch data, so jumping to a far point reads as "loading"
    // right away instead of a frozen frame. The position-stall heuristic (no
    // progress for >500ms while playing) is a backstop for platforms that
    // under-report isBuffering.
    final stalled = c.value.isPlaying &&
        _lastReportedPosition != null &&
        _lastPositionTime != null &&
        pos == _lastReportedPosition &&
        now.difference(_lastPositionTime!) > _kBufferingShowDelay;
    final wantBuffering = c.value.isBuffering || stalled;
    if (wantBuffering != _buffering && mounted) {
      setState(() => _buffering = wantBuffering);
    }
    // Advance the stall-heuristic tracking whenever the position moves.
    if (_lastReportedPosition == null || pos != _lastReportedPosition) {
      _lastReportedPosition = pos;
      _lastPositionTime = now;
    }

    if (c.value.duration > Duration.zero &&
        pos >= c.value.duration - const Duration(milliseconds: 250)) {
      VideoResumeService.clearPosition(widget.url);
    }

    // Rebuild whenever play/pause flips (end-of-video, external pause, …)
    // so the center button + its icon update immediately instead of
    // waiting for the next second tick.
    if (_lastIsPlaying != c.value.isPlaying) {
      _lastIsPlaying = c.value.isPlaying;
      if (mounted) setState(() {});
      // A flip to paused means the auto-hide should stand down so the
      // resume button stays put; a flip to playing restarts the countdown.
      _scheduleHide();
    }

    // Tick the time label + scrubber forward once per second during normal
    // playback. This must NOT key off _lastReportedPosition: the buffering
    // branch above rewrites that to the current position on every advancing
    // frame, so the comparison was always equal and the UI never refreshed
    // (the "timer frozen at 00:13 while the picture keeps playing" bug).
    final sec = pos.inSeconds;
    if (_lastRenderedSec != sec && mounted) {
      _lastRenderedSec = sec;
      setState(() {});
    }
  }

  void _startResumeCheckpointer() {
    _resumeSaveTimer?.cancel();
    _resumeSaveTimer = Timer.periodic(_kResumeCheckpointEvery, (_) async {
      final c = _video;
      if (c == null || !c.value.isInitialized) return;
      if (!c.value.isPlaying) return;
      await VideoResumeService.savePosition(
        url: widget.url,
        position: c.value.position,
        total: c.value.duration,
      );
    });
  }

  @override
  void dispose() {
    final c = _video;
    if (c != null && c.value.isInitialized) {
      VideoResumeService.savePosition(
        url: widget.url,
        position: c.value.position,
        total: c.value.duration,
      );
    }
    _resumeSaveTimer?.cancel();
    _hideTimer?.cancel();
    _chromeFade.dispose();
    _video?.removeListener(_onTick);
    _video?.dispose();
    _setOrientationPortrait();
    super.dispose();
  }

  // ─── Gesture handlers ──────────────────────────────────────────────

  void _showChrome() {
    if (!_chromeVisible) _chromeFade.forward();
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    // While paused, keep the controls (and the center play button) on
    // screen — auto-hiding them would leave the user staring at a frozen
    // frame with no obvious way to resume.
    final c = _video;
    if (c != null && c.value.isInitialized && !c.value.isPlaying) return;
    _hideTimer = Timer(_kControlsHideAfter, () {
      if (!mounted) return;
      _chromeFade.reverse();
    });
  }

  /// A tap on the video surface no longer pauses playback — that was too
  /// easy to trigger by accident while watching. Now a tap just toggles the
  /// on-screen controls; play/pause lives on the dedicated center button
  /// ([_togglePlayPause]).
  void _handleTap() {
    if (_locked) {
      _showChrome();
      return;
    }
    if (_chromeVisible) {
      _hideTimer?.cancel();
      _chromeFade.reverse();
    } else {
      _showChrome();
    }
  }

  /// Deliberate play/pause via the big center button.
  void _togglePlayPause() {
    if (_locked) return;
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    HapticFeedback.lightImpact();
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    if (mounted) setState(() {}); // refresh the play/pause icon immediately
    _showChrome();
  }

  Future<void> _handleDoubleTapDown(TapDownDetails d) async {
    if (_locked) {
      _showChrome();
      return;
    }
    final c = _video;
    if (c == null || !c.value.isInitialized) return;

    final width = context.size?.width ?? MediaQuery.of(context).size.width;
    final forward = d.localPosition.dx >= width / 2;
    HapticFeedback.lightImpact();

    final id = ++_rippleIdSeq;
    setState(() {
      _ripples.add(
        _SeekRipple(id: id, position: d.localPosition, forward: forward),
      );
    });

    final pos = c.value.position;
    final dur = c.value.duration;
    final raw = forward ? pos + _kSeekStep : pos - _kSeekStep;
    final target = raw < Duration.zero
        ? Duration.zero
        : (raw > dur ? dur : raw);
    await c.seekTo(target);
    _showChrome();
  }

  void _removeRipple(int id) {
    if (!mounted) return;
    setState(() => _ripples.removeWhere((r) => r.id == id));
  }

  void _handleLongPressStart(LongPressStartDetails _) {
    if (_locked) return;
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    HapticFeedback.selectionClick();
    _speedBefore = c.value.playbackSpeed;
    c.setPlaybackSpeed(2.0);
    setState(() => _speedMode = true);
  }

  void _handleLongPressEnd(LongPressEndDetails _) {
    if (!_speedMode) return;
    final c = _video;
    if (c != null && c.value.isInitialized) {
      c.setPlaybackSpeed(_speedBefore == 0 ? 1.0 : _speedBefore);
    }
    HapticFeedback.lightImpact();
    setState(() => _speedMode = false);
  }

  double _verticalDragAcc = 0;
  void _handleVerticalDragStart(DragStartDetails _) {
    _verticalDragAcc = 0;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails d) {
    if (!_isLandscape || _locked) return;
    if (d.delta.dy > 0) _verticalDragAcc += d.delta.dy;
  }

  void _handleVerticalDragEnd(DragEndDetails _) {
    if (!_isLandscape || _locked) return;
    if (_verticalDragAcc > 80) {
      _exitLandscape();
    }
    _verticalDragAcc = 0;
  }

  // ─── Orientation + mute toggles ───────────────────────────────────

  Future<void> _enterLandscape() async {
    HapticFeedback.mediumImpact();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (!mounted) return;
    setState(() => _isLandscape = true);
    _showChrome();
  }

  Future<void> _exitLandscape() async {
    HapticFeedback.mediumImpact();
    await _setOrientationPortrait();
    if (!mounted) return;
    setState(() {
      _isLandscape = false;
      _locked = false;
    });
    _showChrome();
  }

  Future<void> _setOrientationPortrait() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  void _toggleMute() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    HapticFeedback.selectionClick();
    setState(() => _appWideMuted = !_appWideMuted);
    c.setVolume(_appWideMuted ? 0.0 : 1.0);
    _showChrome();
  }

  void _toggleLock() {
    HapticFeedback.mediumImpact();
    setState(() => _locked = !_locked);
    _showChrome();
  }

  // ─── Quality picker ────────────────────────────────────────────────

  /// Ordered list shown in the sheet: Auto first, then renditions from
  /// highest to lowest by their numeric prefix (1080p, 720p, 480p…).
  List<String> _qualityLabels() {
    final keys = widget.qualityVariants.keys.toList();
    int rank(String s) =>
        int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    keys.sort((a, b) => rank(b).compareTo(rank(a)));
    return [_autoQuality, ...keys];
  }

  void _openQualitySheet() {
    _hideTimer?.cancel(); // don't let controls fade while the sheet is up
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF14181F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Icon(Icons.high_quality_rounded,
                        color: Colors.cyanAccent, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'videoPlayer.quality'.tr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              for (final label in _qualityLabels())
                ListTile(
                  dense: true,
                  leading: Icon(
                    label == _currentQuality
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: label == _currentQuality
                        ? Colors.cyanAccent
                        : Colors.white38,
                  ),
                  title: Text(
                    label == _autoQuality ? 'videoPlayer.auto'.tr : label,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _switchQuality(label);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ).whenComplete(_showChrome);
  }

  /// Swaps the playing source to the chosen quality, preserving position +
  /// play/mute state. Re-inits a fresh controller (video_player can't
  /// retarget an existing one) and only swaps it in once the new source is
  /// ready, so playback never visibly breaks. On failure we keep the old
  /// controller and revert the label.
  Future<void> _switchQuality(String label) async {
    if (label == _currentQuality) return;
    final url =
        label == _autoQuality ? widget.url : widget.qualityVariants[label];
    if (url == null || url.isEmpty) return;

    final old = _video;
    final pos = old?.value.position ?? Duration.zero;
    final wasPlaying = old?.value.isPlaying ?? widget.autoPlay;
    final prevQuality = _currentQuality;
    setState(() {
      _switching = true;
      _currentQuality = label;
    });

    final next = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await next.initialize();
      await next.setVolume(_appWideMuted ? 0.0 : 1.0);
      await next.setLooping(widget.loop);
      if (pos < (next.value.duration - const Duration(milliseconds: 500))) {
        await next.seekTo(pos);
      }
      if (wasPlaying) await next.play();
    } catch (_) {
      await next.dispose();
      if (mounted) {
        setState(() {
          _switching = false;
          _currentQuality = prevQuality; // keep the source that's still playing
        });
      }
      return;
    }

    old?.removeListener(_onTick);
    next.addListener(_onTick);
    if (!mounted) {
      await next.dispose();
      return;
    }
    setState(() {
      _video = next;
      _activeUrl = url;
      _switching = false;
      _lastIsPlaying = next.value.isPlaying;
    });
    await old?.dispose();
    HapticFeedback.selectionClick();
    _showChrome();
  }

  Future<void> _retry() async {
    setState(() {
      _initializing = true;
      _hasError = false;
      _errorMsg = null;
    });
    await _video?.dispose();
    _video = null;
    await _bootController();
  }

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_hasError) return _buildError();

    final c = _video;
    final ready = c != null && c.value.isInitialized;
    final aspect =
        widget.aspectRatio ?? (ready ? c.value.aspectRatio : 16 / 9);

    final stack = Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black),
        if (ready)
          Center(
            child: AspectRatio(
              aspectRatio: aspect,
              child: VideoPlayer(c),
            ),
          )
        else if (widget.coverUrl != null && widget.coverUrl!.isNotEmpty)
          Positioned.fill(
            child: AppNetworkImage(widget.coverUrl!, fit: BoxFit.cover),
          ),

        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            onDoubleTapDown: _handleDoubleTapDown,
            onDoubleTap: () {},
            onLongPressStart: _handleLongPressStart,
            onLongPressEnd: _handleLongPressEnd,
            onVerticalDragStart: _handleVerticalDragStart,
            onVerticalDragUpdate: _handleVerticalDragUpdate,
            onVerticalDragEnd: _handleVerticalDragEnd,
          ),
        ),

        for (final r in _ripples)
          _SeekRippleOverlay(
            key: ValueKey(r.id),
            ripple: r,
            duration: _kRippleAnimDuration,
            onDone: () => _removeRipple(r.id),
          ),

        if (_speedMode)
          const Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(child: _SpeedBadge()),
          ),

        if ((_buffering || _switching) && !_speedMode)
          const Center(
            child: SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ),

        if (_initializing)
          const Center(
            child: SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ),

        if (widget.showChrome) ...[
          _TopChrome(
            fade: _chromeFade,
            title: widget.title,
            isLandscape: _isLandscape,
            locked: _locked,
            onBack: widget.onClose ?? () => Navigator.maybePop(context),
            onToggleLock: _toggleLock,
          ),
          _BottomChrome(
            fade: _chromeFade,
            controller: _video,
            ready: ready,
            muted: _appWideMuted,
            isLandscape: _isLandscape,
            locked: _locked,
            bottomOverlay: widget.bottomOverlay,
            onToggleMute: _toggleMute,
            onToggleLandscape: () =>
                _isLandscape ? _exitLandscape() : _enterLandscape(),
            onSeekToRatio: _seekToRatio,
            // While the user is dragging the scrubber, freeze the auto-hide
            // so the bar can't fade out from under their finger; resume the
            // normal hide countdown when they let go.
            onScrubStart: () {
              _hideTimer?.cancel();
              if (!_chromeVisible) _chromeFade.forward();
            },
            onScrubEnd: _showChrome,
            onTogglePlayPause: _togglePlayPause,
            showQuality: widget.qualityVariants.isNotEmpty,
            onTapQuality: _openQualitySheet,
          ),
        ],
      ],
    );

    return ColoredBox(
      color: Colors.black,
      child: _isLandscape ? stack : SafeArea(top: false, child: stack),
    );
  }

  Future<void> _seekToRatio(double r) async {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    final target = Duration(
      milliseconds: (c.value.duration.inMilliseconds * r.clamp(0.0, 1.0))
          .round(),
    );
    await c.seekTo(target);
    _showChrome();
  }

  Widget _buildError() {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white70, size: 56),
              const SizedBox(height: 16),
              Text(
                'videoPlayer.loadFailed'.tr,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              if (_errorMsg != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMsg!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text('videoPlayer.tryAgain'.tr),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: widget.onClose ?? () => Navigator.maybePop(context),
                child: Text('videoPlayer.close'.tr,
                    style: const TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Data + child widgets ────────────────────────────────────────────

class _SeekRipple {
  final int id;
  final Offset position;
  final bool forward;
  _SeekRipple(
      {required this.id, required this.position, required this.forward});
}

class _SeekRippleOverlay extends StatefulWidget {
  final _SeekRipple ripple;
  final Duration duration;
  final VoidCallback onDone;
  const _SeekRippleOverlay(
      {super.key,
      required this.ripple,
      required this.duration,
      required this.onDone});

  @override
  State<_SeekRippleOverlay> createState() => _SeekRippleOverlayState();
}

class _SeekRippleOverlayState extends State<_SeekRippleOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration)
      ..forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fwd = widget.ripple.forward;
    final color = Colors.white.withValues(alpha: 0.18);
    final iconColor = Colors.white;

    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        final scale = math.min(1.0, t / 0.6);
        final alpha = t < 0.6 ? 0.85 : (1 - (t - 0.6) / 0.4) * 0.85;

        return Positioned.fill(
          child: IgnorePointer(
            child: Stack(
              children: [
                Positioned(
                  left: fwd ? null : 0,
                  right: fwd ? 0 : null,
                  top: 0,
                  bottom: 0,
                  width: MediaQuery.of(context).size.width * 0.45,
                  child: Opacity(
                    opacity: alpha.clamp(0.0, 1.0),
                    child: ClipPath(
                      clipper:
                          fwd ? _RightHalfDisc(scale) : _LeftHalfDisc(scale),
                      child: ColoredBox(color: color),
                    ),
                  ),
                ),
                Align(
                  alignment:
                      fwd ? const Alignment(0.5, 0) : const Alignment(-0.5, 0),
                  child: Opacity(
                    opacity: alpha.clamp(0.0, 1.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          fwd
                              ? Icons.fast_forward_rounded
                              : Icons.fast_rewind_rounded,
                          color: iconColor,
                          size: 56,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          fwd ? '+5s' : '-5s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LeftHalfDisc extends CustomClipper<Path> {
  final double scale;
  _LeftHalfDisc(this.scale);
  @override
  Path getClip(Size size) {
    final p = Path();
    final w = size.width * scale;
    final h = size.height;
    p.moveTo(0, 0);
    p.lineTo(w * 0.7, 0);
    p.quadraticBezierTo(w, h / 2, w * 0.7, h);
    p.lineTo(0, h);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(covariant _LeftHalfDisc old) => old.scale != scale;
}

class _RightHalfDisc extends CustomClipper<Path> {
  final double scale;
  _RightHalfDisc(this.scale);
  @override
  Path getClip(Size size) {
    final p = Path();
    final w = size.width;
    final h = size.height;
    final s = w * scale;
    p.moveTo(w, 0);
    p.lineTo(w - s * 0.7, 0);
    p.quadraticBezierTo(w - s, h / 2, w - s * 0.7, h);
    p.lineTo(w, h);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(covariant _RightHalfDisc old) => old.scale != scale;
}

class _SpeedBadge extends StatefulWidget {
  const _SpeedBadge();
  @override
  State<_SpeedBadge> createState() => _SpeedBadgeState();
}

class _SpeedBadgeState extends State<_SpeedBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1.12).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fast_forward_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              'videoPlayer.speedBadge'.tr,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopChrome extends StatelessWidget {
  final Animation<double> fade;
  final String? title;
  final bool isLandscape;
  final bool locked;
  final VoidCallback onBack;
  final VoidCallback onToggleLock;
  const _TopChrome({
    required this.fade,
    required this.title,
    required this.isLandscape,
    required this.locked,
    required this.onBack,
    required this.onToggleLock,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: fade,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            8,
            isLandscape ? 12 : MediaQuery.of(context).padding.top + 4,
            8,
            8,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xA0000000), Color(0x00000000)],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const DirectionalIcon(Icons.arrow_back_rounded,
                    color: Colors.white),
                onPressed: locked ? null : onBack,
                tooltip: 'videoPlayer.back'.tr,
              ),
              const SizedBox(width: 4),
              if (title != null && title!.isNotEmpty)
                Expanded(
                  child: Text(
                    title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              if (isLandscape)
                IconButton(
                  icon: Icon(
                    locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                    color: locked ? Colors.cyanAccent : Colors.white,
                  ),
                  onPressed: onToggleLock,
                  tooltip: locked
                      ? 'videoPlayer.unlockControls'.tr
                      : 'videoPlayer.lockControls'.tr,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomChrome extends StatelessWidget {
  final Animation<double> fade;
  final VideoPlayerController? controller;
  final bool ready;
  final bool muted;
  final bool isLandscape;
  final bool locked;
  final Widget? bottomOverlay;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleLandscape;
  final Future<void> Function(double) onSeekToRatio;
  final VoidCallback onScrubStart;
  final VoidCallback onScrubEnd;
  final VoidCallback onTogglePlayPause;
  final bool showQuality;
  final VoidCallback onTapQuality;

  const _BottomChrome({
    required this.fade,
    required this.controller,
    required this.ready,
    required this.muted,
    required this.isLandscape,
    required this.locked,
    required this.bottomOverlay,
    required this.onToggleMute,
    required this.onToggleLandscape,
    required this.onSeekToRatio,
    required this.onScrubStart,
    required this.onScrubEnd,
    required this.onTogglePlayPause,
    required this.showQuality,
    required this.onTapQuality,
  });

  @override
  Widget build(BuildContext context) {
    final pos = ready ? controller!.value.position : Duration.zero;
    final dur = ready ? controller!.value.duration : Duration.zero;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: fade,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            isLandscape ? 16 : MediaQuery.of(context).padding.bottom + 8,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xCC000000), Color(0x00000000)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (bottomOverlay != null) ...[
                bottomOverlay!,
                const SizedBox(height: 8),
              ],
              if (ready && controller != null)
                _Scrubber(
                  controller: controller!,
                  enabled: !locked,
                  onSeek: onSeekToRatio,
                  onScrubStart: onScrubStart,
                  onScrubEnd: onScrubEnd,
                )
              else
                // Not-ready placeholder: an inert bar so the layout doesn't
                // jump when the controller finishes initializing.
                Row(
                  children: [
                    Text(_fmt(pos),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          activeTrackColor: Colors.cyanAccent,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12),
                        ),
                        child: const Slider(value: 0, onChanged: null),
                      ),
                    ),
                    Text(_fmt(dur),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12)),
                  ],
                ),
              Row(
                children: [
                  // Play/pause now lives here, next to the volume control
                  // (moved out of the center of the video).
                  IconButton(
                    icon: Icon(
                      (ready && controller!.value.isPlaying)
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
                    onPressed: (locked || !ready) ? null : onTogglePlayPause,
                    tooltip: (ready && controller!.value.isPlaying)
                        ? 'videoPlayer.pause'.tr
                        : 'videoPlayer.play'.tr,
                  ),
                  IconButton(
                    icon: Icon(
                      muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: Colors.white,
                    ),
                    onPressed: locked ? null : onToggleMute,
                    tooltip:
                        muted ? 'videoPlayer.unmute'.tr : 'videoPlayer.mute'.tr,
                  ),
                  const Spacer(),
                  if (showQuality)
                    IconButton(
                      icon: const Icon(Icons.settings_rounded,
                          color: Colors.white),
                      onPressed: locked ? null : onTapQuality,
                      tooltip: 'videoPlayer.quality'.tr,
                    ),
                  IconButton(
                    icon: Icon(
                      isLandscape
                          ? Icons.fullscreen_exit_rounded
                          : Icons.screen_rotation_rounded,
                      color: Colors.white,
                    ),
                    onPressed: locked ? null : onToggleLandscape,
                    tooltip: isLandscape
                        ? 'videoPlayer.exitLandscape'.tr
                        : 'videoPlayer.enterLandscape'.tr,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final hh = d.inHours;
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';
  }
}

/// Buttery seek bar. The glitch/lag came from seeking the network video on
/// EVERY drag tick — each `seekTo` forces a re-buffer, so the picture
/// stuttered seconds behind the finger. The fix is to seek only ONCE, on
/// release:
///
///   * While dragging, only [_dragRatio] moves — the thumb + the left time
///     label follow the finger instantly with zero network work.
///   * On release we fire a single `seekTo`, and we HOLD the displayed
///     ratio at the target until that seek resolves, so the thumb never
///     snaps back to the old position and then jumps forward.
class _Scrubber extends StatefulWidget {
  final VideoPlayerController controller;
  final bool enabled;
  final Future<void> Function(double ratio) onSeek;
  final VoidCallback onScrubStart;
  final VoidCallback onScrubEnd;

  const _Scrubber({
    required this.controller,
    required this.enabled,
    required this.onSeek,
    required this.onScrubStart,
    required this.onScrubEnd,
  });

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  double? _dragRatio; // non-null while dragging OR while a release-seek lands

  /// Keep the thumb pinned at the released ratio [target] until the
  /// controller's reported position actually reaches it, so it never snaps
  /// back to the pre-seek spot for a frame. Polls at ~frame cadence and
  /// gives up after 700ms in case the position never lands exactly
  /// (keyframe snap / rounding), so this can't hang the release.
  Future<void> _settleThumb(double target) async {
    final c = widget.controller;
    final durMs = c.value.duration.inMilliseconds;
    if (durMs <= 0) return;
    final deadline = DateTime.now().add(const Duration(milliseconds: 700));
    while (mounted && DateTime.now().isBefore(deadline)) {
      final live = c.value.position.inMilliseconds / durMs;
      if ((live - target).abs() < 0.02) return; // within 2% → close enough
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final dur = c.value.duration;
    final liveRatio = dur.inMilliseconds > 0
        ? c.value.position.inMilliseconds / dur.inMilliseconds
        : 0.0;
    final ratio = (_dragRatio ?? liveRatio).clamp(0.0, 1.0);
    final shownPos =
        Duration(milliseconds: (dur.inMilliseconds * ratio).round());

    return Row(
      children: [
        Text(_BottomChrome._fmt(shownPos),
            style: const TextStyle(color: Colors.white, fontSize: 12)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: Colors.cyanAccent,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: ratio,
              onChangeStart: widget.enabled
                  ? (v) {
                      setState(() => _dragRatio = v);
                      widget.onScrubStart();
                    }
                  : null,
              // Drag = move the thumb only (no seeking → no stutter).
              onChanged: widget.enabled
                  ? (v) => setState(() => _dragRatio = v)
                  : null,
              // Release = a single seek; hold the target until it lands so
              // the thumb doesn't bounce back to the old spot.
              onChangeEnd: widget.enabled
                  ? (v) async {
                      setState(() => _dragRatio = v);
                      widget.onScrubEnd();
                      await widget.onSeek(v);
                      // seekTo's future resolves a beat before the
                      // controller's reported position updates. Releasing the
                      // hold right away let the thumb snap to the pre-seek
                      // spot for one frame — the visible glitch. Keep it
                      // pinned until the live position actually reaches the
                      // target (bounded, so we never hang).
                      await _settleThumb(v);
                      if (mounted) setState(() => _dragRatio = null);
                    }
                  : null,
            ),
          ),
        ),
        Text(_BottomChrome._fmt(dur),
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}
