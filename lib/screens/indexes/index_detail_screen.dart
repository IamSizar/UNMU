import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/currency_controller.dart';
import '../../controllers/stocks_controller.dart';
import '../../widgets/platform_adaptive/platform_app_bar.dart';
import '../../localization/locale_format.dart';
import 'share_index_chart_sheet.dart';

class IndexDetailScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool isSentiment;

  const IndexDetailScreen({
    super.key,
    required this.data,
    this.isSentiment = false,
  });

  @override
  State<IndexDetailScreen> createState() => _IndexDetailScreenState();
}

class _IndexDetailScreenState extends State<IndexDetailScreen> {
  String _selectedRange = 'ALL';

  String _getLocalizedCategory(BuildContext context, String? category) {
    if (category == null) return 'indexes.market'.tr;
    switch (category) {
      case 'Benchmarks':
        return 'indexes.category.benchmarks'.tr;
      case 'Macro':
        return 'indexes.category.macro'.tr;
      case 'Health':
        return 'indexes.category.health'.tr;
      default:
        return category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final name =
        widget.data['name']?.toString() ??
        (widget.isSentiment
            ? 'indexes.marketSentiment'.tr
            : 'indexes.indexSingular'.tr);
    final symbol =
        widget.data['symbol']?.toString() ?? (widget.isSentiment ? 'F&G' : '');

    // Get primary index if this is the sentiment view
    Map<String, dynamic>? primaryIndex;
    if (widget.isSentiment) {
      final provider = Get.find<StocksController>();
      final benchmarks = provider.marketIndexes
          .where(
            (idx) =>
                idx['category'] == 'Benchmarks' || idx['category'] == 'Global',
          )
          .toList();
      if (benchmarks.isNotEmpty) {
        primaryIndex = benchmarks.first;
      }
    }

    final price = widget.isSentiment
        ? (widget.data['value'] as num?)?.toDouble() ?? 0.0
        : (widget.data['price'] as num?)?.toDouble() ?? 0.0;
    final change = widget.isSentiment
        ? 0.0
        : (widget.data['change'] as num?)?.toDouble() ?? 0.0;
    final changePercent = widget.isSentiment
        ? 0.0
        : (widget.data['change_percent'] as num?)?.toDouble() ?? 0.0;

    final List<double> fullChartData = List<double>.from(
      (widget.data[widget.isSentiment ? 'trend' : 'sparkline'] as List?)?.map(
            (e) => (e as num).toDouble(),
          ) ??
          [],
    );

    final List<String> fullChartDates = List<String>.from(
      (widget.data[widget.isSentiment ? 'trend_dates' : 'sparkline_dates']
              as List?) ??
          [],
    );

    // Filter data based on range
    List<double> chartData = fullChartData;
    List<String> chartDates = fullChartDates;

    if (fullChartData.isNotEmpty) {
      int points = fullChartData.length;
      switch (_selectedRange) {
        case '1D':
          points = 1;
          break;
        case '5D':
          points = 5;
          break;
        case '1M':
          points = 22; // approx trading days
          break;
        case '3M':
          points = 66;
          break;
        case 'ALL':
        default:
          points = fullChartData.length;
          break;
      }

      if (points < fullChartData.length) {
        chartData = fullChartData.sublist(fullChartData.length - points);
        if (fullChartDates.length == fullChartData.length) {
          chartDates = fullChartDates.sublist(fullChartDates.length - points);
        }
      }
    }

    final isPositive = change >= 0 || widget.isSentiment;
    final color = widget.isSentiment
        ? _parseColor(widget.data['color'] as String? ?? '#FFCC00')
        : (isPositive ? const Color(0xFF34C759) : const Color(0xFFFF3B30));

    // Experts get a Share button (indexes only, not the sentiment view) that
    // turns the chart into a branded image they can post to their profile or
    // a community. Regular users don't see it.
    final isExpert = Get.find<AuthController>().user?.isExpert ?? false;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.grey[50],
      appBar: PlatformAppBar(
        title: name,
        actions: (isExpert && !widget.isSentiment && fullChartData.isNotEmpty)
            ? [
                IconButton(
                  tooltip: 'indexes.share'.tr,
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () => showShareIndexChartSheet(
                    context,
                    name: name,
                    symbol: symbol,
                    value: price,
                    changePercent: changePercent,
                    sparkline: fullChartData,
                    color: color,
                  ),
                ),
              ]
            : null,
      ),
      body: CustomScrollView(
        slivers: [
          // Chart Section
          SliverToBoxAdapter(
            child: Column(
              children: [
                Container(
                  height: 300,
                  padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
                  child: chartData.isNotEmpty
                      ? _DetailedChart(
                          chartData: chartData,
                          chartDates: chartDates,
                          color: color,
                          isDark: isDark,
                        )
                      : Center(child: Text('indexes.noHistoricalData'.tr)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: _RangeSelector(
                    selectedRange: _selectedRange,
                    onRangeSelected: (range) {
                      setState(() {
                        _selectedRange = range;
                      });
                    },
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ),

          // Main Stats
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isSentiment
                            ? 'indexes.currentValue'.tr
                            : 'indexes.currentPrice'.tr,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Sentiment is a plain 0–100 value (no currency), so it
                      // must NOT be wrapped in Obx — an Obx that reads no
                      // observable trips GetX's "improper use" assertion.
                      // Only the currency-formatted price needs reactivity.
                      widget.isSentiment
                          ? Text(
                              '$price',
                              style: theme.textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : Obx(() {
                              final currencyProvider =
                                  Get.find<CurrencyController>();
                              return Text(
                                currencyProvider.formatPrice(price),
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            }),
                      if (widget.isSentiment && primaryIndex != null) ...[
                        const SizedBox(height: 12),
                        _buildMarketDataRow(context, primaryIndex),
                      ],
                      if (!widget.isSentiment) ...[
                        const SizedBox(height: 12),
                        Text(
                          'indexes.dayChange'.tr,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isDark ? Colors.white54 : Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Obx(() {
                          final currencyProvider = Get.find<CurrencyController>();
                          final formattedChange = currencyProvider
                              .formatPrice(change.abs());
                          return Text(
                            '${isPositive ? '+' : '-'}$formattedChange (${changePercent.toStringAsFixed(2)}%)',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                  if (widget.isSentiment)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.data['label']?.toString() ?? 'indexes.neutral'.tr,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Details Grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 2.5,
              children: [
                _StatCard(
                  label: 'indexes.symbol'.tr,
                  value: symbol,
                  isDark: isDark,
                ),
                _StatCard(
                  label: 'indexes.category'.tr,
                  value: _getLocalizedCategory(
                    context,
                    widget.data['category']?.toString(),
                  ),
                  isDark: isDark,
                ),
                _StatCard(
                  label: 'indexes.lastUpdate'.tr,
                  value: 'indexes.justNow'.tr,
                  isDark: isDark,
                ),
                _StatCard(
                  label: 'indexes.dataSource'.tr,
                  value: 'indexes.liveFeed'.tr,
                  isDark: isDark,
                ),
              ],
            ),
          ),

          // About Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    'indexes.aboutIndex'.tr,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _getAboutText(context, symbol, widget.isSentiment),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white70 : Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'indexes.references'.tr,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'indexes.referencesContent'.tr,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'indexes.market'.tr,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.brightness == Brightness.dark
                ? Colors.white54
                : Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Obx(() {
          final currencyProvider = Get.find<CurrencyController>();
          final formattedPrice = currencyProvider.formatPrice(currentPrice);
          return Text(
            formattedPrice,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          );
        }),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: changeColor, size: 14),
            const SizedBox(width: 4),
            Obx(() {
              final currencyProvider = Get.find<CurrencyController>();
              final formattedChange = currencyProvider.formatPrice(
                priceChange.abs(),
              );
              return Text(
                '$sign$formattedChange ($sign${percentChange.toStringAsFixed(2)}%)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: changeColor,
                  fontWeight: FontWeight.bold,
                ),
              );
            }
            ),
          ],
        ),
      ],
    );
  }

  String _getAboutText(BuildContext context, String symbol, bool isSentiment) {
    if (isSentiment) {
      return 'indexes.descSentiment'.tr;
    }

    switch (symbol.toUpperCase()) {
      case 'SPY':
        return 'indexes.descSPY'.tr;
      case 'QQQ':
        return 'indexes.descQQQ'.tr;
      case 'DIA':
        return 'indexes.descDIA'.tr;
      case 'TNX':
        return 'indexes.descTNX'.tr;
      case 'VXX':
        return 'indexes.descVXX'.tr;
      case 'CL':
        return 'indexes.descCL'.tr;
      default:
        return 'indexes.descGeneric'.tr;
    }
  }

  Color _parseColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    try {
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }
}

class _DetailedChart extends StatelessWidget {
  final List<double> chartData;
  final List<String> chartDates;
  final Color color;
  final bool isDark;

  const _DetailedChart({
    required this.chartData,
    required this.chartDates,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (chartData.isEmpty) return const SizedBox();

    final minVal = chartData.reduce((a, b) => a < b ? a : b);
    final maxVal = chartData.reduce((a, b) => a > b ? a : b);
    double padding = (maxVal - minVal) * 0.15;
    if (padding == 0) {
      padding = maxVal == 0 ? 1.0 : maxVal.abs() * 0.1;
    }


    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxVal - minVal + padding * 2) / 4,
          getDrawingHorizontalLine: (value) => FlLine(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.1),
            strokeWidth: 1,
            dashArray: [4, 4], // Dotted lines
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == minVal - padding || value == maxVal + padding) {
                  return const SizedBox();
                }
                return Text(
                  value.toStringAsFixed(2),
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: (chartData.length / 5).clamp(1, 100).toDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= chartDates.length) {
                  return const SizedBox();
                }

                try {
                  final date = DateTime.parse(chartDates[index]);
                  final label = LocaleFormat.time(date);
                  final isLongRange = chartDates.length > 20;
                  final text = isLongRange
                      ? LocaleFormat.monthDay(date)
                      : label;

                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      text,
                      style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontSize: 10,
                      ),
                    ),
                  );
                } catch (e) {
                  return const SizedBox();
                }
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (chartData.length - 1).toDouble(),
        minY: minVal - padding,
        maxY: maxVal + padding,
        lineBarsData: [
          LineChartBarData(
            spots: chartData.asMap().entries.map((e) {
              return FlSpot(e.key.toDouble(), e.value);
            }).toList(),
            isCurved: true,
            color: color,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.2),
                  color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          getTouchedSpotIndicator:
              (LineChartBarData barData, List<int> spotIndexes) {
                return spotIndexes.map((spotIndex) {
                  return TouchedSpotIndicatorData(
                    FlLine(
                      color: isDark ? Colors.white24 : Colors.black26,
                      strokeWidth: 2,
                      dashArray: [5, 5], // Vertical dotted crosshair
                    ),
                    FlDotData(
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 6,
                          color: color,
                          strokeWidth: 3,
                          strokeColor: isDark ? Colors.black : Colors.white,
                        );
                      },
                    ),
                  );
                }).toList();
              },
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: const Color(0xFF333333),
            tooltipRoundedRadius: 8,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.x.toInt();
                String dateLabel = '';
                if (index >= 0 && index < chartDates.length) {
                  try {
                    final date = DateTime.parse(chartDates[index]);
                    dateLabel = LocaleFormat.time(date);
                  } catch (_) {}
                }

                final price = spot.y.toStringAsFixed(2);

                return LineTooltipItem(
                  '\$$price\n',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  children: [
                    TextSpan(
                      text: dateLabel,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  final String selectedRange;
  final Function(String) onRangeSelected;
  final bool isDark;

  const _RangeSelector({
    required this.selectedRange,
    required this.onRangeSelected,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final ranges = ['1D', '5D', '1M', '3M', '6M', 'YTD', '1Y', '5Y', 'ALL'];
    final localizedRanges = {
      '1D': 'indexes.range1D'.tr,
      '5D': 'indexes.range5D'.tr,
      '1M': 'indexes.range1M'.tr,
      '3M': 'indexes.range3M'.tr,
      '6M': 'indexes.range6M'.tr,
      'YTD': 'indexes.rangeYTD'.tr,
      '1Y': 'indexes.range1Y'.tr,
      '5Y': 'indexes.range5Y'.tr,
      'ALL': 'indexes.rangeAll'.tr,
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ranges.map((range) {
          final isSelected = selectedRange == range;
          return GestureDetector(
            onTap: () => onRangeSelected(range),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: isSelected
                    ? const Border(
                        bottom: BorderSide(color: Colors.blueAccent, width: 3),
                      )
                    : null,
              ),
              child: Text(
                localizedRanges[range] ?? range,
                style: TextStyle(
                  color: isSelected
                      ? (isDark ? Colors.blueAccent : Colors.blue[700])
                      : (isDark ? Colors.white38 : Colors.black38),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _StatCard({
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
