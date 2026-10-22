
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/social/social_tokens.dart';
import '../theme/aurora_tokens.dart';
import 'aurora/aurora_glass_surface.dart';

/// =============================================================================
/// Modern Bottom Navigation — context-aware floating capsule.
///
/// Rendered as an Aurora bento glass pill: a stadium-shaped frosted pane
/// (see widgets/aurora/aurora_glass_surface.dart) lit from behind by the
/// UNMU accent sweep, with the active tab marked by a sliding aurora pill.
/// Every colour is derived from [SocialTokens] / [SocialPalette] at build
/// time, so the bar follows the brand and the current theme.
///
/// The bar is identical on every tab. It used to morph into an
/// Articles/Videos/Reels filter row on the Feed page; that made the
/// navigation change shape under the user mid-journey, so the filter moved
/// back to the Feed screen's own menu where it belongs.
///
/// =============================================================================
class ModernBottomNav extends StatelessWidget {
  final int currentIndex;
  final List<NavItem> items;
  final ValueChanged<int> onTap;

  /// Smooth page offset from the parent `PageController` (e.g. 2.4 means
  /// "40% of the way from Social to Feed during a swipe"). Drives the
  /// sliding aurora pill and the colour interpolation of each
  /// tab's icon + label. When omitted, falls back to [currentIndex] so
  /// the bar still works in static contexts that aren't backed by a
  /// PageView.
  final double? currentPage;

