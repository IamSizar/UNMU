// =============================================================================
// aurora_glass_surface.dart
//
// A pill-shaped Aurora bento glass surface.
//
// This is the chrome the bottom navigation floats in: a stadium-shaped pane
// that blurs whatever scrolls behind it, carries a bright inset edge along
// its top, and casts a brand-tinted glow rather than a neutral Material
// shadow.
//
// It paints the material only. It has no idea what sits inside it, so the
// same surface can wrap the nav bar, a filter row, or anything else that
// should read as aurora glass.
//
// Layer order, back to front:
//   1. aurora glow   — soft brand-coloured light bleeding out from behind
//   2. backdrop      — blur of the page underneath
//   3. fill          — translucent body, derived from the theme surface
//   4. sheen         — 1px inset highlight along the top edge
//   5. border        — brand-tinted hairline
//   6. child
// =============================================================================

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/aurora_tokens.dart';

/// A stadium-shaped frosted pane in the Aurora bento style.
class AuroraGlassSurface extends StatelessWidget {
  /// Content laid over the glass.
  final Widget child;

  /// Padding between the surface edge and [child].
  final EdgeInsetsGeometry padding;

  /// Resolved recipe. Passing one in lets a caller that already resolved the
  /// glass for this frame avoid a second lookup.
  final AuroraGlass? glass;

  const AuroraGlassSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.glass,
  });

  @override
  Widget build(BuildContext context) {
    final g = glass ?? AuroraGlass.of(context);

    // Stadium — a true pill. Height is decided by the child, so the radius
    // has to follow it rather than being a fixed number. StadiumBorder
    // always yields exact semicircular caps at any height, which is what
    // keeps the bar a pill on a small phone and on an iPad without a
    // per-device constant.
    const shape = StadiumBorder();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── 1. Aurora glow ──────────────────────────────────────────────
        // Sits behind the pill so colour bleeds past its edge the way light
        // does behind frosted glass. Ignores pointers so it can never
        // intercept a tab tap.
        Positioned.fill(
          child: IgnorePointer(child: _AuroraGlow(glass: g)),
        ),

        // ── 2-6. The pane itself ────────────────────────────────────────
        // ClipRRect, NOT ClipPath. A BackdropFilter only samples the
        // backdrop inside an enclosing RECTANGULAR clip; a ClipPath with a
        // custom clipper does not bound it, so the filter leaked across the
        // full width of the layer and painted a hard-edged lightened box
        // behind the bar. A 999 radius clamps to half the height, giving the
        // same stadium as StadiumBorder while keeping the clip a rounded
        // rect that the filter respects.
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: AuroraTokens.blurSigma,
              sigmaY: AuroraTokens.blurSigma,
            ),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: shape.copyWith(
                  side: BorderSide(color: g.border, width: 1),
                ),
                // A vertical gradient rather than a flat colour: the top
                // edge catches more light than the bottom, which is what
                // stops a wide pill reading as a flat slab.
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(g.sheen.withValues(alpha: 0.10), g.fill),
                    g.fill,
                  ],
                ),
                shadows: [
                  BoxShadow(
                    color: g.shadow,
                    blurRadius: 32,
                    spreadRadius: -10,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // ── 4. Inset sheen ────────────────────────────────────
                  // One hairline inside the top edge, inset horizontally so
                  // it stays on the flat of the pill instead of poking
                  // through the rounded caps. Fades out at both ends.
                  Positioned(
                    top: 0,
                    left: 24,
                    right: 24,
                    child: IgnorePointer(
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(1),
                          gradient: LinearGradient(
                            colors: [
                              g.sheen.withValues(alpha: 0),
                              g.sheen,
                              g.sheen.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(padding: padding, child: child),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

}

/// The soft brand-coloured light behind an aurora surface.
///
/// One blurred radial pool per sweep colour, spread across the width and then
/// blurred again as a group so they melt into each other instead of reading
/// as separate dots.
class _AuroraGlow extends StatelessWidget {
  final AuroraGlass glass;

  const _AuroraGlow({required this.glass});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 14),
      child: Opacity(
        opacity: glass.glowOpacity,
        child: Row(
          children: [
            for (final c in glass.sweep)
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [c, c.withValues(alpha: 0)],
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
