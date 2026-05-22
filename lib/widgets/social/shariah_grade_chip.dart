import 'package:flutter/material.dart';

import '../../theme/halal_fintech_theme.dart';

/// Tiny grade chip (A/B/C/F) using the existing Shariah grade colors.
/// Theme-neutral by design — same colors mean the same thing regardless of
/// dark or light mode.
class ShariahGradeChip extends StatelessWidget {
  final String grade;
  final double size;
  final bool filled;

  const ShariahGradeChip({
    super.key,
    required this.grade,
    this.size = 18,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = HalalFintechTheme.getGradeColor(grade);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.16),
        border: Border.all(color: color, width: 1.4),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        grade,
        style: TextStyle(
          color: filled ? Colors.white : color,
          fontSize: size * 0.55,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
