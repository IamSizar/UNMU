import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/portfolio_controller.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/api_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/platform_adaptive/platform_dialog.dart';

/// Portfolio screen — the user's real, valued holdings (shares + average
/// buy price), distinct from the Watchlist (which tracks stocks without a
/// position). Backed by the same `GET/POST/DELETE /api/user/portfolio`
/// endpoints as the watchlist; [PortfolioController] filters to rows that
/// actually carry shares > 0.
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
      builder: (_) => _AddHoldingSheet(token: token),
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
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
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

/// Bottom sheet: search a stock, enter shares + avg buy price, save.
class _AddHoldingSheet extends StatefulWidget {
  const _AddHoldingSheet({required this.token});

  final String token;

  @override
  State<_AddHoldingSheet> createState() => _AddHoldingSheetState();
}

class _AddHoldingSheetState extends State<_AddHoldingSheet> {
  final _searchController = TextEditingController();
  final _sharesController = TextEditingController();
  final _priceController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selected;
  bool _saving = false;
  bool _searching = false;
  String? _saveError;
  Timer? _debounce;
  int _searchRequestId = 0;

  bool get _isValid {
    if (_selected == null) return false;
    final shares = double.tryParse(_sharesController.text);
    final price = double.tryParse(_priceController.text);
    return shares != null && shares > 0 && price != null && price > 0;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _sharesController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    final requestId = ++_searchRequestId;
    setState(() => _searching = true);
    final results = await ApiService.searchStocks(query.trim());
    // A faster later keystroke may have already started a newer request —
    // drop this response if it's not the most recent one, so a slow query
    // for "A" can't overwrite the results for "AAPL" typed right after it.
    if (!mounted || requestId != _searchRequestId) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  Future<void> _save() async {
    if (!_isValid) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final ok = await Get.find<PortfolioController>().addHolding(
      widget.token,
      (_selected!['id'] as num).toInt(),
      double.parse(_sharesController.text),
      double.parse(_priceController.text),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _saveError = 'portfolio.errorSaving'.tr;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'portfolio.addHolding'.tr,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                if (_selected == null) ...[
                  TextField(
                    controller: _searchController,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearchChanged,
                    style: TextStyle(color: palette.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search ticker or company…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: palette.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: palette.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_searching) const LinearProgressIndicator(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final s = _results[i];
                        return ListTile(
                          title: Text(
                            '${s['ticker'] ?? ''} — ${s['name'] ?? ''}',
                            style: TextStyle(color: palette.textPrimary),
                          ),
                          onTap: () => setState(() {
                            _selected = s;
                            _results = [];
                          }),
                        );
                      },
                    ),
                  ),
                ] else ...[
                  ListTile(
                    tileColor: palette.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    title: Text(
                      '${_selected!['ticker'] ?? ''} — ${_selected!['name'] ?? ''}',
                      style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _selected = null),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sharesController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: palette.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'portfolio.shares'.tr,
                      filled: true,
                      fillColor: palette.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: palette.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: palette.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'portfolio.avgBuyPrice'.tr,
                      prefixText: '\$ ',
                      filled: true,
                      fillColor: palette.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: palette.border),
                      ),
                    ),
                  ),
                  if (_saveError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _saveError!,
                      style: const TextStyle(color: SocialTokens.down, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _isValid && !_saving ? _save : null,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('portfolio.save'.tr),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
