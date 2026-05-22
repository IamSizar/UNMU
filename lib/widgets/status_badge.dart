import 'package:flutter/material.dart';
import '../theme/halal_fintech_theme.dart';
import 'package:get/get.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final String? grade;

  const StatusBadge({super.key, required this.status, this.grade});

  @override
  Widget build(BuildContext context) {
    final statusColor = HalalFintechTheme.getStatusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          // If grade is present, show it as the primary indicator
          if (grade != null) ...[
            Text(
              '${'statusBadge.grade'.tr} $grade',
              style: TextStyle(
                color: statusColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ] else ...[
            Text(
              _getStatusLabel(status),
              style: TextStyle(
                color: statusColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getStatusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'HALAL':
        return 'statusBadge.halal'.tr;
      case 'HARAM':
      case 'NOT_HALAL':
        return 'statusBadge.haram'.tr;
      case 'MIXED':
        return 'statusBadge.mixed'.tr;
      default:
        return 'statusBadge.unknown'.tr;
    }
  }
}
