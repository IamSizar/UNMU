import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/stocks_controller.dart';
import '../../screens/discover/search_screen.dart';
import '../../screens/social/social_tokens.dart';
import '../../screens/stock_detail/stock_detail_screen.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/responsive.dart';
import '../../widgets/ads/banner_ad_widget.dart';
import '../../widgets/stock_card.dart';
import '../../widgets/skeleton_loaders.dart';

/// =============================================================================
/// Discover Screen — editorial bento redesign.
///
///   ▸ Themed app bar (search, notifications)
///   ▸ Inline search pill (taps into the dedicated SearchScreen)
///   ▸ Horizontal region pills (GLOBAL / US / GCC / MENA / EU / ASIA / CN)
///   ▸ Bento stats strip — Total / Halal / Filtered (3 cells)
///   ▸ Filter chips — All / Halal / Mixed / Haram / Unknown
///   ▸ Section header "All stocks · count" with eyebrow
///   ▸ List of stock cards (existing StockCard widget kept)
///
/// Theme-reactive via [SocialTheme.of(context)].
/// =============================================================================
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  String? _selectedFilter; // null = ALL

  // Region catalogue used for the horizontal pills. `labelKey` is a GetX
  // translation key resolved at build time (`.tr`).
  static const List<_Region> _regions = [
    _Region('GLOBAL', 'discover.region.global', '🌍'),
    _Region('US', 'discover.region.us', '🇺🇸'),
    _Region('GCC', 'discover.region.gcc', '🕌'),
    _Region('MENA', 'discover.region.mena', '🌙'),
    _Region('EU', 'discover.region.eu', '🇪🇺'),
    _Region('ASIA', 'discover.region.asia', '🌏'),
    _Region('CN', 'discover.region.cn', '🇨🇳'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<StocksController>().loadStocksByRegion('GLOBAL');
    });
  }

  // ---- helpers -----------------------------------------------------------

  void _selectRegion(String code) {
    HapticUtils.lightTap();
    setState(() => _selectedFilter = null);
    Get.find<StocksController>().loadStocksByRegion(code);
  }

  void _selectStatusFilter(String? grade) {
    HapticUtils.lightTap();
    setState(() => _selectedFilter = grade);
    Get.find<StocksController>().filterByGrade(grade);
  }

  Future<void> _refresh() async {
    final p = Get.find<StocksController>();
    // force: true so pull-to-refresh always re-fetches (bypasses the cache).
    await p.loadStocksByRegion(p.selectedRegion, force: true);
    if (_selectedFilter != null) p.filterByGrade(_selectedFilter);
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'discover.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Obx(() {
        final provider = Get.find<StocksController>();
        return RefreshIndicator.adaptive(
            onRefresh: _refresh,
            color: SocialTokens.cyan,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                // ── Search pill ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _SearchPill(
                      palette: palette,
                      hint: 'discover.searchHint'.tr,
                      onTap: _openSearch,
                    ),
                  ),
                ),
                // ── Region pills ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
                    child: _RegionPills(
                      palette: palette,
                      selectedCode: provider.selectedRegion.isNotEmpty
                          ? provider.selectedRegion
                          : 'GLOBAL',
                      regions: _regions,
                      onSelect: _selectRegion,
                    ),
                  ),
                ),
                // ── Stats bento ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _StatsBento(
                      palette: palette,
                      provider: provider,
                    ),
                  ),
                ),
                // ── Banner ad (region-aware: shows the ad for the
                //    currently-selected region; GLOBAL ads show everywhere) ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: BannerAdWidget(
                      regionCode: provider.selectedRegion.isNotEmpty
                          ? provider.selectedRegion
                          : 'GLOBAL',
                    ),
                  ),
                ),
                // ── Filter chips ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                    child: _FilterChips(
                      palette: palette,
                      selected: _selectedFilter,
                      onSelect: _selectStatusFilter,
                    ),
                  ),
                ),
                // ── Section header ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: _SectionHeader(
                      palette: palette,
                      eyebrow: _selectedFilter == null
                          ? 'discover.all'.tr
                          : _filterLabel(_selectedFilter!),
                      title: 'discover.allStocks'.tr,
                      count: provider.stocks.length,
                    ),
                  ),
                ),
                // ── List body ──
                if (provider.isLoading)
                  // Shimmer skeletons that match the loaded StockCard layout —
                  // no content-shift, far nicer than a centered spinner.
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: StockListSkeleton(),
                    ),
                  )
                else if (provider.error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ErrorState(
                      palette: palette,
                      message: provider.error!,
                      onRetry: _refresh,
                      retryLabel: 'common.retry'.tr,
                    ),
                  )
                else if (provider.stocks.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(palette: palette, message: 'common.empty'.tr),
                  )
                else
                  // iPad: 2–3 columns of stock cards; phone: unchanged
                  // single column (helper returns a plain SliverList at 1 col).
                  sliverResponsiveCards(
                    context: context,
                    itemCount: provider.stocks.length,
                    itemBuilder: (_, i) {
                      final stock = provider.stocks[i];
                      return GestureDetector(
                        onTap: () => _openStock(stock),
                        child: StockCard(stock: stock),
                      );
                    },
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openSearch() {
    HapticUtils.lightTap();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
  }

  void _openStock(Map<String, dynamic> stock) {
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

  String _filterLabel(String grade) {
    switch (grade.toUpperCase()) {
      case 'A':
        return 'discover.gradeA'.tr;
      case 'B':
        return 'discover.gradeB'.tr;
      case 'C':
        return 'discover.gradeC'.tr;
      case 'F':
        return 'discover.gradeF'.tr;
      default:
        return 'discover.all'.tr;
    }
  }
}

class _Region {
  final String code;

  /// GetX translation key (resolve with `.tr`), not a literal label.
  final String label;
  final String emoji;
  const _Region(this.code, this.label, this.emoji);
}

// ============================================================================
// SearchPill — looks like a search field but is just a tap target that opens
// the dedicated SearchScreen.
// ============================================================================
class _SearchPill extends StatelessWidget {
  final SocialPalette palette;
  final String hint;
  final VoidCallback onTap;

  const _SearchPill({
    required this.palette,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SocialTokens.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.search_rounded,
                  color: SocialTokens.cyan,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  '⌘ K',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: 0.6,
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

// ============================================================================
// RegionPills — horizontal scrollable region selector.
// ============================================================================
class _RegionPills extends StatelessWidget {
  final SocialPalette palette;
  final String selectedCode;
  final List<_Region> regions;
  final ValueChanged<String> onSelect;

  const _RegionPills({
    required this.palette,
    required this.selectedCode,
    required this.regions,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: regions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final r = regions[i];
          final selected = r.code == selectedCode;
          final accent = SocialTokens.regionColor(r.code);
          return GestureDetector(
            onTap: () => onSelect(r.code),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.18)
                    : palette.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? accent : palette.border,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    r.emoji,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    r.label.tr,
                    style: TextStyle(
                      color: selected ? accent : palette.textSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
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

// ============================================================================
// StatsBento — Total / Halal / Filtered count
// ============================================================================
class _StatsBento extends StatelessWidget {
  final SocialPalette palette;
  final StocksController provider;

  const _StatsBento({
    required this.palette,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final stocks = provider.stocks;
    final total = stocks.length;
    int gradeA = 0;
    int gradeB = 0;
    for (final s in stocks) {
      final g = s['shariah_status']?['grade']?.toString().toUpperCase() ?? '';
      if (g == 'A') gradeA++;
      if (g == 'B') gradeB++;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _statCell(
              icon: Icons.dashboard_rounded,
              accent: SocialTokens.cyan,
              value: '$total',
              label: 'discover.totalStocks'.tr,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCell(
              icon: Icons.star_rounded,
              accent: const Color(0xFF10B981), // green = grade A
              value: '$gradeA',
              label: 'discover.gradeA'.tr,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCell(
              icon: Icons.star_half_rounded,
              accent: const Color(0xFF84CC16), // lime = grade B
              value: '$gradeB',
              label: 'discover.gradeB'.tr,
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
// FilterChips — All / Halal / Mixed / Haram / Unknown
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
    // Filter by Shariah grade (A/B/C/F) — same letter system used elsewhere
    // in the app. Replaces the older Halal/Mixed/Haram/Unknown chips.
    final entries = <_FilterEntry>[
      _FilterEntry(null, 'discover.all'.tr, Icons.apps_rounded, SocialTokens.cyan),
      _FilterEntry(
        'A',
        'discover.gradeA'.tr,
        Icons.star_rounded,
        const Color(0xFF10B981), // green
      ),
      _FilterEntry(
        'B',
        'discover.gradeB'.tr,
        Icons.star_half_rounded,
        const Color(0xFF84CC16), // lime
      ),
      _FilterEntry(
        'C',
        'discover.gradeC'.tr,
        Icons.star_outline_rounded,
        const Color(0xFFF59E0B), // amber
      ),
      _FilterEntry(
        'F',
        'discover.gradeF'.tr,
        Icons.warning_amber_rounded,
        const Color(0xFFEF4444), // red
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
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
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
// SectionHeader — eyebrow + title + count badge + accent stripe
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
// ErrorState
// ============================================================================
class _ErrorState extends StatelessWidget {
  final SocialPalette palette;
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;
  const _ErrorState({
    required this.palette,
    required this.message,
    required this.onRetry,
    required this.retryLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: SocialTokens.down.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: SocialTokens.down,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(
              retryLabel,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: SocialTokens.cyan,
              padding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 12,
              ),
              side: const BorderSide(color: SocialTokens.cyan, width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// EmptyState
// ============================================================================
class _EmptyState extends StatelessWidget {
  final SocialPalette palette;
  final String message;
  const _EmptyState({required this.palette, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
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
              Icons.inbox_outlined,
              color: SocialTokens.cyan,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textMuted, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}
