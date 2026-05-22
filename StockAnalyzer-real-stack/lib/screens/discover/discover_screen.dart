import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../providers/stocks_provider.dart';
import '../../localization/app_localizations.dart';
import '../../widgets/stock_card.dart';
import '../../widgets/platform_adaptive/platform_app_bar.dart';
import '../../widgets/platform_adaptive/platform_button.dart';
import '../../screens/discover/search_screen.dart';
import '../../screens/stock_detail/stock_detail_screen.dart';
import '../../utils/platform_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../theme/halal_fintech_theme.dart';
import '../../widgets/region_filter_button.dart';
import '../../widgets/ads/banner_ad_widget.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _selectedFilter; // null = ALL, 'HALAL', 'HARAM', 'UNKNOWN'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StocksProvider>().loadStocksByRegion('GLOBAL');
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildHeaderCard(BuildContext context, StocksProvider provider) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations(context);
    final isDark = theme.brightness == Brightness.dark;
    final displayedStocks = provider.stocks;
    final totalStocks = displayedStocks.length;
    final halalCount = displayedStocks.where((s) {
      final status = s['shariah_status']?['status']?.toString() ?? '';
      return status.toUpperCase() == 'HALAL';
    }).length;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF1A4D3A), const Color(0xFF0F3D2E)]
              : [const Color(0xFFD1FAE5), const Color(0xFFA7F3D0)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: HalalFintechTheme.accentGreen.withValues(alpha: 0.5),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          // Green accent glow
          BoxShadow(
            color: HalalFintechTheme.accentGreen.withValues(alpha: 0.25),
            blurRadius: 16,
            spreadRadius: -4,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.totalStocks,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white70 : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$totalStocks',
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 32,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.trending_up,
                  color: isDark ? Colors.white : Colors.black87,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  l10n.gradeA,
                  '$halalCount',
                  Icons.verified,
                  isDark,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatItem(
                  context,
                  l10n.available,
                  '${totalStocks - halalCount}',
                  Icons.inventory_2,
                  isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    bool isDark,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isDark ? Colors.white70 : Colors.black87),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final l10n = AppLocalizations(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<StocksProvider>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Search Button - Glassmorphism
          Expanded(
            child: _buildGlassmorphismButton(
              context: context,
              label: l10n.search,
              onTap: () async {
                await HapticUtils.lightTap();
                if (!context.mounted) return;
                if (PlatformUtils.isIOS) {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(builder: (_) => const SearchScreen()),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchScreen()),
                  );
                }
              },
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 12),
          // Filter Button - Glassmorphism with popup menu
          Expanded(
            child: _buildFilterGlassmorphismButton(
              context,
              l10n,
              isDark,
              provider,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassmorphismButton({
    required BuildContext context,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: HalalFintechTheme.accentGreen.withValues(alpha: 0.6),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
              // Green accent glow
              BoxShadow(
                color: HalalFintechTheme.accentGreen.withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: -2,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterGlassmorphismButton(
    BuildContext context,
    AppLocalizations l10n,
    bool isDark,
    StocksProvider provider,
  ) {
    final filterLabel = _selectedFilter != null
        ? _getFilterLabel(context, _selectedFilter!)
        : l10n.filter;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: HalalFintechTheme.accentGreen.withValues(alpha: 0.6),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
              // Green accent glow
              BoxShadow(
                color: HalalFintechTheme.accentGreen.withValues(alpha: 0.3),
                blurRadius: 12,
                spreadRadius: -2,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                await HapticUtils.lightTap();
                if (!context.mounted) return;

                if (PlatformUtils.isIOS) {
                  await showCupertinoModalPopup(
                    context: context,
                    builder: (context) => CupertinoActionSheet(
                      actions: [
                        CupertinoActionSheetAction(
                          onPressed: () {
                            Navigator.pop(context);
                            HapticUtils.lightTap();
                            setState(() => _selectedFilter = null);
                            provider.filterByStatus(null);
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_selectedFilter == null) ...[
                                const Icon(CupertinoIcons.check_mark, size: 18),
                                const SizedBox(width: 8),
                              ],
                              Text(l10n.all),
                            ],
                          ),
                        ),
                        CupertinoActionSheetAction(
                          onPressed: () {
                            Navigator.pop(context);
                            HapticUtils.lightTap();
                            setState(() => _selectedFilter = 'HALAL');
                            provider.filterByStatus('HALAL');
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_selectedFilter == 'HALAL') ...[
                                const Icon(CupertinoIcons.check_mark, size: 18),
                                const SizedBox(width: 8),
                              ],
                              Text(l10n.halal),
                            ],
                          ),
                        ),
                        CupertinoActionSheetAction(
                          onPressed: () {
                            Navigator.pop(context);
                            HapticUtils.lightTap();
                            setState(() => _selectedFilter = 'HARAM');
                            provider.filterByStatus('HARAM');
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_selectedFilter == 'HARAM') ...[
                                const Icon(CupertinoIcons.check_mark, size: 18),
                                const SizedBox(width: 8),
                              ],
                              Text(l10n.haram),
                            ],
                          ),
                        ),
                        CupertinoActionSheetAction(
                          onPressed: () {
                            Navigator.pop(context);
                            HapticUtils.lightTap();
                            setState(() => _selectedFilter = 'MIXED');
                            provider.filterByStatus('MIXED');
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_selectedFilter == 'MIXED') ...[
                                const Icon(CupertinoIcons.check_mark, size: 18),
                                const SizedBox(width: 8),
                              ],
                              Text(l10n.mixed),
                            ],
                          ),
                        ),
                        CupertinoActionSheetAction(
                          onPressed: () {
                            Navigator.pop(context);
                            HapticUtils.lightTap();
                            setState(() => _selectedFilter = 'UNKNOWN');
                            provider.filterByStatus('UNKNOWN');
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_selectedFilter == 'UNKNOWN') ...[
                                const Icon(CupertinoIcons.check_mark, size: 18),
                                const SizedBox(width: 8),
                              ],
                              Text(l10n.unknown),
                            ],
                          ),
                        ),
                      ],
                      cancelButton: CupertinoActionSheetAction(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n.cancel),
                      ),
                    ),
                  );
                } else {
                  final RenderBox? renderBox =
                      context.findRenderObject() as RenderBox?;
                  final Offset offset =
                      renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;

                  await showMenu(
                    context: context,
                    position: RelativeRect.fromLTRB(
                      offset.dx,
                      offset.dy + 48,
                      offset.dx + (renderBox?.size.width ?? 0),
                      offset.dy + 48 + (renderBox?.size.height ?? 0),
                    ),
                    items: [
                      PopupMenuItem(
                        child: Row(
                          children: [
                            if (_selectedFilter == null) ...[
                              const Icon(Icons.check, size: 18),
                              const SizedBox(width: 8),
                            ],
                            Text(l10n.all),
                          ],
                        ),
                        onTap: () {
                          setState(() => _selectedFilter = null);
                          provider.filterByStatus(null);
                        },
                      ),
                      PopupMenuItem(
                        child: Row(
                          children: [
                            if (_selectedFilter == 'HALAL') ...[
                              const Icon(Icons.check, size: 18),
                              const SizedBox(width: 8),
                            ],
                            Text(l10n.halal),
                          ],
                        ),
                        onTap: () {
                          setState(() => _selectedFilter = 'HALAL');
                          provider.filterByStatus('HALAL');
                        },
                      ),
                      PopupMenuItem(
                        child: Row(
                          children: [
                            if (_selectedFilter == 'HARAM') ...[
                              const Icon(Icons.check, size: 18),
                              const SizedBox(width: 8),
                            ],
                            Text(l10n.haram),
                          ],
                        ),
                        onTap: () {
                          setState(() => _selectedFilter = 'HARAM');
                          provider.filterByStatus('HARAM');
                        },
                      ),
                      PopupMenuItem(
                        child: Row(
                          children: [
                            if (_selectedFilter == 'MIXED') ...[
                              const Icon(Icons.check, size: 18),
                              const SizedBox(width: 8),
                            ],
                            Text(l10n.mixed),
                          ],
                        ),
                        onTap: () {
                          setState(() => _selectedFilter = 'MIXED');
                          provider.filterByStatus('MIXED');
                        },
                      ),
                      PopupMenuItem(
                        child: Row(
                          children: [
                            if (_selectedFilter == 'UNKNOWN') ...[
                              const Icon(Icons.check, size: 18),
                              const SizedBox(width: 8),
                            ],
                            Text(l10n.unknown),
                          ],
                        ),
                        onTap: () {
                          setState(() => _selectedFilter = 'UNKNOWN');
                          provider.filterByStatus('UNKNOWN');
                        },
                      ),
                    ],
                  );
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Center(
                child: Text(
                  filterLabel,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getFilterLabel(BuildContext context, String status) {
    final l10n = AppLocalizations(context);
    switch (status.toUpperCase()) {
      case 'HALAL':
        return l10n.halal;
      case 'HARAM':
        return l10n.haram;
      case 'UNKNOWN':
        return l10n.unknown;
      default:
        return l10n.filter;
    }
  }

  // Removed _showFilterDialog and _buildFilterOption - now using CNPopupMenuButton instead

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: PlatformAppBar(
        title: l10n.discover,
        leading: PlatformUtils.isIOS
            ? Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Consumer<StocksProvider>(
                  builder: (context, provider, _) {
                    final currentRegion = provider.selectedRegion.isNotEmpty
                        ? provider.selectedRegion
                        : 'GLOBAL';

                    return RegionFilterButton(
                      selectedRegion: currentRegion,
                      onRegionSelected: (code) {
                        setState(() => _selectedFilter = null);
                        provider.loadStocksByRegion(code);
                      },
                    );
                  },
                ),
              )
            : null,
      ),
      body: Consumer<StocksProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return Center(
              child: PlatformUtils.isIOS
                  ? const CupertinoActivityIndicator()
                  : const CircularProgressIndicator(),
            );
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(provider.error!),
                  const SizedBox(height: 16),
                  PlatformButton(
                    label: l10n.retry,
                    onPressed: () =>
                        provider.loadStocksByRegion(provider.selectedRegion),
                  ),
                ],
              ),
            );
          }

          if (provider.stocks.isEmpty) {
            return Center(
              child: Text(l10n.empty, style: theme.textTheme.bodyLarge),
            );
          }

          if (PlatformUtils.isIOS) {
            return CupertinoScrollbar(
              controller: _scrollController,
              child: CustomScrollView(
                controller: _scrollController,
                primary: false,
                slivers: [
                  CupertinoSliverRefreshControl(
                    onRefresh: () async {
                      await provider.loadStocksByRegion(
                        provider.selectedRegion,
                      );
                      if (_selectedFilter != null) {
                        provider.filterByStatus(_selectedFilter);
                      }
                    },
                  ),
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _buildHeaderCard(context, provider),
                        // Removed FearAndGreedCard from here as it moved to Indexes tab
                        const SizedBox(height: 8),
                        const BannerAdWidget(),
                        const SizedBox(height: 8),
                        _buildActionButtons(context),
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                l10n.allStocks,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                              const Icon(CupertinoIcons.search, size: 18),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final stock = provider.stocks[index];
                      return GestureDetector(
                        onTap: () async {
                          await HapticUtils.lightTap();
                          if (!context.mounted) return;
                          final ticker = stock['ticker']?.toString() ?? '';
                          final exchange = stock['exchange']?.toString() ?? '';
                          if (ticker.isNotEmpty && exchange.isNotEmpty) {
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (_) => StockDetailScreen(
                                  ticker: ticker,
                                  exchange: exchange,
                                ),
                              ),
                            );
                          }
                        },
                        child: StockCard(stock: stock),
                      );
                    }, childCount: provider.stocks.length),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            );
          } else {
            return RefreshIndicator(
              onRefresh: () async {
                await provider.loadStocksByRegion(provider.selectedRegion);
                if (_selectedFilter != null) {
                  provider.filterByStatus(_selectedFilter);
                }
              },
              child: ListView(
                controller: _scrollController,
                padding: EdgeInsets.zero,
                children: [
                  _buildHeaderCard(context, provider),
                  const SizedBox(height: 8),
                  _buildActionButtons(context),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.allStocks,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Icon(
                          Icons.search,
                          size: 20,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...provider.stocks.map((stock) {
                    return InkWell(
                      onTap: () async {
                        await HapticUtils.lightTap();
                        if (!context.mounted) return;
                        final ticker = stock['ticker']?.toString() ?? '';
                        final exchange = stock['exchange']?.toString() ?? '';
                        if (ticker.isNotEmpty && exchange.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StockDetailScreen(
                                ticker: ticker,
                                exchange: exchange,
                              ),
                            ),
                          );
                        }
                      },
                      child: StockCard(stock: stock),
                    );
                  }),
                  const SizedBox(height: 100),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}
