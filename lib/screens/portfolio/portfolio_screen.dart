import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/portfolio_controller.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/social/social_tokens.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/platform_adaptive/platform_dialog.dart';
import 'add_holding_sheet.dart';

/// Portfolio screen — the user's real, valued holdings (shares + average
/// buy price), distinct from the Watchlist (which tracks stocks without a
/// position). Backed by the same `GET/POST/DELETE /api/user/portfolio`
/// endpoints as the watchlist; [PortfolioController] filters to rows that
/// actually carry shares > 0. The add-holding flow lives in
/// add_holding_sheet.dart (split out to keep this file under 500 lines).
class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Get.find<AuthController>();
      if (auth.isAuthenticated) {
        Get.find<PortfolioController>().loadPortfolio(auth.token);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final auth = Get.find<AuthController>();
    final portfolio = Get.find<PortfolioController>();

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'portfolio.title'.tr,
          style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w800),
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
      ),
      floatingActionButton: auth.isAuthenticated
          ? FloatingActionButton.extended(
              onPressed: () => _showAddHoldingSheet(context, auth.token),
              icon: const Icon(Icons.add_rounded),
              label: Text('portfolio.addHolding'.tr),
            )
          : null,
      body: !auth.isAuthenticated
          ? _SignInPrompt(palette: palette)
          : Obx(() {
              if (portfolio.isLoading && portfolio.holdings.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (portfolio.error != null && portfolio.holdings.isEmpty) {
                return _ErrorState(
                  palette: palette,
                  onRetry: () => portfolio.loadPortfolio(auth.token),
                );
              }
              if (portfolio.holdings.isEmpty) {
                return _EmptyState(
                  palette: palette,
                  onAdd: () => _showAddHoldingSheet(context, auth.token),
                );
              }
              return RefreshIndicator(
                onRefresh: () => portfolio.loadPortfolio(auth.token),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    _SummaryCard(palette: palette, portfolio: portfolio),
                    const SizedBox(height: 16),
                    Text(
                      'portfolio.holdings'.tr,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...portfolio.holdings.map(
                      (h) => _HoldingCard(
                        palette: palette,
                        holding: h,
                        onRemove: () => _confirmRemove(context, auth.token, h),
                      ),
                    ),
                  ],
                ),
              );
            }),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    String? token,
    Map<String, dynamic> holding,
  ) async {
    final confirmed = await PlatformDialog.show(
      context: context,
      title: 'portfolio.removeTitle'.tr,
      content: 'portfolio.removeConfirm'.tr,
      confirmText: 'common.remove'.tr,
      cancelText: 'portfolio.cancel'.tr,
      isDestructive: true,
    );
    if (confirmed != true) return;
    HapticUtils.lightTap();
    final stockId = (holding['stock_id'] as num).toInt();
    await Get.find<PortfolioController>().removeHolding(token, stockId);
  }

  Future<void> _showAddHoldingSheet(BuildContext context, String? token) async {
    if (token == null) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddHoldingSheet(token: token),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.palette, required this.portfolio});

  final SocialPalette palette;
  final PortfolioController portfolio;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'portfolio.totalValue'.tr,
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${portfolio.totalCostBasis.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${portfolio.holdings.length}',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldingCard extends StatelessWidget {
  const _HoldingCard({
    required this.palette,
    required this.holding,
    required this.onRemove,
  });

  final SocialPalette palette;
  final Map<String, dynamic> holding;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final stock = holding['stock'] as Map<String, dynamic>?;
    final shariah = stock?['shariah_status'] as Map<String, dynamic>?;
    final shares = (holding['shares'] as num?)?.toDouble() ?? 0;
    final avgPrice = (holding['avg_buy_price'] as num?)?.toDouble() ?? 0;
    final status = (shariah?['status'] as String?) ?? 'UNKNOWN';
    final statusColor = switch (status) {
      'HALAL' => SocialTokens.up,
      'HARAM' => SocialTokens.down,
      _ => SocialTokens.gold,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (stock?['ticker'] as String?) ?? '—',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${shares.toStringAsFixed(2)} sh @ \$${avgPrice.toStringAsFixed(2)}',
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '\$${(shares * avgPrice).toStringAsFixed(2)}',
            style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: palette.textSecondary, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette, required this.onAdd});

  final SocialPalette palette;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pie_chart_outline_rounded, size: 56, color: palette.textSecondary),
            const SizedBox(height: 16),
            Text(
              'portfolio.noHoldings'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'portfolio.startAdding'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text('portfolio.addHolding'.tr),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.palette, required this.onRetry});

  final SocialPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: SocialTokens.down),
            const SizedBox(height: 16),
            Text(
              'portfolio.errorLoading'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: Text('common.refresh'.tr)),
          ],
        ),
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.palette});

  final SocialPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'portfolio.signInSubtitle'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
              child: Text('watchlist.signIn'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
