import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/watchlist_controller.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/social/social_tokens.dart';
import '../../screens/stock_detail/stock_detail_screen.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/responsive.dart';
import '../../widgets/platform_adaptive/platform_dialog.dart';
import '../../widgets/stock_card.dart';

/// =============================================================================
/// Watchlist Screen — editorial bento redesign.
///
///   ▸ Themed app bar
///   ▸ Hero summary bento (Total · Halal · Mixed) — 3 cells with accents
///   ▸ Filter chips (All · Grade A · Grade B · Halal · Mixed)
///   ▸ Section header with count
///   ▸ Stock cards with floating star/remove on hover
///   ▸ Polished empty + unauth states
/// =============================================================================
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  String? _selectedFilter; // null = ALL, 'HALAL', 'MIXED', 'A', 'B'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Get.find<AuthController>();
      if (auth.isAuthenticated) {
        Get.find<WatchlistController>().loadWatchlist(auth.token);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final auth = Get.find<AuthController>();
    final wl = Get.find<WatchlistController>();

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'watchlist.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
        actions: [
          IconButton(
            icon: Icon(Icons.tune_rounded, color: palette.textPrimary),
            onPressed: () {},
            tooltip: 'watchlist.sort'.tr,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: !auth.isAuthenticated
          ? _UnauthState(palette: palette)
          : _buildAuthenticatedBody(palette, auth, wl),
    );
  }

  Widget _buildAuthenticatedBody(
    SocialPalette palette,
    AuthController auth,
    WatchlistController wl,
  ) {
    final filtered = _applyFilter(wl.watchlist);

    return RefreshIndicator(
      color: SocialTokens.cyan,
      onRefresh: () => wl.loadWatchlist(auth.token),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // Summary bento (only when there's anything to summarize)
          if (wl.watchlist.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _SummaryBento(
                  palette: palette,
                  watchlist: wl.watchlist,
                ),
              ),
            ),
          // Filter chips
          if (wl.watchlist.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
                child: _FilterChips(
                  palette: palette,
                  selected: _selectedFilter,
                  onSelect: (f) {
                    HapticUtils.lightTap();
                    setState(() => _selectedFilter = f);
                  },
                ),
              ),
            ),
          // Section header
          if (wl.watchlist.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
                child: _SectionHeader(
                  palette: palette,
                  eyebrow: _selectedFilter == null
                      ? 'watchlist.all'.tr
                      : _filterDisplay(_selectedFilter!),
                  title: 'watchlist.following'.tr,
                  count: filtered.length,
                ),
              ),
            ),
          // Body content
          if (wl.isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(color: SocialTokens.cyan),
              ),
            )
          else if (wl.watchlist.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(palette: palette),
            )
          else if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _NoMatchesState(palette: palette),
            )
          else
            // iPad: 2–3 columns; phone: unchanged single column.
            sliverResponsiveCards(
              context: context,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final item = filtered[i];
                return _WatchlistRow(
                  palette: palette,
                  item: item,
                  onTap: () => _openStock(item),
                  onRemove: () => _confirmRemove(auth, wl, item),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // ── filter / actions ─────────────────────────────────────────────────────

  List<Map<String, dynamic>> _applyFilter(
    List<Map<String, dynamic>> watchlist,
  ) {
    if (_selectedFilter == null) return watchlist;
    return watchlist.where((item) {
      final stock = item['stock'] as Map<String, dynamic>?;
      if (stock == null) return false;
      final shariah = stock['shariah_status'] as Map<String, dynamic>?;
      final grade = shariah?['grade']?.toString().toUpperCase() ?? '';
      // Watchlist filters by grade A/B/C/F only.
      return grade == _selectedFilter;
    }).toList();
  }

  String _filterDisplay(String f) {
    switch (f) {
      case 'A':
        return 'watchlist.gradeA'.tr;
      case 'B':
        return 'watchlist.gradeB'.tr;
      case 'C':
        return 'watchlist.gradeC'.tr;
      case 'F':
        return 'watchlist.gradeF'.tr;
      default:
        return 'watchlist.all'.tr;
    }
  }

  void _openStock(Map<String, dynamic> item) {
    final stock = item['stock'] as Map<String, dynamic>?;
    if (stock == null) return;
    HapticUtils.lightTap();
    final ticker = stock['ticker']?.toString() ?? '';
    final exchange = stock['exchange']?.toString() ?? '';
    if (ticker.isEmpty || exchange.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StockDetailScreen(ticker: ticker, exchange: exchange),
      ),
    );
  }

  Future<void> _confirmRemove(
    AuthController auth,
    WatchlistController wl,
    Map<String, dynamic> item,
  ) async {
    HapticUtils.lightTap();
    final confirmed = await PlatformDialog.show(
      context: context,
      title: 'watchlist.removeTitle'.tr,
      content: 'watchlist.removeConfirm'.tr,
      confirmText: 'common.remove'.tr,
      cancelText: 'common.cancel'.tr,
      isDestructive: true,
    );
    if (confirmed == true && mounted) {
      await HapticUtils.success();
      await wl.removeFromWatchlist(auth.token, item['stock_id']);
    }
  }
}

// ============================================================================
// Summary bento (Total · Halal · Mixed)
// ============================================================================
class _SummaryBento extends StatelessWidget {
  final SocialPalette palette;
  final List<Map<String, dynamic>> watchlist;

  const _SummaryBento({
    required this.palette,
    required this.watchlist,
  });

