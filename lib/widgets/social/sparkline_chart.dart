import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../screens/social/social_tokens.dart';

/// Theme-agnostic sparkline. Auto-colors itself from trend direction (up=green,
/// down=red) unless [overrideColor] is provided. Stays purely visual — no
/// axes, no labels, no interactivity. Looks identical in light and dark mode.
class SparklineChart extends StatelessWidget {
  final List<double> data;
  final Color? overrideColor;
  final double height;
  final bool showFill;
  final double strokeWidth;
  final double curve;

  const SparklineChart({
    super.key,
    required this.data,
    this.overrideColor,
    this.height = 36,
    this.showFill = true,
    this.strokeWidth = 2,
    this.curve = 0.3,
  });

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) return SizedBox(height: height);

    final lineColor =
        overrideColor ??
        (data.last >= data.first ? SocialTokens.up : SocialTokens.down);

    final spots = <FlSpot>[
      for (int i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i]),
    ];

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (data.length - 1).toDouble(),
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: curve,
              color: lineColor,
              barWidth: strokeWidth,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: showFill,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    lineColor.withValues(alpha: 0.30),
                    lineColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
