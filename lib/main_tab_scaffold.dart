import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controllers/feed_controller.dart';
import 'utils/haptic_utils.dart';
import 'screens/discover/discover_screen.dart';
import 'screens/feed/feed_screen.dart';
import 'screens/indexes/indexes_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/social/social_hub_screen.dart';
// Watchlist + Tools live in Profile → Quick Actions (May 2026).
// Feed is NOT a top-level button anymore — it sits in the PageView
// at position 3, but the bottom nav only shows 4 buttons at a time
// and position #2 is contextual: shows Indexes by default, swaps to
// Feed when the user is on the Social tab (or already on Feed). The
// swap is purely a navbar concern; the underlying PageView always
// holds all 5 screens.
import 'widgets/modern_bottom_nav.dart';

/// Main tab scaffold using a unified modern floating bottom navigation
/// across iOS and Android. The body screens stay platform-adaptive
/// internally, but the chrome (nav bar) is one branded look.
///
/// May 2026 refresh — swap from `IndexedStack` to a `PageView` so users
/// can SWIPE horizontally between tabs (Discover ↔ Indexes ↔ Social ↔
/// Feed ↔ Watchlist ↔ Tools ↔ Profile). State is preserved per page via
/// a [_KeepAlivePage] wrapper using `AutomaticKeepAliveClientMixin`, so
/// scroll positions, fetched lists, etc. don't reset on tab change.
///
/// Tap behaviour stays the same — tapping a nav tab JUMPS straight to
/// that page (no animated scroll through 5 intermediate pages, which
/// would flash content). Swipes get smooth physics + page-snap.
class MainTabScaffold extends StatefulWidget {
  const MainTabScaffold({super.key});

  @override
  State<MainTabScaffold> createState() => _MainTabScaffoldState();
}

