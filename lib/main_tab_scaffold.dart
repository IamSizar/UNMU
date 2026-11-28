import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'controllers/auth_controller.dart';
import 'controllers/feed_controller.dart';
import 'utils/haptic_utils.dart';
import 'utils/responsive.dart';
import 'widgets/auth/auth_widgets.dart';
import 'screens/social/social_tokens.dart';
import 'screens/discover/discover_screen.dart';
import 'screens/feed/feed_screen.dart';
import 'screens/indexes/indexes_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/pulse/pulse_home_screen.dart';
import 'screens/social/social_hub_screen.dart';
// Watchlist + Tools live in Profile → Quick Actions (May 2026).
// The PageView holds five tab screens (Pulse, Discover, Indexes, Social, Feed)
// and the bottom nav shows one button per page. Profile is a pushed route
// opened from the avatar button on each screen, not a tab.
import 'widgets/modern_bottom_nav.dart';

/// Main tab scaffold using a unified modern floating bottom navigation
/// across iOS and Android. The body screens stay platform-adaptive
/// internally, but the chrome (nav bar) is one branded look.
///
/// May 2026 refresh — swap from `IndexedStack` to a `PageView` so users
/// can SWIPE horizontally between tabs (Discover ↔ Indexes ↔ Social ↔
/// Feed). State is preserved per page via
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
    // in this order, and the bottom nav has one button per page.
    // Only feedPage is referenced by name — the reels viewer needs to know
    // when it is on screen. The other three are implied by list order.
    const feedPage = 4;

    final screens = const [
      PulseHomeScreen(),   // page 0 — UNMU Pulse, the daily briefing
      DiscoverScreen(),    // page 1
      IndexesScreen(),     // page 2
      SocialHubScreen(),   // page 3
      FeedScreen(),        // page 4
    ];

    // Five permanent destinations, one per page — no contextual slot.
    //
    // Position 1 used to swap between Indexes and Feed depending on where
    // you already were, which meant whichever of the two you were NOT on had
    // no button at all and could only be reached by swiping. Profile moved
    // to a top-right avatar on every screen (see ProfileAvatarButton), which
    // freed the slot this needed.
    final navItems = <NavItem>[
      NavItem(
        icon: Icons.monitor_heart_outlined,
        activeIcon: Icons.monitor_heart,
        label: 'nav.pulse'.tr,
      ),
      NavItem(
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore,
        label: 'nav.discover'.tr,
      ),
      NavItem(
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
        icon: Icons.dynamic_feed_outlined,
        activeIcon: Icons.dynamic_feed,
        label: 'nav.feed'.tr,
      ),
    ];

    // Nav button index and page index are now the same number, so the two
    // lookup tables this used to need are gone.

    // feedTabIndex feeds the existing `isFeedTabActive` Rx so the
    // reels viewer can pause when the user leaves Feed. The flag
    // takes a page index (not a nav slot), so feedPage (4) is the
    // correct value here.
    const feedTabIndex = feedPage;

    final feed = Get.find<FeedController>();

    // Shared body — the same PageView on every form factor. Swipes still
    // work linearly (Pulse → Discover → Indexes → Social → Feed).
    final pageView = PageView(
      controller: _pageController,
      physics: const BouncingScrollPhysics(),
      onPageChanged: (i) => _onSwipe(i, feed, feedTabIndex),
      children: [
        for (final s in screens) _KeepAlivePage(child: s),
      ],
    );

    // ── iPad / wide layout ───────────────────────────────────────────
    // A side NavigationRail replaces the bottom bar. A rail has room for
    // all FOUR real destinations, so we skip the phone navbar's contextual
    // Indexes↔Feed slot entirely and map 1:1 to pages. There is no bottom
    // bar here at all: it used to appear on the Feed page purely to host the
    // Articles/Videos/Reels filter, and that filter now lives only in the
    // Feed screen's own menu (see feed_screen.dart). The rail owns
    // navigation; nothing is left for a bottom bar to do.
    if (context.isWide) {
      return Scaffold(
        body: Obx(() {
          final fullscreen = feed.reelsFullscreen.value;
          // Reels fullscreen → drop the rail so the video owns the screen.
          if (fullscreen) return pageView;
          return Row(
            children: [
              _buildSideNav(context, feed, feedTabIndex),
              Expanded(child: pageView),
            ],
          );
        }),
      );
    }

    // ── Phone layout (unchanged) ──────────────────────────────────────
    return Scaffold(
      // The floating aurora pill is drawn OVER the page, not in a reserved
      // slot beneath it. Without extendBody the Scaffold paints its own
      // background in that slot, which reads as a dark band behind the bar
      // and defeats the point of a glass surface — there is nothing behind
      // it to blur.
      extendBody: true,
      // PageView holds the 5 tab screens. Swipes still work
      // linearly (Pulse → Discover → Indexes → Social → Feed) — the
      // navbar shows one button per page.
      body: pageView,
      // Bottom navbar hides when the reels viewer toggles fullscreen.
      // The page index and the nav button index are the same number.
      //
      // The bar is the SAME on every tab, Feed included. It used to morph
      // into an Articles/Videos/Reels filter row on the Feed page, which
      // meant the navigation changed shape under the user mid-journey. The
      // filter is still available, from the Feed screen's own menu, where
      // it belongs — filtering a list is the list's job, not the nav's.
      bottomNavigationBar: Obx(
        () {
          if (feed.reelsFullscreen.value) return const SizedBox.shrink();
          return ModernBottomNav(
            currentIndex: _currentIndex,
            currentPage: _currentIndex.toDouble(),
            items: navItems,
            onTap: (page) => _goToTab(page, feed, feedTabIndex),
          );
        },
      ),
    );
  }

  /// Custom branded iPad side navigation (replaces the stock NavigationRail).
  /// Logo header on top, premium capsule-style selected state, and a tappable
  /// user chip anchored at the bottom. Compact icons + small labels on a
  /// portrait iPad; wider with labels beside icons on a large landscape
  /// canvas. RTL is handled automatically by the parent Directionality.
  Widget _buildSideNav(
    BuildContext context,
    FeedController feed,
    int feedTabIndex,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final extended = context.isWideLandscape;
    const accent = SocialTokens.cyan;

    const items = <(IconData, IconData, String)>[
      (Icons.monitor_heart_outlined, Icons.monitor_heart, 'nav.pulse'),
      (Icons.explore_outlined, Icons.explore, 'nav.discover'),
      (Icons.bar_chart_outlined, Icons.bar_chart, 'nav.indexes'),
      (Icons.groups_outlined, Icons.groups, 'nav.social'),
      (Icons.dynamic_feed_outlined, Icons.dynamic_feed, 'nav.feed'),
    ];

    return Container(
      width: extended ? 250 : 96,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0E1722) : Colors.white,
        border: Border(
          right: BorderSide(
            color: isDark ? Colors.white10 : const Color(0xFFE6EBF2),
          ),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            // ── Brand header ──
            Padding(
              padding: EdgeInsets.symmetric(horizontal: extended ? 20 : 0),
              child: Row(
                mainAxisAlignment: extended
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  const AuthBrandMark(size: 34),
                  if (extended) ...[
                    const SizedBox(width: 10),
                    Text(
                      'UNMU',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
            // ── Destinations ──
            for (var i = 0; i < items.length; i++)
              _SideNavTile(
                icon: items[i].$1,
                activeIcon: items[i].$2,
                label: items[i].$3.tr,
                selected: _currentIndex == i,
                extended: extended,
                accent: accent,
                onTap: () => _goToTab(i, feed, feedTabIndex),
              ),
            const Spacer(),
            // ── User chip (anchored bottom) ──
            _SideNavUserChip(
              extended: extended,
              accent: accent,
              // Profile is a pushed route, not a page, so the rail's user
              // chip opens it the same way the phone's top-right avatar does.
              onTap: () => Get.to(() => const ProfileScreen()),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

/// One destination row in the iPad side nav. Selected = a rounded capsule
/// with the cyan accent gradient + a soft glow; unselected = muted icon+label.
class _SideNavTile extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final bool extended;
  final Color accent;
  final VoidCallback onTap;
  const _SideNavTile({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.extended,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected
        ? accent
        : theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final content = extended
        ? Row(
            children: [
              Icon(selected ? activeIcon : icon, color: fg, size: 24),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? activeIcon : icon, color: fg, size: 25),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: extended ? 12 : 10, vertical: 4),
          padding: EdgeInsets.symmetric(
            horizontal: extended ? 14 : 0,
            vertical: extended ? 12 : 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected
                ? LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.22),
                      accent.withValues(alpha: 0.10),
                    ],
                  )
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Signed-in user chip at the bottom of the iPad side nav — avatar + name,
/// tap jumps to Profile. Rebuilds reactively on login/logout.
class _SideNavUserChip extends StatelessWidget {
  final bool extended;
  final Color accent;
  final VoidCallback onTap;
  const _SideNavUserChip({
    required this.extended,
    required this.accent,
    required this.onTap,
  });

  String _initials(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    final parts = t.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final theme = Theme.of(context);
    return Obx(() {
      final user = auth.userObservable.value;
      final name = user?.name ?? 'Guest';
      final avatarAccent = auth.avatarAccent ?? accent;
      final avatar = Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: avatarAccent.withValues(alpha: 0.18),
        ),
        child: Text(
          _initials(name),
          style: TextStyle(
            color: avatarAccent,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      );
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: extended ? 12 : 10),
            padding: EdgeInsets.symmetric(
              horizontal: extended ? 10 : 0,
              vertical: 8,
            ),
            child: extended
                ? Row(
                    children: [
                      avatar,
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'nav.profile'.tr,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Center(child: avatar),
          ),
        ),
      );
    });
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
