import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/currency_controller.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/api_service.dart';
import '../../utils/haptic_utils.dart';

/// =============================================================================
/// DCA (Dollar-Cost Averaging) Calculator — modern fintech UI.
///
///   ▸ Themed app bar
///   ▸ Hero result card (cyan gradient, big projected value)
///   ▸ Inputs: monthly amount, years, return %
///   ▸ Cyan gradient calculate button with glow
///   ▸ Yearly breakdown — visual list with progress bars
///   ▸ Embedded sparkline showing the projected growth curve
/// =============================================================================
class DcaCalculatorScreen extends StatefulWidget {
  const DcaCalculatorScreen({super.key});

  @override
  State<DcaCalculatorScreen> createState() => _DcaCalculatorScreenState();
}

class _DcaCalculatorScreenState extends State<DcaCalculatorScreen> {
  final _amount = TextEditingController(text: '500');
  final _years = TextEditingController(text: '10');
  final _rate = TextEditingController(text: '8');

  bool _loading = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _amount.dispose();
    _years.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _calculate() async {
    HapticUtils.lightTap();
    FocusScope.of(context).unfocus();
    final amount = double.tryParse(_amount.text);
    final years = int.tryParse(_years.text);
    final rate = double.tryParse(_rate.text);

    if (amount == null || years == null || rate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('dca.invalidNumbers'.tr)),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await ApiService.calculateDCA(amount, years, rate / 100);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
      if (result != null) {
        await HapticUtils.success();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('dca.errorPrefix'.trParams({'error': '$e'}))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final cur = Get.find<CurrencyController>();

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'dca.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          // Hero result — always visible (shows defaults pre-calc)
          _DcaHero(
            palette: palette,
            result: _result,
            cur: cur,
            // Use input values as preview when no API result yet
            previewAmount: double.tryParse(_amount.text) ?? 0,
            previewYears: int.tryParse(_years.text) ?? 0,
            previewRate: double.tryParse(_rate.text) ?? 0,
          ),
          const SizedBox(height: 20),
          _MiniSectionHeader(
            palette: palette,
            eyebrow: 'dca.inputsEyebrow'.tr,
            title: 'dca.inputsTitle'.tr,
          ),
          const SizedBox(height: 12),
          _InputsCard(
            palette: palette,
            amount: _amount,
            years: _years,
            rate: _rate,
            currencySymbol: cur.selectedCurrency.symbol,
            onChange: () => setState(() {}),
          ),
          const SizedBox(height: 14),
          _CalculateButton(
            label: 'dca.calculate'.tr,
            onPressed: _loading ? null : _calculate,
            loading: _loading,
          ),
          if (_result != null) ...[
            const SizedBox(height: 28),
            _MiniSectionHeader(
              palette: palette,
              eyebrow: 'dca.yearlyEyebrow'.tr,
              title: 'dca.breakdownTitle'.tr,
            ),
            const SizedBox(height: 12),
            _BreakdownList(palette: palette, result: _result!, cur: cur),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// Hero result card — big projected value + sparkline
// ============================================================================
class _DcaHero extends StatelessWidget {
  final SocialPalette palette;
  final Map<String, dynamic>? result;
  final CurrencyController cur;
  final double previewAmount;
  final int previewYears;
  final double previewRate;

  const _DcaHero({
    required this.palette,
    required this.result,
    required this.cur,
    required this.previewAmount,
    required this.previewYears,
    required this.previewRate,
  });

  @override
  Widget build(BuildContext context) {
    final hasResult = result != null;
    final invested = hasResult
        ? ((result!['total_invested'] as num?)?.toDouble() ?? 0)
        : previewAmount * 12 * previewYears;
    final projected = hasResult
        ? ((result!['projected_value'] as num?)?.toDouble() ?? 0)
        : _previewProjection(previewAmount, previewYears, previewRate);
    final gain = hasResult
        ? ((result!['projected_gain'] as num?)?.toDouble() ?? 0)
        : (projected - invested);
    final gainPct = invested > 0 ? (gain / invested) * 100 : 0;

    final sparkData = _sparklineFromBreakdown(result) ??
        _previewSparkline(previewAmount, previewYears, previewRate);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: palette.heroGradient(),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: SocialTokens.cyan.withValues(alpha: 0.5),
          width: 1.4,
        ),
        boxShadow: palette.cardShadow(accent: SocialTokens.cyan),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: SocialTokens.cyan.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: SocialTokens.cyan.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.trending_up_rounded,
                      size: 11,
                      color: SocialTokens.cyan,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'dca.projection'.tr,
                      style: const TextStyle(
                        color: SocialTokens.cyan,
                        fontWeight: FontWeight.w900,
                        fontSize: 9.5,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (!hasResult)
                Text(
                  'dca.preview'.tr,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            hasResult
                ? 'dca.projectedValue'.tr
                : 'dca.projectedValueAfter'
                    .trParams({'years': '$previewYears'}),
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                cur.formatPrice(projected),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 36,
                  letterSpacing: -1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: SocialTokens.up.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.arrow_upward_rounded,
                        size: 10,
                        color: SocialTokens.up,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '+${gainPct.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: SocialTokens.up,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Sparkline
          SizedBox(
            height: 60,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (sparkData.length - 1).toDouble(),
                minY: sparkData.reduce(math.min),
                maxY: sparkData.reduce(math.max),
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (int i = 0; i < sparkData.length; i++)
                        FlSpot(i.toDouble(), sparkData[i]),
                    ],
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: SocialTokens.cyan,
                    barWidth: 2.4,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          SocialTokens.cyan.withValues(alpha: 0.32),
                          SocialTokens.cyan.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 1,
            color: palette.subtleDivider,
            margin: const EdgeInsets.symmetric(vertical: 6),
          ),
          Row(
            children: [
              Expanded(
                child: _heroStat(
                  palette,
                  label: 'dca.invested'.tr,
                  value: cur.formatPrice(invested),
                  color: palette.textPrimary,
                ),
              ),
              Container(width: 1, height: 30, color: palette.subtleDivider),
              const SizedBox(width: 12),
              Expanded(
                child: _heroStat(
                  palette,
                  label: 'dca.gain'.tr,
                  value: '+${cur.formatPrice(gain)}',
                  color: SocialTokens.up,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(
    SocialPalette palette, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// Compute a smooth preview value from input fields when no API result yet.
  double _previewProjection(double monthly, int years, double annualPct) {
    if (monthly <= 0 || years <= 0) return 0;
    final r = annualPct / 100 / 12; // monthly rate
    final n = years * 12;
    if (r == 0) return monthly * n;
    // Future value of an annuity (deposits at end of period).
    return monthly * (math.pow(1 + r, n) - 1) / r;
  }

  /// Build a 12-point preview curve from inputs for a smooth chart.
  List<double> _previewSparkline(double monthly, int years, double annualPct) {
    final out = <double>[];
    if (monthly <= 0 || years <= 0) return [0, 0];
    final r = annualPct / 100 / 12;
    final n = years * 12;
    final step = math.max(1, (n / 24).round());
    for (int i = 0; i <= n; i += step) {
      final fv = r == 0 ? monthly * i : monthly * (math.pow(1 + r, i) - 1) / r;
      out.add(fv.toDouble());
    }
    if (out.length < 2) out.add(out.last);
    return out;
  }

  /// Try to extract sparkline data from API breakdown (preferred when present).
  List<double>? _sparklineFromBreakdown(Map<String, dynamic>? r) {
    if (r == null) return null;
    final list = r['breakdown'] as List?;
    if (list == null || list.isEmpty) return null;
    final values = list
        .map((e) => ((e['projected_value'] as num?)?.toDouble() ?? 0))
        .toList();
    return values;
  }
}

// ============================================================================
// Inputs card — money + years + rate
// ============================================================================
class _InputsCard extends StatelessWidget {
  final SocialPalette palette;
  final TextEditingController amount;
  final TextEditingController years;
  final TextEditingController rate;
  final String currencySymbol;
  final VoidCallback onChange;

  const _InputsCard({
    required this.palette,
    required this.amount,
    required this.years,
    required this.rate,
    required this.currencySymbol,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        gradient: palette.cardGradient(),
        borderRadius: BorderRadius.circular(18),
        border: palette.highlightedBorder(),
        boxShadow: palette.cardShadow(),
      ),
      child: Column(
        children: [
          _LabeledNumberField(
            palette: palette,
            controller: amount,
            label: 'dca.monthlyAmount'.tr,
            icon: Icons.attach_money_rounded,
            accent: SocialTokens.cyan,
            prefix: currencySymbol,
            isInteger: false,
            onChanged: (_) => onChange(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _LabeledNumberField(
                  palette: palette,
                  controller: years,
                  label: 'dca.years'.tr,
                  icon: Icons.calendar_today_rounded,
                  accent: SocialTokens.gold,
                  isInteger: true,
                  onChanged: (_) => onChange(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LabeledNumberField(
                  palette: palette,
                  controller: rate,
                  label: 'dca.returnPct'.tr,
                  icon: Icons.trending_up_rounded,
                  accent: SocialTokens.up,
                  isInteger: false,
                  suffix: '%',
                  onChanged: (_) => onChange(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Quick presets
          Row(
            children: [
              for (final y in const [5, 10, 20, 30])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: _Preset(
                    palette: palette,
                    label: 'dca.yearChip'.trParams({'years': '$y'}),
                    selected: years.text == '$y',
                    onTap: () {
                      years.text = '$y';
                      onChange();
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Preset extends StatelessWidget {
  final SocialPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Preset({
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? SocialTokens.cyan.withValues(alpha: 0.18)
              : palette.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? SocialTokens.cyan : palette.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? SocialTokens.cyan : palette.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Labeled number field with accent icon
// ============================================================================
class _LabeledNumberField extends StatelessWidget {
  final SocialPalette palette;
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color accent;
  final String? prefix;
  final String? suffix;
  final bool isInteger;
  final ValueChanged<String> onChanged;

  const _LabeledNumberField({
    required this.palette,
    required this.controller,
    required this.label,
    required this.icon,
    required this.accent,
    required this.isInteger,
    required this.onChanged,
    this.prefix,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: !isInteger,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(isInteger ? r'[0-9]' : r'[0-9.]'),
                    ),
                  ],
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    prefixText: prefix != null ? '$prefix ' : null,
                    suffixText: suffix,
                    prefixStyle: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    suffixStyle: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Calculate button
// ============================================================================
class _CalculateButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  const _CalculateButton({
    required this.label,
    required this.onPressed,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: SocialTokens.cyan.withValues(alpha: 0.45),
            blurRadius: 18,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [SocialTokens.cyan, SocialTokens.cyanSoft],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Color(0xFF0A1628),
                      strokeWidth: 2.4,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        color: Color(0xFF0A1628),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFF0A1628),
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Yearly breakdown — list of rows with per-year progress
// ============================================================================
class _BreakdownList extends StatelessWidget {
  final SocialPalette palette;
  final Map<String, dynamic> result;
  final CurrencyController cur;

  const _BreakdownList({
    required this.palette,
    required this.result,
    required this.cur,
  });

  @override
  Widget build(BuildContext context) {
    final list = List<Map<String, dynamic>>.from(result['breakdown'] ?? []);
    if (list.isEmpty) return const SizedBox.shrink();
    final maxValue = list.fold<double>(
      0,
      (m, e) => math.max(
        m,
        (e['projected_value'] as num?)?.toDouble() ?? 0,
      ),
    );

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final item = list[i];
        final year = item['year'];
        final value = (item['projected_value'] as num?)?.toDouble() ?? 0;
        final invested = (item['invested'] as num?)?.toDouble() ?? 0;
        final progress = maxValue > 0 ? (value / maxValue).clamp(0.0, 1.0) : 0.0;

        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: SocialTokens.cyan.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Y$year',
                      style: const TextStyle(
                        color: SocialTokens.cyan,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          cur.formatPrice(value),
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            fontFeatures:
                                const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          'dca.investedRow'.trParams({
                            'amount': cur.formatPrice(invested),
                          }),
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (value > invested)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: SocialTokens.up.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '+${(((value - invested) / invested) * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: SocialTokens.up,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 5,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(color: palette.surfaceElevated),
                      ),
                      FractionallySizedBox(
                        widthFactor: progress,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [SocialTokens.cyan, SocialTokens.cyanSoft],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// Section header
// ============================================================================
class _MiniSectionHeader extends StatelessWidget {
  final SocialPalette palette;
  final String eyebrow;
  final String title;
  const _MiniSectionHeader({
    required this.palette,
    required this.eyebrow,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: const TextStyle(
              color: SocialTokens.cyan,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}