  const ModernBottomNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.currentPage,
  });

  /// Effective page offset — honours `currentPage` when provided,
  /// otherwise the integer index. Clamped to `[0, items.length - 1]`
  /// so a runaway PageView overshoot can't drag the pill off the bar.
  double get _effectivePage {
    final raw = currentPage ?? currentIndex.toDouble();
    return raw.clamp(0.0, (items.length - 1).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    // Resolve the aurora recipe once for this frame and hand it to both the
    // surface and the sliding pill, so the two can never disagree about
    // which brightness they are painting for.
    final glass = AuroraGlass.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        // Floating pill — wider side margins than the old rounded-rect
        // bar. A stadium shape needs visible gutters to read as a pill
        // rather than a full-width bar with rounded ends, and the margin
        // gives the aurora glow somewhere to spill.
        //
        // The bottom inset is deliberately small: this sits INSIDE the
        // SafeArea, so the home indicator is already cleared and anything
        // larger just floats the bar awkwardly high up the screen.
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
        child: AuroraGlassSurface(
          glass: glass,
          // Wider horizontal padding than before so the first and last
          // tabs clear the pill's rounded caps instead of being clipped
          // by them.
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: _RegularTabRow(
            items: items,
            currentIndex: currentIndex,
            currentPage: _effectivePage,
            onTap: onTap,
            palette: palette,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Regular tab row.
//
// LAYOUT (current — June 2026):
//   Every tab is visible at once and all are the same size. The bar
//   stays at its natural compact height — no scrolling, no off-screen
//   tabs to hunt for. A sliding aurora pill sits BEHIND the active tab
//   and interpolates with `currentPage`, so a body-swipe glides it
//   smoothly between tab centres rather than snapping on release.
//
//   Why this over the earlier scrollable variant: navbar tabs that
//   require swiping to reach hurt navigation. Bigger labels aren't
//   worth less direct access — phones can render a readable 10pt
//   label at ~52px per tab on a ~370px screen, which is enough.
// ============================================================================
class _RegularTabRow extends StatelessWidget {
  final List<NavItem> items;
  final int currentIndex;
  /// Smooth page offset — used for the sliding pill + per-tab colour
  /// interpolation. Updated every frame while the user is swiping.
  final double currentPage;
  final ValueChanged<int> onTap;
  final SocialPalette palette;

  const _RegularTabRow({
    required this.items,
    required this.currentIndex,
    required this.currentPage,
    required this.onTap,
    required this.palette,
  });

  // The active indicator is a full-height aurora pill sitting behind the
  // selected tab, not the 3px dot this bar used before. A pill is what
  // makes the bar read as Aurora bento — a bento cell lit from inside —
  // and it reads at a glance where a hairline dot did not.
  //
  // Inset from the tab's own width so neighbouring pills would never touch
  // if the slide is interrupted mid-swipe.
  static const double _pillInsetX = 3;
  static const double _pillInsetY = 2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Equal-width tabs. Constraints.maxWidth includes the navbar's
        // inner padding (the parent Container handles outer margins).
        final tabWidth = constraints.maxWidth / items.length;
        // Sliding pill — positioned at the fractional current page so
        // it glides between tab centres while the user swipes the
        // body PageView.
        //
        // The tab Row auto-reverses under RTL, but Positioned.left is
        // ALWAYS physical-left — so under RTL we mirror the pill's x,
        // otherwise it lands over the LTR-mirror of the active tab
        // (i.e. the wrong tab) when the language is Arabic.
        final isRtl = Directionality.of(context) == TextDirection.rtl;
        final pillCenter = (currentPage + 0.5) * tabWidth;
        final pillLeft =
            (isRtl ? (constraints.maxWidth - pillCenter) : pillCenter) -
                (tabWidth / 2) +
                _pillInsetX;

        // Resolved once here rather than inside the pill so the aurora
        // colours are looked up a single time per layout pass.
        final glass = AuroraGlass.of(context);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Sliding aurora pill, UNDER the tabs so icons and labels stay
            // fully legible on top of it. Positioned (not animated) because
            // `currentPage` is already a smooth fractional value driven by
            // the body PageView — the pill tracks the user's finger frame
            // by frame rather than chasing it with its own animation.
            Positioned(
              left: pillLeft,
              top: _pillInsetY,
              bottom: _pillInsetY,
              width: tabWidth - (_pillInsetX * 2),
              child: IgnorePointer(
                child: _AuroraActivePill(glass: glass),
              ),
            ),
            Row(
              children: List.generate(items.length, (i) {
                // 1.0 when the page is exactly on this tab, 0.0 once
                // we're more than 1 page away. Linear ramp in between
                // gives the icon + label a smooth colour fade when
                // the user swipes between pages.
                final selection =
                    (1 - (i - currentPage).abs()).clamp(0.0, 1.0);
                return Expanded(
                  child: _NavTab(
                    item: items[i],
                    selection: selection,
                    palette: palette,
                    onTap: () {
                      if (i != currentIndex) {
                        HapticFeedback.selectionClick();
                      }
                      onTap(i);
                    },
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// _AuroraActivePill — the lit cell behind the selected tab.
//
// The aurora sweep at low alpha, inside a stadium with a brand-tinted rim and
// a soft outer glow. Alpha is deliberately low: this sits UNDER the icon and
// label, so anything stronger would cost the 4.5:1 text contrast the design
// rules require.
// ============================================================================
class _AuroraActivePill extends StatelessWidget {
  final AuroraGlass glass;

  const _AuroraActivePill({required this.glass});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(
          side: BorderSide(color: glass.pillGlow, width: 1),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: glass.pillFill,
        ),
        shadows: [
          BoxShadow(
            color: glass.pillGlow,
            blurRadius: 14,
            spreadRadius: -4,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Single regular-mode tab — receives a smooth `selection` (0..1) so the
// icon + label + halo all interpolate smoothly as the user swipes
// between pages. The active indicator is not drawn here; it's a single
// aurora pill in [_RegularTabRow] that slides between tab centres
// BEHIND this widget.
//
// Layout per tab (top → bottom):
//   • Icon with a halo that fades in proportional to `selection`
//   • Always-visible label, colour-interpolated from muted → cyan
//
// `selection` semantics:
//   1.0  → exactly on this tab
//   0.5  → halfway between this tab and the next/prev one
//   0.0  → at least one full tab away
// ============================================================================
class _NavTab extends StatelessWidget {
  final NavItem item;

  /// Smooth selection amount, 0..1. Drives every visual aspect of the
  /// tab so the colour change tracks the user's finger during a swipe.
  final double selection;

  final SocialPalette palette;
  final VoidCallback onTap;

  const _NavTab({
    required this.item,
    required this.selection,
    required this.palette,
    required this.onTap,
  });

  // Threshold above which we count the tab as "the home". Drives the
  // filled-vs-outlined icon morph and the bold-vs-regular weight on
  // the label. Picked > 0.5 so we don't flip-flop mid-swipe.
  static const double _commitThreshold = 0.5;

  @override
  Widget build(BuildContext context) {
    const activeColor = SocialTokens.cyan;
    final inactiveColor = palette.textMuted;

    // Linear interpolation between muted and active for both icon + label.
    final lerpedColor =
        Color.lerp(inactiveColor, activeColor, selection) ?? inactiveColor;
    final isCommitted = selection > _commitThreshold;

    return InkResponse(
      onTap: onTap,
      // Bounded ripple — matches the tab's footprint so taps feel
      // precise (the default Material splash spreads beyond the
      // container).
      radius: 36,
      highlightShape: BoxShape.rectangle,
      child: Padding(
        // Compact padding — tabs are ~52px wide on a typical phone
        // (equal-width with 7 items), so per-tab padding stays small
        // to keep the icon + label centred without overflowing.
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // No top spacer any more. The old sliding dot lived above the
            // icon and every tab had to reserve 10px for it to keep a
            // shared baseline. The aurora pill sits BEHIND the whole tab
            // instead, so the icon and label can centre in the pill —
            // reserving space here would push them off-centre inside it.
            // Icon with a halo that brightens as `selection` rises.
            // 30×30 sizes the active state visibly without crowding a
            // narrow tab.
            SizedBox(
              width: 30,
              height: 30,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Halo — opacity interpolates with `selection`.
                  Opacity(
                    opacity: selection,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Color(0x3800D9FF), // ~22% cyan
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Icon — outlined ↔ filled morph, flips at the
                  // commit threshold to avoid mid-swipe flicker.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: Icon(
                      isCommitted
                          ? (item.activeIcon ?? item.icon)
                          : item.icon,
                      key: ValueKey<bool>(isCommitted),
                      size: 21,
                      color: lerpedColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            // Always-visible label. 10pt is the sweet spot for the
            // compressed tab width — readable at arm's length, fits
            // every existing label without ellipsis on the standard
            // 7-tab set (Discover / Indexes / Social / Feed /
            // Watchlist / Tools / Profile).
            DefaultTextStyle(
              style: TextStyle(
                color: lerpedColor,
                fontWeight: isCommitted ? FontWeight.w900 : FontWeight.w700,
                fontSize: 10,
                letterSpacing: 0.1,
                height: 1.1,
              ),
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Description of a single nav tab.
class NavItem {
  /// Icon shown when the tab is unselected. Use the *outlined* variant.
  final IconData icon;

  /// Optional filled variant shown when selected. Falls back to [icon].
  final IconData? activeIcon;

  /// Label shown when the tab is active (slides in alongside the icon).
  final String label;

  const NavItem({
    required this.icon,
    this.activeIcon,
    required this.label,
  });
}
