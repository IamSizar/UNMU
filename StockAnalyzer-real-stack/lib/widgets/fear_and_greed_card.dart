import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../localization/app_localizations.dart';
import '../providers/stocks_provider.dart';
import '../screens/indexes/index_detail_screen.dart';

class FearAndGreedCard extends StatelessWidget {
  const FearAndGreedCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<StocksProvider>();
    final data = provider.fearAndGreedData;

    // Attempt to get a primary benchmark (e.g. S&P 500 or global) to show market price/change
    Map<String, dynamic>? primaryIndex;
    final benchmarks = provider.marketIndexes
        .where(
          (idx) =>
              idx['category'] == 'Benchmarks' || idx['category'] == 'Global',
        )
        .toList();
    if (benchmarks.isNotEmpty) {
      primaryIndex = benchmarks.first;
    }

    // Default values if loading or error
    final value = data?['value'] as int? ?? 50;
    final label = data?['label'] as String? ?? 'Neutral';
    final colorHex = data?['color'] as String? ?? '#FFCC00';
    final trend = List<int>.from(data?['trend'] ?? []);
    final color = _parseColor(colorHex);

    // For the chart, if we only have one point, we can't draw a line.
    // Let's duplicate it for a flat line effect if there's only one point.
    final chartTrend = [...trend];
    if (chartTrend.length == 1) {
      chartTrend.insert(0, chartTrend[0]);
    }

    return GestureDetector(
      onTap: () {
        if (data != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  IndexDetailScreen(data: data, isSentiment: true),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.marketSentiment,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const _LiveIndicator(),
                    ],
                  ),
                  Text(
                    l10n.fearAndGreedIndex,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (chartTrend.isNotEmpty)
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 40,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      minX: 0,
                      maxX: (chartTrend.length - 1).toDouble(),
                      minY: 0,
                      maxY: 100,
                      lineBarsData: [
                        LineChartBarData(
                          spots: chartTrend.asMap().entries.map((e) {
                            return FlSpot(e.key.toDouble(), e.value.toDouble());
                          }).toList(),
                          isCurved: true,
                          color: color,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: color.withValues(alpha: 0.1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 8),
            // Right Side: Values
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Fear & Greed Value
                Row(
                  children: [
                    Text(
                      '$value',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _localizeLabel(context, label),
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (primaryIndex != null) ...[
                  const SizedBox(height: 8),
                  // Market Benchmark Data
                  _buildMarketDataRow(context, primaryIndex),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketDataRow(
    BuildContext context,
    Map<String, dynamic> indexData,
  ) {
    final theme = Theme.of(context);
    final currentPrice =
        (indexData['current_price'] as num?)?.toDouble() ?? 0.0;
    final priceChange = (indexData['price_change'] as num?)?.toDouble() ?? 0.0;
    final percentChange =
        (indexData['percent_change'] as num?)?.toDouble() ?? 0.0;

    final isPositive = priceChange >= 0;
    final changeColor = isPositive
        ? const Color(0xFF34C759)
        : const Color(0xFFFF3B30);
    final icon = isPositive ? Icons.arrow_upward : Icons.arrow_downward;
    final sign = isPositive ? '+' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Current Price
        Text(
          currentPrice.toStringAsFixed(2),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        // Increase/Decrease and Percent
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: changeColor, size: 14),
            const SizedBox(width: 4),
            Text(
              '$sign${priceChange.toStringAsFixed(2)} ($sign${percentChange.toStringAsFixed(2)}%)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: changeColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _localizeLabel(BuildContext context, String label) {
    if (!AppLocalizations(context).isArabic) return label;

    switch (label) {
      case 'Extreme Fear':
        return 'خوف شديد';
      case 'Fear':
        return 'خوف';
      case 'Neutral':
        return 'محايد';
      case 'Greed':
        return 'طمع';
      case 'Extreme Greed':
        return 'طمع شديد';
      default:
        return label;
    }
  }

  Color _parseColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    try {
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      return Colors.grey;
    }
  }
}

class _LiveIndicator extends StatefulWidget {
  const _LiveIndicator();

  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Color(0xFF34C759),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
