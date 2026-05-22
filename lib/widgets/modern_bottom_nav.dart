import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../controllers/feed_controller.dart';
import '../models/expert_post.dart';
import '../screens/social/social_tokens.dart';

/// =============================================================================
/// Modern Bottom Navigation — context-aware floating capsule.
///
/// Two modes that swap with a 300ms cross-fade + slide:
///
///   1. Regular  — the default 7-tab nav (Discover · Indexes · Social ·
///                 Feed · Watchlist · Tools · Profile). Inactive tabs
///                 are icon-only; the active tab expands into a
///                 cyan-gradient pill with its label.
///
///   2. Feed     — when the user is on the Feed tab, the bar morphs
///                 into a filter-aware row:
///
///                  [ 🏠 ]  [ Articles ]  [ Videos ]  [ Reels ]  [ 👤 ]
///
///                 Tapping a filter pill flips
///                 [FeedController.setFilter] (same plumbing the in-page
///                 dropdown uses). Tapping an *active* filter pill
///                 deselects it → back to "All". The home pill on the
///                 left bounces back to the Discover tab; the profile
///                 pill on the right jumps straight to Profile.
///
/// Switch is driven by `feedMode` from the scaffold.
/// =============================================================================
class ModernBottomNav extends StatelessWidget {
  final int currentIndex;
  final List<NavItem> items;
  final ValueChanged<int> onTap;

  /// Smooth page offset from the parent `PageController` (e.g. 2.4 means
  /// "40% of the way from Social to Feed during a swipe"). Drives the
  /// sliding cyan dot indicator and the colour interpolation of each
  /// tab's icon + label. When omitted, falls back to [currentIndex] so
  /// the bar still works in static contexts that aren't backed by a
  /// PageView.
  final double? currentPage;

  /// When true, the bar renders the Feed-mode filter row instead of the
  /// regular tab list. Driven by the scaffold based on `currentIndex`.
  final bool feedMode;

  /// Tapped when the home pill is pressed in Feed mode — typically
  /// "switch to Discover" so the user can escape filter mode without
  /// losing the rest of the nav.
  final VoidCallback? onGoHome;

  /// Tapped when the profile pill is pressed in Feed mode.
  final VoidCallback? onGoProfile;

  const ModernBottomNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.currentPage,
    this.feedMode = false,
    this.onGoHome,
    this.onGoProfile,
  });

  /// Effective page offset — honours `currentPage` when provided,
  /// otherwise the integer index. Clamped to `[0, items.length - 1]`
  /// so a runaway PageView overshoot doesn't drag the dot off the bar.
  double get _effectivePage {
    final raw = currentPage ?? currentIndex.toDouble();
    return raw.clamp(0.0, (items.length - 1).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        // Floating glass bar — a hair of horizontal margin from the
        // screen edges so the shadow can render cleanly.
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: ClipRRect(
          // Glass effect — the page content behind the bar gets a real
          // backdrop blur, so the bar feels like floating glass instead
          // of a flat panel. Subtle, but it elevates "looks premium".
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              // Compact inner padding — the tabs handle their own
              // internal layout; the bar just needs enough room
              // for the rounded border + dot indicator overflow.
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                // Translucent surface so the blur shows through. Falls
                // back to a fully-opaque surface on light themes where
                // the translucent variant would wash out.
                color: palette.surface.withValues(
                  alpha: palette.isDark ? 0.78 : 0.92,
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: palette.border.withValues(alpha: 0.65),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: palette.isDark ? 0.50 : 0.10,
                    ),
                    blurRadius: 30,
                    spreadRadius: -6,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              // Cross-fade + slide between the two layouts. KeyedSubtree
              // assigns each layout a stable key so AnimatedSwitcher knows
              // they're different children and runs the transition.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) {
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.25),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: feedMode
                    ? _FeedFilterRow(
                        key: const ValueKey('feed-filter-row'),
                        palette: palette,
                        onGoHome: onGoHome,
                        onGoProfile: onGoProfile,
                      )
                    : _RegularTabRow(
                        key: const ValueKey('regular-tab-row'),
                        items: items,
                        currentIndex: currentIndex,
                        currentPage: _effectivePage,
                        onTap: onTap,
                        palette: palette,
                      ),
              ),
            ),
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
//   All 7 tabs are visible at once, every one the same size. The bar
//   stays at its natural compact height — no scrolling, no off-screen
//   tabs to hunt for. Sliding cyan dot indicator at the top of each
//   tab tracks the active page; the dot interpolates with
//   `currentPage` so body-swipes glide it smoothly between tab
//   centres.
//
//   Why this over the earlier scrollable variant: navbar tabs that
//   require swiping to reach hurt navigation. Bigger labels aren't
//   worth less direct access — phones can render a readable 10pt
//   label at ~52px per tab on a ~370px screen, which is enough.
// ============================================================================
class _RegularTabRow extends StatelessWidget {
  final List<NavItem> items;
  final int currentIndex;
  /// Smooth page offset — used for the sliding dot + per-tab colour
  /// interpolation. Updated every frame while the user is swiping.
  final double currentPage;
  final ValueChanged<int> onTap;
  final SocialPalette palette;

