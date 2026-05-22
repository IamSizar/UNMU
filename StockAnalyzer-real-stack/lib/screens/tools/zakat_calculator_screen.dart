import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../localization/app_localizations.dart';
import 'package:flutter/services.dart';
import '../../utils/haptic_utils.dart';
import '../../providers/currency_provider.dart';
import '../../providers/language_provider.dart';
import '../../services/api_service.dart';
import '../../theme/halal_fintech_theme.dart';
import '../../widgets/platform_adaptive/platform_app_bar.dart';
import '../../widgets/platform_adaptive/platform_button.dart';

class ZakatCalculatorScreen extends StatefulWidget {
  const ZakatCalculatorScreen({super.key});

  @override
  State<ZakatCalculatorScreen> createState() => _ZakatCalculatorScreenState();
}

class _ZakatCalculatorScreenState extends State<ZakatCalculatorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Manual Calculation State
  final _cashController = TextEditingController();
  final _goldController = TextEditingController();
  final _sharesController = TextEditingController();
  final _otherController = TextEditingController();
  double _manualTotalZakat = 0.0;

  // Portfolio Calculation State
  Map<String, dynamic>? _portfolioZakatData;
  bool _isLoadingPortfolio = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _calculatePortfolioZakat(); // Try to load portfolio data on start
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cashController.dispose();
    _goldController.dispose();
    _sharesController.dispose();
    _otherController.dispose();
    super.dispose();
  }

  void _calculateManual() {
    final cash = double.tryParse(_cashController.text) ?? 0.0;
    final gold = double.tryParse(_goldController.text) ?? 0.0;
    final shares = double.tryParse(_sharesController.text) ?? 0.0;
    final other = double.tryParse(_otherController.text) ?? 0.0;

    final totalAssets = cash + gold + shares + other;

    // Nisab check (simplified ~85g Gold approx $5000-6000 USD depending on market)
    // For this generic tool, we'll just calculate 2.5% of total.

    setState(() {
      _manualTotalZakat = totalAssets * 0.025;
    });

    HapticUtils.success();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  Future<void> _calculatePortfolioZakat() async {
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isAuthenticated) return;

    setState(() => _isLoadingPortfolio = true);

    try {
      final data = await ApiService.calculateZakat(authProvider.token!);
      if (mounted) {
        setState(() {
          _portfolioZakatData = data;
          _isLoadingPortfolio = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPortfolio = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations(context);
    final theme = Theme.of(context);
    final isArabic = context.watch<LanguageProvider>().isArabic;
    final currencyProvider = context.watch<CurrencyProvider>();

    return Scaffold(
      appBar: PlatformAppBar(title: l10n.zakatCalculator),
      body: Column(
        children: [
          Container(
            color: theme.scaffoldBackgroundColor,
            child: TabBar(
              controller: _tabController,
              indicatorColor: HalalFintechTheme.accentGreen,
              labelColor: HalalFintechTheme.accentGreen,
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(text: isArabic ? 'يدوي' : 'Manual'),
                Tab(text: isArabic ? 'المحفظة' : 'Portfolio'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildManualTab(context, isArabic, theme, currencyProvider),
                _buildPortfolioTab(
                  context,
                  isArabic,
                  theme,
                  l10n,
                  currencyProvider,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualTab(
    BuildContext context,
    bool isArabic,
    ThemeData theme,
    CurrencyProvider currencyProvider,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildInput(
                    isArabic
                        ? 'النقد والودائع البنكية'
                        : 'Cash & Bank Deposits',
                    _cashController,
                    Icons.attach_money,
                    prefix: currencyProvider.selectedCurrency.symbol,
                  ),
                  const SizedBox(height: 16),
                  _buildInput(
                    isArabic ? 'الذهب والفضة' : 'Gold & Silver',
                    _goldController,
                    Icons.grid_on,
                    prefix: currencyProvider.selectedCurrency.symbol,
                  ),
                  const SizedBox(height: 16),
                  _buildInput(
                    isArabic ? 'الأسهم (بنية المتاجرة)' : 'Shares (Trading)',
                    _sharesController,
                    Icons.show_chart,
                    prefix: currencyProvider.selectedCurrency.symbol,
                  ),
                  const SizedBox(height: 16),
                  _buildInput(
                    isArabic ? 'أصول أخرى' : 'Other Assets',
                    _otherController,
                    Icons.account_balance_wallet,
                    prefix: currencyProvider.selectedCurrency.symbol,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: PlatformButton(
                      label: isArabic ? 'احسب' : 'Calculate',
                      onPressed: _calculateManual,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_manualTotalZakat > 0)
            Card(
              color: HalalFintechTheme.accentGreen,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      isArabic ? 'الزكاة المستحقة' : 'Zakat Due (2.5%)',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currencyProvider.formatPrice(_manualTotalZakat),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInput(
    String label,
    TextEditingController controller,
    IconData icon, {
    String? prefix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        prefixText: prefix != null ? '$prefix ' : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildPortfolioTab(
    BuildContext context,
    bool isArabic,
    ThemeData theme,
    AppLocalizations l10n,
    CurrencyProvider currencyProvider,
  ) {
    final authProvider = context.watch<AuthProvider>();

    if (!authProvider.isAuthenticated) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              l10n.pleaseLoginToCalculateZakat,
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    if (_isLoadingPortfolio) {
      return const Center(child: CircularProgressIndicator());
    }

    // Default to empty map if null
    final data = _portfolioZakatData ?? {'total_zakat': 0.0, 'breakdown': []};
    final total = (data['total_zakat'] as num?)?.toDouble() ?? 0.0;
    final breakdown = (data['breakdown'] as List?) ?? [];

    if (total == 0 && breakdown.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.show_chart, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                isArabic
                    ? 'لم يتم العثور على زكاة مستحقة في محفظتك. تأكد من إضافة عدد الأسهم في محفظتك.'
                    : 'No Zakat due found on your portfolio. Make sure you have added shares to your stocks.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _calculatePortfolioZakat,
                child: Text(l10n.refresh),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Total Zakat Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(l10n.totalZakat, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Text(
                    currencyProvider.formatPrice(total),
                    style: theme.textTheme.displayMedium?.copyWith(
                      color: HalalFintechTheme.accentGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Breakdown
          if (breakdown.isNotEmpty) ...[
            Text(l10n.breakdown, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            ...breakdown.map((item) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(item['name']?.toString() ?? ''),
                  subtitle: Text('${item['shares']} shares'),
                  trailing: Text(
                    currencyProvider.formatPrice(
                      (item['zakat_amount'] ?? 0.0).toDouble(),
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