  @override
  Widget build(BuildContext context) {
    final total = watchlist.length;
    int halal = 0;
    int mixed = 0;
    for (final item in watchlist) {
      final s = (item['stock'] as Map<String, dynamic>?)?['shariah_status']
          as Map<String, dynamic>?;
      final status = s?['status']?.toString().toUpperCase() ?? '';
      if (status == 'HALAL') halal++;
      if (status == 'MIXED') mixed++;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _statCell(
              icon: Icons.bookmark_rounded,
              accent: SocialTokens.cyan,
              value: '$total',
              label: 'watchlist.total'.tr,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCell(
              icon: Icons.verified_rounded,
              accent: SocialTokens.up,
              value: '$halal',
              label: 'watchlist.halal'.tr,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCell(
              icon: Icons.balance_rounded,
              accent: SocialTokens.gold,
              value: '$mixed',
              label: 'watchlist.mixed'.tr,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCell({
    required IconData icon,
    required Color accent,
    required String value,
    required String label,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 3, color: accent),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: accent, size: 18),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Filter chips
// ============================================================================
class _FilterChips extends StatelessWidget {
  final SocialPalette palette;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _FilterChips({
    required this.palette,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    // Filter set — All + the four grades A/B/C/F.
    final entries = <_FilterEntry>[
      _FilterEntry(
        null,
        'watchlist.all'.tr,
        Icons.apps_rounded,
        SocialTokens.cyan,
      ),
      _FilterEntry(
        'A',
        'watchlist.gradeA'.tr,
        Icons.star_rounded,
        const Color(0xFF10B981), // green (gradeA)
      ),
      _FilterEntry(
        'B',
        'watchlist.gradeB'.tr,
        Icons.star_half_rounded,
        const Color(0xFF84CC16), // lime (gradeB)
      ),
      _FilterEntry(
        'C',
        'watchlist.gradeC'.tr,
        Icons.star_outline_rounded,
        const Color(0xFFF59E0B), // amber (gradeC)
      ),
      _FilterEntry(
        'F',
        'watchlist.gradeF'.tr,
        Icons.warning_amber_rounded,
        const Color(0xFFEF4444), // red (gradeF)
      ),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final e = entries[i];
          final isSelected = selected == e.code;
          return GestureDetector(
            onTap: () => onSelect(e.code),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? e.accent.withValues(alpha: 0.18)
                    : palette.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected ? e.accent : palette.border,
                  width: isSelected ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    e.icon,
                    size: 13,
                    color: isSelected ? e.accent : palette.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    e.label,
                    style: TextStyle(
                      color: isSelected ? e.accent : palette.textSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterEntry {
  final String? code;
  final String label;
  final IconData icon;
  final Color accent;
  const _FilterEntry(this.code, this.label, this.icon, this.accent);
}

// ============================================================================
// Section header
// ============================================================================
class _SectionHeader extends StatelessWidget {
  final SocialPalette palette;
  final String eyebrow;
  final String title;
  final int count;

  const _SectionHeader({
    required this.palette,
    required this.eyebrow,
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [SocialTokens.cyan, SocialTokens.cyanSoft],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: const TextStyle(
                  color: SocialTokens.cyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.4,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.border),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Watchlist row — wraps StockCard with a floating remove button
// ============================================================================
class _WatchlistRow extends StatelessWidget {
  final SocialPalette palette;
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _WatchlistRow({
    required this.palette,
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final stock = item['stock'] as Map<String, dynamic>?;

    // When the stock object isn't expanded by the API (legacy shape), render
    // a slim placeholder card with just the ID so the user can still remove.
    if (stock == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SocialTokens.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.help_outline_rounded,
                  color: SocialTokens.cyan,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'watchlist.stockId'.trParams({
                    'id': '${item['stock_id']}',
                  }),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: SocialTokens.down.withValues(alpha: 0.85),
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          StockCard(stock: stock),
          // Floating filled-star button (top-right corner) — tap to remove.
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: SocialTokens.gold.withValues(alpha: 0.20),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onRemove,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.star_rounded,
                    color: SocialTokens.gold,
                    size: 18,
                  ),
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
// Empty state — authenticated but no items
// ============================================================================
class _EmptyState extends StatelessWidget {
  final SocialPalette palette;
  const _EmptyState({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: SocialTokens.gold.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.star_rounded,
                color: SocialTokens.gold,
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'watchlist.noFollowed'.tr,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'watchlist.startFollowing'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.explore_rounded, size: 18),
              label: Text(
                'watchlist.exploreStocks'.tr,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: SocialTokens.cyan,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// "No matches" state — has items but the active filter excluded them all
// ============================================================================
class _NoMatchesState extends StatelessWidget {
  final SocialPalette palette;
  const _NoMatchesState({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: SocialTokens.cyan.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.filter_alt_off_rounded,
                color: SocialTokens.cyan,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'watchlist.noMatches'.tr,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'watchlist.tryDifferentFilter'.tr,
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Unauth state — not signed in
// ============================================================================
class _UnauthState extends StatelessWidget {
  final SocialPalette palette;
  const _UnauthState({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: palette.heroGradient(),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: SocialTokens.gold.withValues(alpha: 0.4),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: SocialTokens.gold.withValues(
                  alpha: palette.isDark ? 0.18 : 0.10,
                ),
                blurRadius: 26,
                spreadRadius: -4,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SocialTokens.gold.withValues(alpha: 0.18),
                  border: Border.all(
                    color: SocialTokens.gold.withValues(alpha: 0.5),
                    width: 1.4,
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.star_rounded,
                  color: SocialTokens.gold,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'watchlist.title'.tr,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'watchlist.signInSubtitle'.tr,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await HapticUtils.lightTap();
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: Text(
                    'watchlist.signIn'.tr,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SocialTokens.gold,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