class _MainTabScaffoldState extends State<MainTabScaffold> {
  int _currentIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Centralised tab switch — used by both the nav-bar onTap and the
  /// feed-mode home/profile shortcuts. Updates the page-view + state +
  /// feed-tab-active tracking in one place so we can never get them
  /// out of sync.
  ///
  /// Uses `jumpToPage` (not `animateToPage`) so far jumps (e.g. Discover
  /// → Profile, 6 pages apart) don't flash through every intermediate
  /// tab. PageView would otherwise build each transition frame.
  void _goToTab(int i, FeedController feed, int feedTabIndex) {
    if (i != _currentIndex) HapticUtils.pick();
    setState(() => _currentIndex = i);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(i);
    }
    // Tell the reels viewer the moment we leave / return to the Feed
    // tab. VisibilityDetector alone can't catch this because the
    // previous IndexedStack hid inactive tabs via Offstage; PageView
    // does keep them mounted but our `_KeepAlivePage` keeps them alive
    // even off-screen, so we still rely on this flag rather than
    // visibility callbacks.
    feed.isFeedTabActive.value = (i == feedTabIndex);
  }

  /// Called by [PageView.onPageChanged] when the user SWIPES. We sync
  /// `_currentIndex` and the feed-tab-active flag here, but skip the
  /// jumpToPage call (which would be a no-op anyway — PageView already
  /// landed on `i`).
  void _onSwipe(int i, FeedController feed, int feedTabIndex) {
    if (i == _currentIndex) return;
    HapticUtils.pick();
    setState(() => _currentIndex = i);
    feed.isFeedTabActive.value = (i == feedTabIndex);
  }

  @override
  Widget build(BuildContext context) {
    // ── 5 underlying screens in fixed page-order ────────────────────
    // Page indices are LITERAL — the PageView always shows these five
    // in this order. The bottom nav only renders 4 buttons at a time;
    // the 2nd button is contextual (see navItems + helpers below).
    const discoverPage = 0;
    const indexesPage  = 1;
    const socialPage   = 2;
    const feedPage     = 3;
    const profilePage  = 4;

    final screens = const [
      DiscoverScreen(),    // page 0
      IndexesScreen(),     // page 1
      SocialHubScreen(),   // page 2
      FeedScreen(),        // page 3
      ProfileScreen(),     // page 4
    ];

    // The "Social context" includes both the Social hub AND the Feed
    // screen. Whenever the user is on either one, the 2nd nav slot
    // swaps from Indexes → Feed. Elsewhere it's Indexes.
    final inSocialContext =
        _currentIndex == socialPage || _currentIndex == feedPage;

    // Build the 4 visible nav items. Position 1 is the contextual one.
    final navItems = <NavItem>[
      NavItem(
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore,
        label: 'nav.discover'.tr,
      ),
      inSocialContext
          ? NavItem(
              icon: Icons.dynamic_feed_outlined,
              activeIcon: Icons.dynamic_feed,
              label: 'nav.feed'.tr,
            )
          : NavItem(
              icon: Icons.bar_chart_outlined,
              activeIcon: Icons.bar_chart,
              label: 'nav.indexes'.tr,
            ),
      NavItem(
        icon: Icons.groups_outlined,
        activeIcon: Icons.groups,
        label: 'nav.social'.tr,
      ),
      NavItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        label: 'nav.profile'.tr,
      ),
    ];

    // Map page index (0-4) → active nav-button index (0-3).
    int navActive;
    switch (_currentIndex) {
      case discoverPage:  navActive = 0; break;
      case indexesPage:   navActive = 1; break;   // Indexes shown in slot 1
      case socialPage:    navActive = 2; break;
      case feedPage:      navActive = 1; break;   // Feed shown in slot 1
      case profilePage:   navActive = 3; break;
      default:            navActive = 0;
    }

    // Map nav-button index (0-3) → page index (0-4). Position 1 is
    // contextual: it represents Indexes by default but Feed when the
    // viewer is already inside the Social context.
    int navPositionToPage(int navIndex) {
      switch (navIndex) {
        case 0: return discoverPage;
        case 1: return inSocialContext ? feedPage : indexesPage;
        case 2: return socialPage;
        case 3: return profilePage;
        default: return discoverPage;
      }
    }

    // feedTabIndex feeds the existing `isFeedTabActive` Rx so the
    // reels viewer can pause when the user leaves Feed. The flag
    // takes a page index (not a nav slot), so feedPage (3) is the
    // correct value here.
    const feedTabIndex = feedPage;

    final feed = Get.find<FeedController>();
    return Scaffold(
      // PageView holds all 5 underlying screens. Swipes still work
      // linearly (Discover → Indexes → Social → Feed → Profile) — the
      // navbar simply shows 4 buttons and visually swaps position 1
      // between Indexes and Feed based on the current page.
      body: PageView(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (i) => _onSwipe(i, feed, feedTabIndex),
        children: [
          for (final s in screens) _KeepAlivePage(child: s),
        ],
      ),
      // Bottom navbar hides when the reels viewer toggles fullscreen.
      // We pass the integer `navActive` (0-3) so the cyan indicator
      // dot maps to the correct nav button regardless of which of the
      // 5 underlying pages the user is on.
      //
      // feedMode = true when the user is on the Feed page (3) → the
      // navbar morphs into the Articles/Videos/Reels filter pill bar
      // (the home + profile shortcuts re-appear on either end). The
      // home pill drops the user back to Social Hub since Feed lives
      // inside the Social context.
      bottomNavigationBar: Obx(
        () {
          if (feed.reelsFullscreen.value) return const SizedBox.shrink();
          final onFeedPage = _currentIndex == feedPage;
          return ModernBottomNav(
            currentIndex: navActive,
            currentPage: navActive.toDouble(),
            items: navItems,
            onTap: (navIndex) {
              final targetPage = navPositionToPage(navIndex);
              _goToTab(targetPage, feed, feedTabIndex);
            },
            feedMode: onFeedPage,
            // Home pill (only visible in feedMode) → back to Social
            // Hub, which is the "non-feed" half of the Social context.
            onGoHome: () => _goToTab(socialPage, feed, feedTabIndex),
            onGoProfile: () => _goToTab(profilePage, feed, feedTabIndex),
          );
        },
      ),
    );
  }
}

// ============================================================================
// _KeepAlivePage — wraps an off-screen PageView child so its State is
// preserved when the user swipes / jumps away.
//
// Without this, PageView dispose()s pages once they leave its cache
// extent, which means scroll positions, fetched lists, video players,
// etc. would reset on every tab change. AutomaticKeepAliveClientMixin
// asks the parent (PageView) to keep this State alive even when it's
// not currently visible — same effect as the old IndexedStack.
// ============================================================================
class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  // Must return true so PageView treats this State as kept-alive.
  // PageView walks its children and only retains state for those that
  // mix in AutomaticKeepAliveClientMixin AND return true here.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    // Required by AutomaticKeepAliveClientMixin — ensures the mixin's
    // own build hook runs before the child's tree.
    super.build(context);
    return widget.child;
  }
}
