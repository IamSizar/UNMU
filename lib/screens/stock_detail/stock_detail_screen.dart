import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import '../../services/api_service.dart';
import '../../controllers/watchlist_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../widgets/status_badge.dart';
import '../../theme/halal_fintech_theme.dart';
import '../../utils/stock_logo_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/platform_utils.dart';
import '../../utils/explanation_translator.dart';
import '../../controllers/language_controller.dart';

class StockDetailScreen extends StatefulWidget {
  final String ticker;
  final String exchange;

  const StockDetailScreen({
    super.key,
    required this.ticker,
    required this.exchange,
  });

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  Map<String, dynamic>? _stockData;
  bool _isLoading = true;
  String? _error;
  bool _isFollowing = false;
  final TextEditingController _investmentController = TextEditingController();
  double? _calculatedZakat;

  @override
  void initState() {
    super.initState();
    _loadStockDetails();
    _checkFollowing();
  }

  @override
  void dispose() {
    _investmentController.dispose();
    super.dispose();
  }

  void _calculateZakat() {
    final amount = double.tryParse(_investmentController.text);
    if (amount != null && amount > 0) {
      setState(() {
        _calculatedZakat = amount * 0.025; // 2.5% zakat rate
      });
    } else {
      setState(() {
        _calculatedZakat = null;
      });
    }
  }

