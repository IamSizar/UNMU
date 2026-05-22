import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/currency_provider.dart';
import '../screens/indexes/index_detail_screen.dart';

class IndexCard extends StatefulWidget {
  final Map<String, dynamic> index;

  const IndexCard({super.key, required this.index});

  @override
  State<IndexCard> createState() => _IndexCardState();
}

class _IndexCardState extends State<IndexCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<Color?> _pulseAnimation;
  double? _lastPrice;

  @override
  void initState() {
    super.initState();
    _lastPrice = (widget.index['price'] as num?)?.toDouble();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnimation = ColorTween(
      begin: Colors.transparent,
      end: Colors.transparent,
    ).animate(_pulseController);
  }

  @override
  void didUpdateWidget(IndexCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newPrice = (widget.index['price'] as num?)?.toDouble();
    if (newPrice != null && _lastPrice != null && newPrice != _lastPrice) {
      final isUp = newPrice > _lastPrice!;
      _triggerPulse(isUp);
      _lastPrice = newPrice;
    } else if (_lastPrice == null && newPrice != null) {
      _lastPrice = newPrice;
    }
  }

  void _triggerPulse(bool isUp) {
    _pulseAnimation = ColorTween(
      begin: isUp
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.red.withValues(alpha: 0.1),
      end: Colors.transparent,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));
    _pulseController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final symbol = widget.index['symbol']?.toString() ?? '';
    final name = widget.index['name']?.toString() ?? '';
    final price = (widget.index['price'] as num?)?.toDouble() ?? 0.0;
    final change = (widget.index['change'] as num?)?.toDouble() ?? 0.0;
    final changePercent =
        (widget.index['change_percent'] as num?)?.toDouble() ?? 0.0;
    final List<double> sparkline = List<double>.from(
      (widget.index['sparkline'] as List?)?.map((e) => (e as num).toDouble()) ??
          [],
    );

    final isPositive = change >= 0;
    final color = isPositive
        ? const Color(0xFF34C759)
        : const Color(0xFFFF3B30);

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => IndexDetailScreen(data: widget.index),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
                  _pulseAnimation.value ??
                  (isDark ? const Color(0xFF1E1E1E) : Colors.white),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white10
                    : Colors.grey.withValues(alpha: 0.1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
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
                        name,
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
                  symbol,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
          if (sparkline.isNotEmpty)
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
                    maxX: (sparkline.length - 1).toDouble(),
                    minY: sparkline.reduce((a, b) => a < b ? a : b) * 0.999,
                    maxY: sparkline.reduce((a, b) => a > b ? a : b) * 1.001,
                    lineBarsData: [
                      LineChartBarData(
                        spots: sparkline.asMap().entries.map((e) {
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
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 16),
          Consumer<CurrencyProvider>(
            builder: (context, currencyProvider, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currencyProvider.formatPrice(price),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
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
                      '${isPositive ? '+' : ''}${changePercent.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
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
