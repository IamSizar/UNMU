import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/stocks_controller.dart';
import '../../widgets/fear_and_greed_card.dart';
import '../../widgets/index_card.dart';
import '../../widgets/skeleton_loaders.dart';
import '../../widgets/platform_adaptive/platform_app_bar.dart';
import '../../controllers/auth_controller.dart';
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
      // Indexes are now free for everyone (May 2026 brand refresh — the
      // paywall on Benchmarks/Health/Global/Macro categories was lifted
      // so the discovery surface stays open). We still feed the
      // controller a "premium" flag for the live-update cadence; pass
      // `true` here so all users get the same realtime refresh rate as
      // paying users did before.
      Get.find<StocksController>().startMarketUpdates(true);
    });
  }

  @override
  void dispose() {
    // Avoid accessing context during dispose directly if possible,
    // but here we are in a State, we can use the provider.
    // To be safe, we check if it's still mounted or just call it.
    try {
      if (mounted) {
        Get.find<StocksController>().stopMarketUpdates();
      }
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadData() async {
    final provider = Get.find<StocksController>();
    await Future.wait([
      provider.loadMarketSentiment(),
      provider.loadMarketIndexes(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: PlatformAppBar(title: 'indexes.title'.tr),
      body: Obx(() {
        final provider = Get.find<StocksController>();
        final categories = _groupIndexes(provider.marketIndexes);

        return PlatformRefreshIndicator(
            onRefresh: _loadData,
            slivers: [
              SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 16),
                    const FearAndGreedCard(),
                    const SizedBox(height: 24),

                    // Banner ad still shows for non-premium users — the
                    // indexes content itself is free, but the ad keeps a
                    // gentle upsell present without locking any data.
                    if (!Get.find<AuthController>().isPremium)
                      const BannerAdWidget(),

                    // All four index categories (Benchmarks, Health, Global,
                    // Macro) are now visible to every user. Previously the
                    // free tier only saw "Benchmarks" with a lock-icon
                    // upsell card below; that gating was removed so the
                    // indexes surface is fully open.
                    // Loading: marketIndexes is empty until the first fetch
                    // resolves — show shimmer skeletons that match the loaded
                    // layout (no content-shift) instead of blank space.
                    if (provider.marketIndexes.isEmpty)
                      const IndexListSkeleton()
                    else
                      ...categories.entries.map((entry) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Text(
                                _localizeCategory(entry.key).toUpperCase(),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            // Stagger the real cards in (Framer-Motion
                            // staggerChildren) for a polished reveal once
                            // data arrives.
                            ...entry.value.asMap().entries.map(
                                  (e) => StaggeredReveal(
                                    index: e.key,
                                    child: IndexCard(index: e.value),
                                  ),
                                ),
                            const SizedBox(height: 16),
                          ],
                        );
                      }),

                    const SizedBox(height: 100), // Bottom padding for tab bar
                  ]),
                ),
            ],
          );
        },
      ),
    );
  }

  String _localizeCategory(String key) {
    switch (key.toLowerCase()) {
      case 'benchmarks':
        return 'indexes.category.benchmarks'.tr;
      case 'macro':
        return 'indexes.category.macro'.tr;
      case 'health':
        return 'indexes.category.health'.tr;
      case 'global':
        return 'indexes.category.global'.tr;
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
