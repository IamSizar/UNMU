import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../theme/halal_fintech_theme.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/platform_adaptive/platform_app_bar.dart';
import '../../providers/currency_provider.dart';
import '../../providers/language_provider.dart';

class DcaCalculatorScreen extends StatefulWidget {
  const DcaCalculatorScreen({super.key});

  @override
  State<DcaCalculatorScreen> createState() => _DcaCalculatorScreenState();
}

class _DcaCalculatorScreenState extends State<DcaCalculatorScreen> {
  final _amountController = TextEditingController(text: '500');
  final _yearsController = TextEditingController(text: '10');
  final _rateController = TextEditingController(text: '8');

  bool _isLoading = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _amountController.dispose();
    _yearsController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _calculate() async {
    await HapticUtils.lightTap();
    FocusScope.of(context).unfocus();

    // Validate inputs
    final amount = double.tryParse(_amountController.text);
    final years = int.tryParse(_yearsController.text);
    final rate = double.tryParse(_rateController.text);

    if (amount == null || years == null || rate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid numbers')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Annual rate to decimal (e.g. 8 -> 0.08)
      final result = await ApiService.calculateDCA(amount, years, rate / 100);

      setState(() {
        _result = result;
        _isLoading = false;
      });

      if (result != null) {
        await HapticUtils.success();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isArabic = context.watch<LanguageProvider>().isArabic;
    final currencyProvider = context.watch<CurrencyProvider>();

    return Scaffold(
      appBar: PlatformAppBar(
        title: isArabic ? 'حاسبة الاستثمار' : 'DCA Calculator',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Inputs Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildInput(
                      label: isArabic ? 'المبلغ الشهري' : 'Monthly Amount',
                      controller: _amountController,
                      prefix: currencyProvider.selectedCurrency.symbol,
                      icon: Icons.attach_money,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInput(
                            label: isArabic ? 'السنوات' : 'Years',
                            controller: _yearsController,
                            icon: Icons.calendar_today,
                            isInteger: true,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildInput(
                            label: isArabic ? 'العائد %' : 'Return %',
                            controller: _rateController,
                            suffix: '',
                            icon: Icons.trending_up,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _calculate,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: HalalFintechTheme.accentGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isArabic ? 'احسب' : 'Calculate',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Results
            if (_result != null) ...[
              _buildResultCard(theme, isDark, isArabic, currencyProvider),
              const SizedBox(height: 24),
              Text(
                isArabic ? 'التفاصيل السنوية' : 'Yearly Breakdown',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _buildBreakdownList(isDark, currencyProvider),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInput({
    required String label,
    required TextEditingController controller,
    String? prefix,
    String? suffix,
    required IconData icon,
    bool isInteger = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: !isInteger),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(isInteger ? r'[0-9]' : r'[0-9.]'),
        ),
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix != null ? '$prefix ' : null,
        suffixText: suffix,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
    );
  }

  Widget _buildResultCard(
    ThemeData theme,
    bool isDark,
    bool isArabic,
    CurrencyProvider currencyProvider,
  ) {
    final totalInvested =
        (_result!['total_invested'] as num?)?.toDouble() ?? 0.0;
    final projectedValue =
        (_result!['projected_value'] as num?)?.toDouble() ?? 0.0;
    final gain = (_result!['projected_gain'] as num?)?.toDouble() ?? 0.0;
    final gainPercent = totalInvested > 0 ? (gain / totalInvested) * 100 : 0.0;

    return Card(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              isArabic ? 'قيمة الاستثمار المتوقعة' : 'Projected Value',
              style: theme.textTheme.titleMedium?.copyWith(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              currencyProvider.formatPrice(projectedValue),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: HalalFintechTheme.accentGreen,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildResultItem(
                    theme,
                    isArabic ? 'إجمالي الاستثمار' : 'Total Invested',
                    currencyProvider.formatPrice(totalInvested),
                    isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey.withOpacity(0.2),
                ),
                Expanded(
                  child: _buildResultItem(
                    theme,
                    isArabic ? 'الكسب المتوقع' : 'Total Gain',
                    '+${currencyProvider.formatPrice(gain)}',
                    HalalFintechTheme.accentGreen,
                    subtitle: '+${gainPercent.toStringAsFixed(1)}%',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultItem(
    ThemeData theme,
    String label,
    String value,
    Color valueColor, {
    String? subtitle,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
          textAlign: TextAlign.center,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10,
              color: valueColor.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildBreakdownList(bool isDark, CurrencyProvider currencyProvider) {
    final breakdown = List<Map<String, dynamic>>.from(
      _result!['breakdown'] ?? [],
    );

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: breakdown.length,
      itemBuilder: (context, index) {
        final item = breakdown[index];
        final year = item['year'];
        final value = (item['projected_value'] as num?)?.toDouble() ?? 0.0;
        final invested = (item['invested'] as num?)?.toDouble() ?? 0.0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          color: isDark ? Colors.grey[900] : Colors.grey[50],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isDark ? Colors.white10 : Colors.grey.withOpacity(0.1),
            ),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: HalalFintechTheme.accentGreen.withOpacity(0.1),
              child: Text(
                '$year',
                style: const TextStyle(
                  color: HalalFintechTheme.accentGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              currencyProvider.formatPrice(value),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${context.watch<LanguageProvider>().isArabic ? "المستثمر: " : "Invested: "}${currencyProvider.formatPrice(invested)}',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ),
        );
      },
    );
  }
}
