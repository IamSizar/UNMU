import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/stocks_provider.dart';
import '../../localization/app_localizations.dart';
import '../../widgets/fear_and_greed_card.dart';
import '../../widgets/index_card.dart';
import '../../widgets/platform_adaptive/platform_app_bar.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/ads/banner_ad_widget.dart';
import '../../widgets/platform_adaptive/platform_refresh_indicator.dart';

class IndexesScreen extends StatefulWidget {
  const IndexesScreen({super.key});

  @override
  State<IndexesScreen> createState() => _IndexesScreenState();
}

class _IndexesScreenState extends State<IndexesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      final isPremium = context.read<AuthProvider>().isPremium;
      context.read<StocksProvider>().startMarketUpdates(isPremium);
    });
  }

  @override
  void dispose() {
    // Avoid accessing context during dispose directly if possible,
    // but here we are in a State, we can use the provider.
    // To be safe, we check if it's still mounted or just call it.
    try {
      if (mounted) {
        context.read<StocksProvider>().stopMarketUpdates();
      }
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadData() async {
    final provider = context.read<StocksProvider>();
    await Future.wait([
      provider.loadMarketSentiment(),
      provider.loadMarketIndexes(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: PlatformAppBar(title: l10n.indexes),
      body: Consumer<StocksProvider>(
        builder: (context, provider, child) {
          final categories = _groupIndexes(provider.marketIndexes);

          return PlatformRefreshIndicator(
            onRefresh: _loadData,
            slivers: [
              SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 16),
                    const FearAndGreedCard(),
                    const SizedBox(height: 24),

                    // Banner Ad for Free Users
                    if (!context.watch<AuthProvider>().isPremium)
                      const BannerAdWidget(),

                    ...categories.entries.map((entry) {
                      // For free users, only show Benchmarks
                      final isPremium = context.watch<AuthProvider>().isPremium;
                      if (!isPremium && entry.key != 'Benchmarks') {
                        return const SizedBox.shrink();
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Text(
                              _localizeCategory(
                                context,
                                entry.key,
                              ).toUpperCase(),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          ...entry.value.map(
                            (index) => IndexCard(index: index),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }),

                    // Upsell for Free Users if content is hidden
                    if (!context.watch<AuthProvider>().isPremium) ...[
                      const SizedBox(height: 24),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.lock,
                                color: Colors.grey,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                l10n.upgradeToUnlock,
                                style: theme.textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 100), // Bottom padding for tab bar
                  ]),
                ),
            ],
          );
        },
      ),
    );
  }

  String _localizeCategory(BuildContext context, String key) {
    final l10n = AppLocalizations(context);
    switch (key.toLowerCase()) {
      case 'benchmarks':
        return l10n.benchmarks;
      case 'macro':
        return l10n.macro;
      case 'health':
        return l10n.health;
      case 'global':
        return l10n.regionGlobal;
      default:
        return key;
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupIndexes(
    List<Map<String, dynamic>> indexes,
  ) {
    // Keep categories in specific order
    final order = ['Benchmarks', 'Health', 'Global', 'Macro'];
    final Map<String, List<Map<String, dynamic>>> groups = {};

    for (var cat in order) {
      final items = indexes.where((idx) => idx['category'] == cat).toList();
      if (items.isNotEmpty) {
        groups[cat] = items;
      }
    }

    // Add any remaining categories
    for (var idx in indexes) {
      final cat = idx['category']?.toString() ?? 'Other';
      if (!order.contains(cat)) {
        groups.putIfAbsent(cat, () => []).add(idx);
      }
    }

    return groups;
  }
}
