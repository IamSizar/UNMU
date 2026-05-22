import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../screens/social/social_tokens.dart';
import 'price_indicator.dart';
import 'shariah_grade_chip.dart';

/// Premium TradingView-style price chart used inside Expert profile and
/// Community detail screens. Theme-reactive — surfaces, grid, and tooltip
/// colors flip with the app's brightness.
class TradingChart extends StatefulWidget {
  final String ticker;
  final double price;
  final double changePct;
  final String shariahGrade;
  final List<double> data;

  const TradingChart({
    super.key,
    required this.ticker,
    required this.price,
    required this.changePct,
    required this.shariahGrade,
    required this.data,
  });

  @override
  State<TradingChart> createState() => _TradingChartState();
}

class _TradingChartState extends State<TradingChart> {
  static const _timeframes = ['1D', '1W', '1M', '1Y'];
  String _selected = '1D';
  // Tracks the last index the user's finger was over, so we only fire a
  // tick haptic when the index actually changes (not on every pan event).
  int? _lastTouchedIndex;

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final isUp = widget.changePct >= 0;
    final lineColor = isUp ? SocialTokens.up : SocialTokens.down;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: palette.premiumCardGradient(lineColor),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
        boxShadow: [
          if (palette.isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 18,
              offset: const Offset(0, 6),
            )
          else
            BoxShadow(
              color: const Color(0xFF152033).withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(palette),
          const SizedBox(height: 18),
          SizedBox(height: 220, child: _buildChart(palette, lineColor)),
          const SizedBox(height: 12),
          _buildTimeframePills(palette),
        ],
      ),
    );
  }

  Widget _buildHeader(SocialPalette palette) {
    return Row(
      children: [
        ShariahGradeChip(grade: widget.shariahGrade, size: 26, filled: true),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.ticker,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 19,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: SocialTokens.up,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'tradingChart.liveDemo'.tr,
                  style: TextStyle(color: palette.textMuted, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.price.toStringAsFixed(2),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 22,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            PriceIndicator(changePct: widget.changePct, fontSize: 12),
          ],
        ),
      ],
    );
  }

  Widget _buildChart(SocialPalette palette, Color lineColor) {
    if (widget.data.length < 2) {
      return Center(
        child: Text(
          'tradingChart.noData'.tr,
          style: TextStyle(color: palette.textMuted),
        ),
      );
    }

    final spots = <FlSpot>[
      for (int i = 0; i < widget.data.length; i++)
        FlSpot(i.toDouble(), widget.data[i]),
    ];

    final minY = widget.data.reduce((a, b) => a < b ? a : b);
    final maxY = widget.data.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) * 0.18;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (widget.data.length - 1).toDouble(),
        minY: minY - pad,
        maxY: maxY + pad,
        backgroundColor: Colors.transparent,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: palette.subtleDivider,
            strokeWidth: 1,
            dashArray: const [4, 6],
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: (maxY - minY) / 3,
              getTitlesWidget: (value, _) => Text(
                value.toStringAsFixed(0),
                style: TextStyle(color: palette.textMuted, fontSize: 10),
              ),
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          enabled: true,
          // Tick the user's finger as it crosses each data point, like a
          // proper trading-app scrub. Only fires when the index actually
          // changes (not every micro pan event) so it never feels like a
          // continuous buzz.
          touchCallback: (event, response) {
            // Reset when the gesture ends so the next swipe starts fresh.
            if (event is FlTapUpEvent ||
                event is FlPanEndEvent ||
                event is FlPanCancelEvent) {
              _lastTouchedIndex = null;
              return;
            }
            final spots = response?.lineBarSpots;
            if (spots == null || spots.isEmpty) return;
            final idx = spots.first.spotIndex;
            if (idx != _lastTouchedIndex) {
              _lastTouchedIndex = idx;
              HapticFeedback.selectionClick();
            }
          },
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: palette.surfaceElevated,
            tooltipRoundedRadius: 8,
            getTooltipItems: (touched) => touched
                .map(
                  (s) => LineTooltipItem(
                    s.y.toStringAsFixed(2),
                    TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: lineColor,
            barWidth: 2.6,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  lineColor.withValues(alpha: palette.isDark ? 0.32 : 0.22),
                  lineColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeframePills(SocialPalette palette) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _timeframes.map((tf) {
        final selected = tf == _selected;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selected = tf);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? SocialTokens.cyan.withValues(alpha: 0.18)
                    : palette.surfaceElevated,
                border: Border.all(
                  color: selected ? SocialTokens.cyan : palette.border,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                tf,
                style: TextStyle(
                  color: selected ? SocialTokens.cyan : palette.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
