import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../providers/watchlist_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../localization/halal_strings.dart';
import '../../widgets/stock_card.dart';
import '../../widgets/platform_adaptive/platform_app_bar.dart';
import '../../widgets/platform_adaptive/platform_button.dart';
import '../../widgets/platform_adaptive/platform_dialog.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/stock_detail/stock_detail_screen.dart';
import '../../utils/platform_utils.dart';
import '../../utils/haptic_utils.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      if (authProvider.isAuthenticated) {
        context.read<WatchlistProvider>().loadWatchlist(authProvider.token);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.watch<LanguageProvider>().isArabic;
    // Using static strings directly
    final authProvider = context.watch<AuthProvider>();
    final watchlistProvider = context.watch<WatchlistProvider>();

    if (!authProvider.isAuthenticated) {
      return Scaffold(
        appBar: PlatformAppBar(
          title: isArabic ? HalalStringsAr.watchlist : HalalStrings.watchlist,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                PlatformUtils.isIOS ? CupertinoIcons.star : Icons.star_border,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                isArabic ? HalalStringsAr.myWatchlist : HalalStrings.myWatchlist,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                isArabic ? HalalStringsAr.startFollowing : HalalStrings.startFollowing,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              PlatformButton(
                label: isArabic ? 'تسجيل الدخول' : 'Login',
                onPressed: () async {
                  await HapticUtils.lightTap();
                  if (!mounted) return;
                  if (PlatformUtils.isIOS) {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(builder: (_) => const LoginScreen()),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: PlatformAppBar(
        title: isArabic ? HalalStringsAr.myWatchlist : HalalStrings.myWatchlist,
      ),
      body: watchlistProvider.isLoading
          ? Center(
              child: PlatformUtils.isIOS
                  ? const CupertinoActivityIndicator()
                  : const CircularProgressIndicator(),
            )
          : watchlistProvider.watchlist.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        PlatformUtils.isIOS ? CupertinoIcons.star : Icons.star_border,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isArabic ? HalalStringsAr.noFollowedStocks : HalalStrings.noFollowedStocks,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isArabic ? HalalStringsAr.startFollowing : HalalStrings.startFollowing,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : PlatformUtils.isIOS
                  ? CupertinoScrollbar(
                      controller: _scrollController,
                      child: CustomScrollView(
                        controller: _scrollController,
                        primary: false,
                        slivers: [
                          CupertinoSliverRefreshControl(
                            onRefresh: () async {
                              await watchlistProvider.loadWatchlist(authProvider.token);
                            },
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.all(16),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final item = watchlistProvider.watchlist[index];
                                  final stock = item['stock'] as Map<String, dynamic>?;
                                  
                                  if (stock == null) {
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      child: ListTile(
                                        title: Text('Stock ID: ${item['stock_id']}'),
                                        subtitle: item['shares'] != null 
                                            ? Text('${isArabic ? 'الأسهم' : 'Shares'}: ${item['shares']}')
                                            : null,
                                        trailing: IconButton(
                                          icon: const Icon(Icons.star, color: Colors.amber),
                                          onPressed: () async {
                                            await watchlistProvider.removeFromWatchlist(
                                              authProvider.token,
                                              item['stock_id'],
                                            );
                                          },
                                        ),
                                      ),
                                    );
                                  }
                                  
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: GestureDetector(
                                      onTap: () async {
                                        await HapticUtils.lightTap();
                                        if (!mounted) return;
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
                                      child: Stack(
                                        children: [
                                          StockCard(stock: stock),
                                          Positioned(
                                            top: 8,
                                            right: 8,
                                            child: IconButton(
                                              icon: const Icon(Icons.star, color: Colors.amber),
                                              onPressed: () async {
                                                await HapticUtils.lightTap();
                                                if (!mounted) return;
                                                final confirmed = await PlatformDialog.show(
                                                  context: context,
                                                  title: isArabic ? 'إزالة من المتابعة' : 'Remove from Watchlist',
                                                  content: isArabic
                                                      ? 'هل تريد إزالة هذا السهم من قائمة المتابعة؟'
                                                      : 'Are you sure you want to remove this stock from your watchlist?',
                                                  confirmText: isArabic ? 'إزالة' : 'Remove',
                                                  cancelText: isArabic ? 'إلغاء' : 'Cancel',
                                                  isDestructive: true,
                                                );
                                                
                                                if (confirmed == true) {
                                                  await HapticUtils.success();
                                                  if (!mounted) return;
                                                  await watchlistProvider.removeFromWatchlist(
                                                    authProvider.token,
                                                    item['stock_id'],
                                                  );
                                                }
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                childCount: watchlistProvider.watchlist.length,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        await watchlistProvider.loadWatchlist(authProvider.token);
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: watchlistProvider.watchlist.length,
                        itemBuilder: (context, index) {
                          final item = watchlistProvider.watchlist[index];
                          final stock = item['stock'] as Map<String, dynamic>?;
                          
                          if (stock == null) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                title: Text('Stock ID: ${item['stock_id']}'),
                                subtitle: item['shares'] != null 
                                    ? Text('${isArabic ? 'الأسهم' : 'Shares'}: ${item['shares']}')
                                    : null,
                                trailing: IconButton(
                                  icon: const Icon(Icons.star, color: Colors.amber),
                                  onPressed: () async {
                                    await watchlistProvider.removeFromWatchlist(
                                      authProvider.token,
                                      item['stock_id'],
                                    );
                                  },
                                ),
                              ),
                            );
                          }
                          
                          return InkWell(
                            onTap: () async {
                              await HapticUtils.lightTap();
                              if (!mounted) return;
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
                            child: Stack(
                              children: [
                                StockCard(stock: stock),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: IconButton(
                                    icon: const Icon(Icons.star, color: Colors.amber),
                                    onPressed: () async {
                                      await HapticUtils.lightTap();
                                      if (!mounted) return;
                                      final confirmed = await PlatformDialog.show(
                                        context: context,
                                        title: isArabic ? 'إزالة من المتابعة' : 'Remove from Watchlist',
                                        content: isArabic
                                            ? 'هل تريد إزالة هذا السهم من قائمة المتابعة؟'
                                            : 'Are you sure you want to remove this stock from your watchlist?',
                                        confirmText: isArabic ? 'إزالة' : 'Remove',
                                        cancelText: isArabic ? 'إلغاء' : 'Cancel',
                                        isDestructive: true,
                                      );
                                      
                                      if (confirmed == true) {
                                        await HapticUtils.success();
                                        if (!mounted) return;
                                        await watchlistProvider.removeFromWatchlist(
                                          authProvider.token,
                                          item['stock_id'],
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

