import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/cupertino.dart';
import 'screens/discover/discover_screen.dart';
import 'screens/watchlist/watchlist_screen.dart';
import 'screens/tools/tools_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/indexes/indexes_screen.dart';
import 'localization/halal_strings.dart';
import 'providers/language_provider.dart';
import 'utils/platform_utils.dart';
import 'theme/halal_fintech_theme.dart';

class MainTabScaffold extends StatefulWidget {
  const MainTabScaffold({super.key});

  @override
  State<MainTabScaffold> createState() => _MainTabScaffoldState();
}

class _MainTabScaffoldState extends State<MainTabScaffold> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isArabic = context.watch<LanguageProvider>().isArabic;
    final discoverLabel = isArabic
        ? HalalStringsAr.discover
        : HalalStrings.discover;
    final watchlistLabel = isArabic
        ? HalalStringsAr.watchlist
        : HalalStrings.watchlist;
    final toolsLabel = isArabic ? HalalStringsAr.tools : HalalStrings.tools;
    final profileLabel = isArabic
        ? HalalStringsAr.profile
        : HalalStrings.profile;
    final indexesLabel = isArabic
        ? HalalStringsAr.indexes
        : HalalStrings.indexes;

    final screens = [
      const DiscoverScreen(),
      const IndexesScreen(),
      const WatchlistScreen(),
      const ToolsScreen(),
      const ProfileScreen(),
    ];

    if (PlatformUtils.isIOS) {
      // iOS: Use standard CupertinoTabBar (Flutter-side, no platform views)
      return Scaffold(
        body: IndexedStack(index: _currentIndex, children: screens),
        bottomNavigationBar: CupertinoTabBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          activeColor: HalalFintechTheme.accentGreen,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(CupertinoIcons.globe),
              label: discoverLabel,
            ),
            BottomNavigationBarItem(
              icon: const Icon(CupertinoIcons.chart_bar),
              label: indexesLabel,
            ),
            BottomNavigationBarItem(
              icon: const Icon(CupertinoIcons.star),
              label: watchlistLabel,
            ),
            BottomNavigationBarItem(
              icon: const Icon(CupertinoIcons.wrench),
              label: toolsLabel,
            ),
            BottomNavigationBarItem(
              icon: const Icon(CupertinoIcons.person_circle),
              label: profileLabel,
            ),
          ],
        ),
      );
    } else {
      // Android: Use Material bottom navigation bar
      return Scaffold(
        body: IndexedStack(index: _currentIndex, children: screens),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: HalalFintechTheme.accentGreen,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.explore),
              label: discoverLabel,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.show_chart),
              label: indexesLabel,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.star),
              label: watchlistLabel,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.calculate),
              label: toolsLabel,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.person),
              label: profileLabel,
            ),
          ],
        ),
      );
    }
  }
}