  const _RegularTabRow({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.currentPage,
    required this.onTap,
    required this.palette,
  });

  static const double _dotWidth = 16;
  static const double _dotHeight = 3;
  static const double _dotTopOffset = 3;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Equal-width tabs. Constraints.maxWidth includes the navbar's
        // inner padding (the parent Container handles outer margins).
        final tabWidth = constraints.maxWidth / items.length;
        // Sliding dot — positioned at the fractional current page so
        // it glides between tab centres while the user swipes the
        // body PageView.
        //
        // The tab Row auto-reverses under RTL, but Positioned.left is
        // ALWAYS physical-left — so under RTL we mirror the dot's x,
        // otherwise it lands over the LTR-mirror of the active tab
        // (i.e. the wrong tab) when the language is Arabic.
        final isRtl = Directionality.of(context) == TextDirection.rtl;
        final dotCenter = (currentPage + 0.5) * tabWidth;
        final dotLeft =
            (isRtl ? (constraints.maxWidth - dotCenter) : dotCenter) -
                (_dotWidth / 2);

        return Stack(
          clipBehavior: Clip.none,
          children: [
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
            // Sliding dot indicator.
            Positioned(
              top: _dotTopOffset,
              left: dotLeft,
              child: Container(
                width: _dotWidth,
                height: _dotHeight,
                decoration: BoxDecoration(
                  color: SocialTokens.cyan,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: SocialTokens.cyan.withValues(alpha: 0.55),
                      blurRadius: 6,
                      spreadRadius: -1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// Feed-mode filter row — home + 3 filter pills + profile.
//
// The filter state lives in `FeedController` (the same controller the
// in-page dropdown writes to), so toggling a pill here also flips the
// dropdown — and vice versa. Wrapped in Obx so the highlighted pill
// updates the moment the filter state changes from anywhere.
// ============================================================================
class _FeedFilterRow extends StatelessWidget {
  final SocialPalette palette;
  final VoidCallback? onGoHome;
  final VoidCallback? onGoProfile;

  const _FeedFilterRow({
    super.key,
    required this.palette,
    required this.onGoHome,
    required this.onGoProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ctrl = Get.find<FeedController>();
      final active = ctrl.filter;

      void setOrToggle(PostType type) {
        HapticFeedback.selectionClick();
        // Tap-the-active-pill behaviour: implicit "All" by deselecting.
        ctrl.setFilter(active == type ? null : type);
      }

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _MiniRoundButton(
            icon: Icons.home_rounded,
            tooltip: 'nav.backToDiscover'.tr,
            palette: palette,
            onTap: () {
              HapticFeedback.selectionClick();
              onGoHome?.call();
            },
          ),
          _FilterPill(
            label: 'feed.filter.articles'.tr,
            icon: Icons.text_snippet_rounded,
            selected: active == PostType.article,
            palette: palette,
            onTap: () => setOrToggle(PostType.article),
          ),
          _FilterPill(
            label: 'feed.filter.videos'.tr,
            icon: Icons.smart_display_rounded,
            selected: active == PostType.video,
            palette: palette,
            onTap: () => setOrToggle(PostType.video),
          ),
          _FilterPill(
            label: 'feed.filter.reels'.tr,
            icon: Icons.ondemand_video_rounded,
            selected: active == PostType.reel,
            palette: palette,
            onTap: () => setOrToggle(PostType.reel),
          ),
          _MiniRoundButton(
            icon: Icons.person_rounded,
            tooltip: 'nav.profile'.tr,
            palette: palette,
            onTap: () {
              HapticFeedback.selectionClick();
              onGoProfile?.call();
            },
          ),
        ],
      );
    });
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final SocialPalette palette;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [SocialTokens.cyan, SocialTokens.cyanSoft],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: SocialTokens.cyan.withValues(alpha: 0.5),
                    blurRadius: 16,
                    spreadRadius: -4,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? const Color(0xFF0A1628)
                  : palette.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF0A1628)
                    : palette.textMuted,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniRoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final SocialPalette palette;
  final VoidCallback onTap;

  const _MiniRoundButton({
    required this.icon,
    required this.tooltip,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.surfaceElevated,
            border: Border.all(color: palette.border),
          ),
          child: Icon(icon, size: 18, color: palette.textPrimary),
        ),
      ),
    );
  }
}

// ============================================================================
// Single regular-mode tab — receives a smooth `selection` (0..1) so the
// icon + label + halo all interpolate smoothly as the user swipes
// between pages. The dot indicator is no longer drawn here; it's a
// single overlay in [_RegularTabRow] that slides between tab centres.
//
// Layout per tab (top → bottom):
//   • Spacer matching the overlay dot's height + padding (so labels
//     align across all tabs whether the dot is over them or not)
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
            // Reserve vertical space where the sliding dot lives so
            // every tab's icon + label sit at the same baseline,
            // whether the dot is hovering over them or not.
            //   dotTopOffset(3) + dotHeight(3) + 4 extra = 10
            const SizedBox(height: 10),
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
