import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/halal_fintech_theme.dart';

/// Loading-state building blocks for the stocks + indexes surfaces.
///
/// Design notes (ui-ux-pro-max + Framer-Motion principles, rebuilt in Flutter):
///   • Skeletons mirror the real card's exact shape/size so the layout doesn't
///     jump when data arrives (no content-shift).
///   • A single left→right [Shimmer] sweep conveys "loading" subtly — Linear/
///     Vercel-level restraint, never a spinner.
///   • [StaggeredReveal] fades+slides items in one-by-one (Framer Motion's
///     `staggerChildren`) so the real content arrives with polish.
///   • Animate opacity/transform only (compositor-friendly), never layout.

// ─────────────────────────────────────────────────────────────────────────
// Shimmer — animated highlight sweep over its (opaque) children.
// ─────────────────────────────────────────────────────────────────────────
class Shimmer extends StatefulWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;

  const Shimmer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = widget.baseColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.06));
    final highlight = widget.highlightColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.black.withValues(alpha: 0.11));

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.25, 0.5, 0.75],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              transform: _SlidingGradientTransform(_ctrl.value),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slide; // 0..1
  const _SlidingGradientTransform(this.slide);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    // Sweep the gradient from fully off-screen left to fully off-screen right.
    return Matrix4.translationValues(bounds.width * (slide * 2.0 - 1.0), 0, 0);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// SkeletonBox — one opaque placeholder shape (the Shimmer recolors it).
// ─────────────────────────────────────────────────────────────────────────
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 12,
    this.radius = 7,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white, // recolored by the parent Shimmer's gradient
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// StaggeredReveal — fade + slide-up entrance, delayed by [index].
// Plays once when the widget is first inserted (e.g. when real cards replace
// skeletons). Cheap, self-disposing controller per item.
// ─────────────────────────────────────────────────────────────────────────
class StaggeredReveal extends StatefulWidget {
  final int index;
  final Widget child;
  final Duration baseDelay;

  const StaggeredReveal({
    super.key,
    required this.index,
    required this.child,
    this.baseDelay = const Duration(milliseconds: 55),
  });

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Cap the cumulative delay so a long list doesn't feel slow.
    final delayMs =
        (widget.index * widget.baseDelay.inMilliseconds).clamp(0, 600).toInt();
    _timer = Timer(Duration(milliseconds: delayMs), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// IndexCardSkeleton — mirrors IndexCard's layout (name+symbol | spark | price).
// ─────────────────────────────────────────────────────────────────────────
class IndexCardSkeleton extends StatelessWidget {
  const IndexCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.1),
        ),
      ),
      child: Shimmer(
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 120, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(width: 52, height: 10),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              flex: 2,
              child: SkeletonBox(height: 26, radius: 6),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                SkeletonBox(width: 66, height: 14),
                SizedBox(height: 8),
                SkeletonBox(width: 46, height: 18, radius: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// StockCardSkeleton — mirrors StockCard (logo | name + ticker/sector | grade).
// ─────────────────────────────────────────────────────────────────────────
class StockCardSkeleton extends StatelessWidget {
  const StockCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: isDark ? HalalFintechTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? HalalFintechTheme.cardBorderDark
              : HalalFintechTheme.cardBorderLight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Shimmer(
          child: Row(
            children: [
              const SkeletonBox(width: 46, height: 46, radius: 23),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SkeletonBox(width: 150, height: 15),
                    const SizedBox(height: 9),
                    Row(
                      children: const [
                        SkeletonBox(width: 46, height: 16, radius: 8),
                        SizedBox(width: 8),
                        SkeletonBox(width: 84, height: 12),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const SkeletonBox(width: 58, height: 26, radius: 999),
            ],
          ),
        ),
      ),
    );
  }
}

/// A staggered column of [IndexCardSkeleton]s for the indexes screen's
/// loading state. Includes faint category-header bars so the shape matches
/// the loaded screen.
class IndexListSkeleton extends StatelessWidget {
  final int count;
  const IndexListSkeleton({super.key, this.count = 7});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < count; i++) {
      // Drop a small header bar before the 1st and ~midway, mimicking the
      // "BENCHMARKS / GLOBAL / …" section labels.
      if (i == 0 || i == 3) {
        children.add(
          StaggeredReveal(
            index: i,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Shimmer(child: const SkeletonBox(width: 90, height: 11)),
            ),
          ),
        );
      }
      children.add(
        StaggeredReveal(index: i, child: const IndexCardSkeleton()),
      );
    }
    return Column(children: children);
  }
}

/// A staggered column of [StockCardSkeleton]s for the stocks list loading.
class StockListSkeleton extends StatelessWidget {
  final int count;
  const StockListSkeleton({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          StaggeredReveal(index: i, child: const StockCardSkeleton()),
      ],
    );
  }
}
