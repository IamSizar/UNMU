import 'package:flutter/material.dart';

import '../../screens/social/social_tokens.dart';

/// Compact green/red percentage chip used everywhere a price change is shown.
/// Looks identical across dark/light because the up/down hues are
/// intentionally consistent with market conventions.
class PriceIndicator extends StatelessWidget {
  final double changePct;
  final double fontSize;
  final bool dense;
  final bool bold;

  const PriceIndicator({
    super.key,
    required this.changePct,
    this.fontSize = 12,
    this.dense = false,
    this.bold = true,
  });

  @override
  Widget build(BuildContext context) {
    final isUp = changePct >= 0;
    final color = isUp ? SocialTokens.up : SocialTokens.down;
    final sign = isUp ? '+' : '';
    final arrow = isUp ? Icons.north_east_rounded : Icons.south_east_rounded;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(arrow, color: color, size: fontSize),
          SizedBox(width: dense ? 2 : 3),
          Text(
            '$sign${changePct.toStringAsFixed(2)}%',
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: fontSize,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
