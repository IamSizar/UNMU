import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/haptic_utils.dart';

/// Big, expressive like-button used in the immersive reel right rail.
///
/// On tap (transition from not-liked → liked):
///   1. The heart bumps with an elastic-out scale curve.
///   2. A small burst of mini hearts shoots outward radially and fades.
///
/// On unlike, just the bump — no burst (you don't celebrate undoing).
///
/// Drives only the visual layer; the parent owns network state. Pass in
/// [liked] to control the visual state, [onTap] to be notified of taps.
class AnimatedLikeHeart extends StatefulWidget {
  final bool liked;
  final VoidCallback onTap;
  final double size;
  final Color filledColor;
  final Color outlineColor;

  const AnimatedLikeHeart({
    super.key,
    required this.liked,
    required this.onTap,
    this.size = 28,
    this.filledColor = const Color(0xFFFF3B5C),
    this.outlineColor = Colors.white,
  });

  @override
  State<AnimatedLikeHeart> createState() => _AnimatedLikeHeartState();
}

class _AnimatedLikeHeartState extends State<AnimatedLikeHeart>
    with TickerProviderStateMixin {
  late final AnimationController _bump;
  late final AnimationController _burst;

  @override
  void initState() {
    super.initState();
    _bump = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _bump.dispose();
    _burst.dispose();
    super.dispose();
  }

  /// Sync animations when `liked` flips from outside this widget — e.g.
  /// the user double-tapped the reel video and the parent flipped the
  /// state. Without this hook the rail heart would just snap-fill with no
  /// celebration, even though the user did "like" the post.
  @override
  void didUpdateWidget(covariant AnimatedLikeHeart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liked != widget.liked) {
      _bump
        ..value = 0
        ..forward();
      // Burst only on the not-liked → liked transition (we only celebrate
      // adding a like, never removing one).
      if (widget.liked) {
        _burst
          ..value = 0
          ..forward();
      }
    }
  }

  void _onTap() {
    // Direct rail-icon tap fires its own haptic — the parent's onTap
    // does the network call but doesn't haptic; double-tap-on-video
    // path haptics from its own gesture handler. So this is the only
    // place that hapticizes the rail-tap path.
    HapticUtils.tap();
    // Hand the toggle to the parent; the visual celebration is driven
    // by didUpdateWidget when `liked` flips, which converges direct-
    // tap and double-tap-on-the-reel into one animation path.
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: SizedBox(
        // Roomy hit area + space for the burst particles to fly out into.
        width: widget.size + 36,
        height: widget.size + 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Particle burst — only visible mid-animation.
            AnimatedBuilder(
              animation: _burst,
              builder: (_, __) {
                if (_burst.value == 0) return const SizedBox.shrink();
                return CustomPaint(
                  size: Size.square(widget.size + 36),
                  painter: _HeartBurstPainter(
                    progress: _burst.value,
                    color: widget.filledColor,
                  ),
                );
              },
            ),
            // The heart itself, with elastic-out bump.
            AnimatedBuilder(
              animation: _bump,
              builder: (_, __) {
                final t = _bump.value;
                // Curve: rest → 1.35 → 1.0 with elastic settle.
                final scale = 1.0 +
                    (math.sin(t * math.pi) * 0.35) +
                    (1 - t) * 0 +
                    Curves.elasticOut.transform(t.clamp(0.0, 1.0)) * 0;
                return Transform.scale(
                  scale: scale,
                  child: Icon(
                    widget.liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: widget.size,
                    color: widget.liked
                        ? widget.filledColor
                        : widget.outlineColor,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 6),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a ring of mini hearts that fly outward and fade as [progress]
/// runs from 0 → 1.
class _HeartBurstPainter extends CustomPainter {
  final double progress;
  final Color color;
  _HeartBurstPainter({required this.progress, required this.color});

  static const _count = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.shortestSide * 0.55;

    // Distance ramps fast at the start and eases out.
    final eased = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final radius = maxRadius * eased;

    // Particles fade from full alpha at t=0.15 down to 0 at t=1.0.
    final alpha = (1.0 - Curves.easeIn.transform(progress)).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;

    final particleSize = (size.shortestSide * 0.10) * (1.0 - progress * 0.4);

    for (var i = 0; i < _count; i++) {
      final angle = (i / _count) * math.pi * 2 + (math.pi / _count);
      final dx = math.cos(angle) * radius;
      final dy = math.sin(angle) * radius;
      _drawHeart(canvas, center + Offset(dx, dy), particleSize, paint);
    }
  }

  /// Approximates a heart shape using two circles + a triangle. Cheap and
  /// recognizable at small sizes.
  void _drawHeart(Canvas canvas, Offset c, double size, Paint paint) {
    final path = Path();
    final r = size / 2;
    final lobe = Offset(c.dx - r * 0.55, c.dy - r * 0.15);
    final lobe2 = Offset(c.dx + r * 0.55, c.dy - r * 0.15);
    canvas.drawCircle(lobe, r * 0.65, paint);
    canvas.drawCircle(lobe2, r * 0.65, paint);
    path.moveTo(c.dx - r, c.dy - r * 0.15);
    path.lineTo(c.dx + r, c.dy - r * 0.15);
    path.lineTo(c.dx, c.dy + r);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeartBurstPainter old) =>
      old.progress != progress || old.color != color;
}