  Future<void> _loadStockDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await ApiService.getStockDetails(
        widget.ticker,
        widget.exchange,
      );
      setState(() {
        _stockData = data;
        _isLoading = false;
      });
      _checkFollowing();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _checkFollowing() async {
    if (!mounted) return;
    final authProvider = Get.find<AuthController>();
    if (authProvider.isAuthenticated && _stockData != null) {
      final watchlistProvider = Get.find<WatchlistController>();
      final stockId = _stockData!['stock']?['id'];
      if (stockId != null && mounted) {
        setState(() {
          _isFollowing = watchlistProvider.isInWatchlist(stockId);
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    await HapticUtils.lightTap();
    final authProvider = Get.find<AuthController>();
    if (!authProvider.isAuthenticated) {
      // Show login prompt
      return;
    }

    final watchlistProvider = Get.find<WatchlistController>();
    final stockId = _stockData!['stock']?['id'];
    if (stockId == null) return;

    setState(() {
      _isFollowing = !_isFollowing;
    });

    final success = _isFollowing
        ? await watchlistProvider.addToWatchlist(authProvider.token, stockId)
        : await watchlistProvider.removeFromWatchlist(
            authProvider.token,
            stockId,
          );

    if (!success) {
      setState(() {
        _isFollowing = !_isFollowing;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark
            ? HalalFintechTheme.backgroundDark
            : HalalFintechTheme.backgroundLight,
        appBar: _buildAppBar(context, theme, isDark),
        body: Center(
          child: CircularProgressIndicator(
            color: HalalFintechTheme.accentGreen,
          ),
        ),
      );
    }

    if (_error != null || _stockData == null) {
      return Scaffold(
        backgroundColor: isDark
            ? HalalFintechTheme.backgroundDark
            : HalalFintechTheme.backgroundLight,
        appBar: _buildAppBar(context, theme, isDark),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: isDark
                      ? HalalFintechTheme.textSecondaryDark
                      : HalalFintechTheme.textSecondaryLight,
                ),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'common.error'.tr,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: isDark
                        ? HalalFintechTheme.textSecondaryDark
                        : HalalFintechTheme.textSecondaryLight,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loadStockDetails,
                  child: Text('common.retry'.tr),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final stock = _stockData!['stock'] as Map<String, dynamic>?;
    final shariahStatus =
        _stockData!['shariah_status'] as Map<String, dynamic>?;
    final fundamentals = _stockData!['fundamentals'] as Map<String, dynamic>?;
    final analystRatings = _stockData!['analyst_ratings'] as List<dynamic>?;
    final paysZakat = shariahStatus?['pays_zakat'] as bool? ?? false;
    final status = shariahStatus?['status']?.toString() ?? 'UNKNOWN';
    final statusColor = HalalFintechTheme.getStatusColor(status);

    return Scaffold(
      backgroundColor: isDark
          ? HalalFintechTheme.backgroundDark
          : HalalFintechTheme.backgroundLight,
      appBar: _buildAppBar(context, theme, isDark),
      body: CustomScrollView(
        slivers: [
          // Hero Header Section
          SliverToBoxAdapter(
            child: _buildHeroHeader(
              context,
              stock,
              shariahStatus,
              statusColor,
              isDark,
              theme,
            ),
          ),

          // Key Metrics Section
          if (shariahStatus != null)
            SliverToBoxAdapter(
              child: _buildKeyMetricsSection(
                context,
                shariahStatus,
                statusColor,
                isDark,
                theme,
              ),
            ),

          // Fundamentals Section
          if (fundamentals != null)
            SliverToBoxAdapter(
              child: _buildFundamentalsSection(
                context,
                fundamentals,
                isDark,
                theme,
              ),
            ),

          // Stock Information Section
          if (stock != null)
            SliverToBoxAdapter(
              child: _buildStockInfoSection(context, stock, isDark, theme),
            ),

          // Description Section
          if (stock?['description'] != null)
            SliverToBoxAdapter(
              child: _buildDescriptionSection(
                context,
                stock!['description'].toString(),
                isDark,
                theme,
              ),
            ),

          // Reasoning Section
          if (shariahStatus?['reason'] != null ||
              shariahStatus?['explanation'] != null)
            SliverToBoxAdapter(
              child: _buildReasoningSection(
                context,
                shariahStatus!,
                status,
                isDark,
                theme,
              ),
            ),

          // Zakat Section
          SliverToBoxAdapter(
            child: _buildZakatSection(context, paysZakat, isDark, theme),
          ),

          // Analyst Ratings Section
          if (analystRatings != null && analystRatings.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildAnalystRatingsSection(
                context,
                analystRatings,
                isDark,
                theme,
              ),
            ),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    if (PlatformUtils.isIOS) {
      return CupertinoNavigationBar(
        middle: Text(
          'stock.title'.tr,
          style: TextStyle(
            color: isDark
                ? HalalFintechTheme.textPrimaryDark
                : HalalFintechTheme.textPrimaryLight,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: _loadStockDetails,
              child: const Icon(CupertinoIcons.refresh, size: 20),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: _toggleFollow,
              child: Icon(
                _isFollowing ? Icons.star : Icons.star_border,
                color: _isFollowing
                    ? HalalFintechTheme.accentGreen
                    : (isDark
                          ? HalalFintechTheme.textSecondaryDark
                          : HalalFintechTheme.textSecondaryLight),
                size: 24,
              ),
            ),
          ],
        ),
        backgroundColor: isDark
            ? HalalFintechTheme.backgroundDark
            : HalalFintechTheme.backgroundLight,
        border: null,
      );
    }

    return AppBar(
      title: Text('stock.title'.tr),
      backgroundColor: isDark
          ? HalalFintechTheme.backgroundDark
          : HalalFintechTheme.backgroundLight,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadStockDetails,
          tooltip: 'common.refresh'.tr,
        ),
        IconButton(
          icon: Icon(_isFollowing ? Icons.star : Icons.star_border),
          onPressed: _toggleFollow,
          color: _isFollowing ? HalalFintechTheme.accentGreen : null,
        ),
      ],
    );
  }

  Widget _buildHeroHeader(
    BuildContext context,
    Map<String, dynamic>? stock,
    Map<String, dynamic>? shariahStatus,
    Color statusColor,
    bool isDark,
    ThemeData theme,
  ) {
    final stockName = stock?['name']?.toString() ?? widget.ticker;
    final ticker = stock?['ticker']?.toString() ?? widget.ticker;
    final exchange = stock?['exchange']?.toString() ?? widget.exchange;
    final logoUrl = StockLogoUtils.getStockLogoUrl(ticker, exchange: exchange);

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Stock Logo
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: Image.network(
                logoUrl,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        ticker.isNotEmpty
                            ? ticker.substring(0, 1).toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 32,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Stock Name
          Text(
            stockName,
            style: theme.textTheme.displaySmall?.copyWith(
              color: isDark
                  ? HalalFintechTheme.textPrimaryDark
                  : HalalFintechTheme.textPrimaryLight,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Ticker and Exchange
          Text(
            '$ticker • $exchange',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isDark
                  ? HalalFintechTheme.textSecondaryDark
                  : HalalFintechTheme.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 24),

          // Status Badge
          if (shariahStatus != null)
            StatusBadge(
              status: shariahStatus['status']?.toString() ?? 'UNKNOWN',
              grade: shariahStatus['grade']?.toString(),
            ),
        ],
      ),
    );
  }

  Widget _buildKeyMetricsSection(
    BuildContext context,
    Map<String, dynamic> shariahStatus,
    Color statusColor,
    bool isDark,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'stock.keyMetrics'.tr,
            style: theme.textTheme.titleLarge?.copyWith(
              color: isDark
                  ? HalalFintechTheme.textPrimaryDark
                  : HalalFintechTheme.textPrimaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (shariahStatus['debt_ratio'] != null)
                _buildMetricChip(
                  'stock.debtRatio'.tr,
                  '${(shariahStatus['debt_ratio'] as num).toStringAsFixed(2)}%',
                  isDark,
                  theme,
                ),
              if (shariahStatus['haram_income_ratio'] != null)
                _buildMetricChip(
                  'stock.haramIncome'.tr,
                  '${(shariahStatus['haram_income_ratio'] as num).toStringAsFixed(2)}%',
                  isDark,
                  theme,
                ),
              if (shariahStatus['purification_rate'] != null)
                _buildMetricChip(
                  'stock.purification'.tr,
                  '${(shariahStatus['purification_rate'] as num).toStringAsFixed(2)}%',
                  isDark,
                  theme,
                ),
              if (shariahStatus['pays_zakat'] != null)
                _buildMetricChip(
                  'stock.paysZakat'.tr,
                  shariahStatus['pays_zakat'] == true
                      ? 'stock.yes'.tr
                      : 'stock.no'.tr,
                  isDark,
                  theme,
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildMetricChip(
    String label,
    String value,
    bool isDark,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? HalalFintechTheme.cardDark
            : HalalFintechTheme.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? HalalFintechTheme.cardBorderDark
              : HalalFintechTheme.cardBorderLight,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? HalalFintechTheme.textSecondaryDark
                  : HalalFintechTheme.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: isDark
                  ? HalalFintechTheme.textPrimaryDark
                  : HalalFintechTheme.textPrimaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFundamentalsSection(
    BuildContext context,
    Map<String, dynamic> fundamentals,
    bool isDark,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'stock.fundamentals'.tr,
            style: theme.textTheme.titleLarge?.copyWith(
              color: isDark
                  ? HalalFintechTheme.textPrimaryDark
                  : HalalFintechTheme.textPrimaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? HalalFintechTheme.cardDark
                  : HalalFintechTheme.cardLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? HalalFintechTheme.cardBorderDark
                    : HalalFintechTheme.cardBorderLight,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                if (fundamentals['total_assets'] != null)
                  _buildInfoRow(
                    'stock.totalAssets'.tr,
                    _formatNumber(fundamentals['total_assets']),
                    isDark,
                    theme,
                  ),
                if (fundamentals['total_debt'] != null)
                  _buildInfoRow(
                    'stock.totalDebt'.tr,
                    _formatNumber(fundamentals['total_debt']),
                    isDark,
                    theme,
                  ),
                if (fundamentals['cash_and_equiv'] != null)
                  _buildInfoRow(
                    'stock.cashAndEquiv'.tr,
                    _formatNumber(fundamentals['cash_and_equiv']),
                    isDark,
                    theme,
                  ),
                if (fundamentals['total_revenue'] != null)
                  _buildInfoRow(
                    'stock.totalRevenue'.tr,
                    _formatNumber(fundamentals['total_revenue']),
                    isDark,
                    theme,
                  ),
                if (fundamentals['net_income'] != null)
                  _buildInfoRow(
                    'stock.netIncome'.tr,
                    _formatNumber(fundamentals['net_income']),
                    isDark,
                    theme,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    bool isDark,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? HalalFintechTheme.textSecondaryDark
                  : HalalFintechTheme.textSecondaryLight,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isDark
                  ? HalalFintechTheme.textPrimaryDark
                  : HalalFintechTheme.textPrimaryLight,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockInfoSection(
    BuildContext context,
    Map<String, dynamic> stock,
    bool isDark,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'stock.information'.tr,
            style: theme.textTheme.titleLarge?.copyWith(
              color: isDark
                  ? HalalFintechTheme.textPrimaryDark
                  : HalalFintechTheme.textPrimaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? HalalFintechTheme.cardDark
                  : HalalFintechTheme.cardLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? HalalFintechTheme.cardBorderDark
                    : HalalFintechTheme.cardBorderLight,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                if (stock['country'] != null)
                  _buildInfoRow(
                    'stock.country'.tr,
                    stock['country'].toString(),
                    isDark,
                    theme,
                  ),
                if (stock['region_code'] != null)
                  _buildInfoRow(
                    'stock.region'.tr,
                    stock['region_code'].toString(),
                    isDark,
                    theme,
                  ),
                if (stock['sector'] != null)
                  _buildInfoRow(
                    'stock.sector'.tr,
                    stock['sector'].toString(),
                    isDark,
                    theme,
                  ),
                if (stock['industry'] != null)
                  _buildInfoRow(
                    'stock.industry'.tr,
                    stock['industry'].toString(),
                    isDark,
                    theme,
                  ),
                if (stock['market_cap'] != null)
                  _buildInfoRow(
                    'stock.marketCap'.tr,
                    _formatNumber(stock['market_cap']),
                    isDark,
                    theme,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(
    BuildContext context,
    String description,
    bool isDark,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'stock.description'.tr,
            style: theme.textTheme.titleLarge?.copyWith(
              color: isDark
                  ? HalalFintechTheme.textPrimaryDark
                  : HalalFintechTheme.textPrimaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? HalalFintechTheme.cardDark
                  : HalalFintechTheme.cardLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? HalalFintechTheme.cardBorderDark
                    : HalalFintechTheme.cardBorderLight,
                width: 1,
              ),
            ),
            child: Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? HalalFintechTheme.textPrimaryDark
                    : HalalFintechTheme.textSecondaryLight,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildReasoningSection(
    BuildContext context,
    Map<String, dynamic> shariahStatus,
    String status,
    bool isDark,
    ThemeData theme,
  ) {
    final isArabic = Get.find<LanguageController>().isArabic;
    final reason = shariahStatus['reason']?.toString();
    final explanation = shariahStatus['explanation']?.toString();
    final statusColor = HalalFintechTheme.getStatusColor(status);

    // Translate explanation and reason if Arabic
    final translatedReason = reason != null
        ? ExplanationTranslator.translate(reason, isArabic)
        : null;
    final translatedExplanation = explanation != null
        ? ExplanationTranslator.translate(explanation, isArabic)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'stock.shariahAssessment'.tr,
            style: theme.textTheme.titleLarge?.copyWith(
              color: isDark
                  ? HalalFintechTheme.textPrimaryDark
                  : HalalFintechTheme.textPrimaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? HalalFintechTheme.cardDark
                  : HalalFintechTheme.cardLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? HalalFintechTheme.cardBorderDark
                    : HalalFintechTheme.cardBorderLight,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (translatedReason != null) ...[
                  _buildReasonText(
                    translatedReason,
                    statusColor,
                    isDark,
                    theme,
                    context,
                  ),
                  if (translatedExplanation != null) const SizedBox(height: 16),
                ],
                if (translatedExplanation != null)
                  _buildExplanationBlock(
                    translatedExplanation,
                    isDark,
                    theme,
                    isArabic,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Renders the Shariah explanation as clean, readable text. The backend
  /// stores it as a raw ASCII report (==== separators, "1. SECTION:" numbering,
  /// indented "Key: Value" lines) which reads like a terminal dump. This strips
  /// the decorations and styles section headers vs body lines as normal text.
  Widget _buildExplanationBlock(
    String raw,
    bool isDark,
    ThemeData theme,
    bool isArabic,
  ) {
    final sepRe = RegExp(r'^[=\-_\s]+$'); // separator-only lines
    final numRe = RegExp(r'^\s*\d+[\.\)]\s*'); // leading "1. " / "2) "
    final primary = isDark
        ? HalalFintechTheme.textPrimaryDark
        : HalalFintechTheme.textPrimaryLight;
    final secondary = isDark
        ? HalalFintechTheme.textSecondaryDark
        : HalalFintechTheme.textSecondaryLight;
    final dir = isArabic ? TextDirection.rtl : TextDirection.ltr;

    bool isTitleLine(String l) =>
        l.startsWith('Sharia Compliance Analysis') ||
        l.startsWith('تحليل الامتثال الشرعي');

    final blocks = <Widget>[];
    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || sepRe.hasMatch(line) || isTitleLine(line)) continue;

      final hadNumber = numRe.hasMatch(line);
      final stripped = line.replaceFirst(numRe, '').trim();
      final isUpperLatin = stripped == stripped.toUpperCase() &&
          RegExp(r'[A-Z]').hasMatch(stripped);
      final isHeading = hadNumber || (stripped.endsWith(':') && isUpperLatin);

      if (isHeading) {
        blocks.add(Padding(
          padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 16, bottom: 8),
          child: Text(
            _titleCaseIfUpper(stripped.replaceAll(':', '').trim()),
            textDirection: dir,
            style: theme.textTheme.titleSmall?.copyWith(
              color: primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ));
      } else {
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            stripped,
            textDirection: dir,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondary,
              height: 1.55,
            ),
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  /// "BUSINESS ACTIVITY SCREENING" → "Business Activity Screening". Leaves
  /// already-cased text and Arabic (no Latin caps) untouched.
  String _titleCaseIfUpper(String s) {
    if (s != s.toUpperCase() || !RegExp(r'[A-Z]').hasMatch(s)) return s;
    return s
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Widget _buildReasonText(
    String reason,
    Color statusColor,
    bool isDark,
    ThemeData theme,
    BuildContext context,
  ) {
    final isArabic = Get.find<LanguageController>().isArabic;
    final parts = reason.split('. ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: parts.map((part) {
        if (part.trim().isEmpty) return const SizedBox.shrink();
        final lowerPart = part.toLowerCase();
        final isImportant =
            lowerPart.contains('debt ratio') ||
            lowerPart.contains('نسبة الدين') ||
            lowerPart.contains('non-compliant income') ||
            lowerPart.contains('الدخل غير المتوافق') ||
            lowerPart.contains('final grade') ||
            lowerPart.contains('الدرجة النهائية') ||
            lowerPart.contains('business activity') ||
            lowerPart.contains('النشاط التجاري');

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            part.trim() + (part.endsWith('.') ? '' : '.'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isImportant ? FontWeight.w600 : FontWeight.normal,
              color: isImportant
                  ? statusColor
                  : (isDark
                        ? HalalFintechTheme.textPrimaryDark
                        : HalalFintechTheme.textPrimaryLight),
              fontSize: isImportant ? 15 : 14,
            ),
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildZakatSection(
    BuildContext context,
    bool paysZakat,
    bool isDark,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'stock.zakatInformation'.tr,
            style: theme.textTheme.titleLarge?.copyWith(
              color: isDark
                  ? HalalFintechTheme.textPrimaryDark
                  : HalalFintechTheme.textPrimaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? HalalFintechTheme.cardDark
                  : HalalFintechTheme.cardLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? HalalFintechTheme.cardBorderDark
                    : HalalFintechTheme.cardBorderLight,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      paysZakat ? Icons.check_circle : Icons.cancel,
                      color: paysZakat
                          ? HalalFintechTheme.halalGreen
                          : HalalFintechTheme.mixedYellow,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        paysZakat
                            ? 'stock.companyPaysZakat'.tr
                            : 'stock.companyDoesNotPayZakat'.tr,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: isDark
                              ? HalalFintechTheme.textPrimaryDark
                              : HalalFintechTheme.textPrimaryLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!paysZakat) ...[
                  const SizedBox(height: 20),
                  Text(
                    'stock.zakatCalculation'.tr,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: isDark
                          ? HalalFintechTheme.textPrimaryDark
                          : HalalFintechTheme.textPrimaryLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _investmentController,
                    keyboardType: TextInputType.number,
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      labelText: 'stock.enterInvestmentAmount'.tr,
                      prefixIcon: const Icon(Icons.attach_money),
                      filled: true,
                      fillColor: isDark
                          ? HalalFintechTheme.backgroundDark
                          : HalalFintechTheme.backgroundLight,
                    ),
                    onChanged: (_) => _calculateZakat(),
                  ),
                  if (_calculatedZakat != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: HalalFintechTheme.accentGreen.withValues(
                          alpha: 0.1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'stock.zakatAmount'.tr,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: isDark
                                  ? HalalFintechTheme.textPrimaryDark
                                  : HalalFintechTheme.textPrimaryLight,
                            ),
                          ),
                          Text(
                            '\$${_calculatedZakat!.toStringAsFixed(2)}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: HalalFintechTheme.accentGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${'stock.zakatRate'.tr} (${_investmentController.text} × 2.5%)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? HalalFintechTheme.textSecondaryDark
                            : HalalFintechTheme.textSecondaryLight,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildAnalystRatingsSection(
    BuildContext context,
    List<dynamic> analystRatings,
    bool isDark,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'stock.analystRatings'.tr,
            style: theme.textTheme.titleLarge?.copyWith(
              color: isDark
                  ? HalalFintechTheme.textPrimaryDark
                  : HalalFintechTheme.textPrimaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...analystRatings.map((rating) {
            final ratingValue = rating['rating']?.toString() ?? '';
            Color ratingColor;
            IconData ratingIcon;
            switch (ratingValue.toUpperCase()) {
              case 'BUY':
                ratingColor = HalalFintechTheme.halalGreen;
                ratingIcon = Icons.trending_up;
                break;
              case 'SELL':
                ratingColor = HalalFintechTheme.haramRed;
                ratingIcon = Icons.trending_down;
                break;
              case 'HOLD':
                ratingColor = HalalFintechTheme.mixedYellow;
                ratingIcon = Icons.trending_flat;
                break;
              default:
                ratingColor = isDark
                    ? HalalFintechTheme.textSecondaryDark
                    : HalalFintechTheme.textSecondaryLight;
                ratingIcon = Icons.help_outline;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? HalalFintechTheme.cardDark
                    : HalalFintechTheme.cardLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? HalalFintechTheme.cardBorderDark
                      : HalalFintechTheme.cardBorderLight,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: ratingColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(ratingIcon, color: ratingColor, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rating['analyst_name']?.toString() ??
                              'stock.analystName'.tr,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: isDark
                                ? HalalFintechTheme.textPrimaryDark
                                : HalalFintechTheme.textPrimaryLight,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (rating['rating'] != null)
                          Text(
                            _getRatingText(rating['rating'].toString()),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: ratingColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (rating['target_price'] != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${'stock.target'.tr}: \$${(rating['target_price'] as num).toStringAsFixed(2)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? HalalFintechTheme.textSecondaryDark
                                  : HalalFintechTheme.textSecondaryLight,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _getRatingText(String rating) {
    switch (rating.toUpperCase()) {
      case 'BUY':
        return 'stock.ratingBuy'.tr;
      case 'SELL':
        return 'stock.ratingSell'.tr;
      case 'HOLD':
        return 'stock.ratingHold'.tr;
      default:
        return rating;
    }
  }

  String _formatNumber(dynamic value) {
    if (value == null) return 'N/A';
    final num = value is int ? value.toDouble() : value as double;
    if (num >= 1e12) {
      return '\$${(num / 1e12).toStringAsFixed(2)}T';
    } else if (num >= 1e9) {
      return '\$${(num / 1e9).toStringAsFixed(2)}B';
    } else if (num >= 1e6) {
      return '\$${(num / 1e6).toStringAsFixed(2)}M';
    } else if (num >= 1e3) {
      return '\$${(num / 1e3).toStringAsFixed(2)}K';
    }
    return '\$${num.toStringAsFixed(2)}';
  }
}
