import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../utils/platform_utils.dart';
import '../../theme/halal_fintech_theme.dart';

class PlatformButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final IconData? icon;

  const PlatformButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isPrimary = true,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformUtils.isIOS) {
      // iOS: Use standard CupertinoButton
      final childWidget = icon != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isPrimary
                      ? Colors.white
                      : HalalFintechTheme.accentGreen,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isPrimary
                        ? Colors.white
                        : HalalFintechTheme.accentGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            )
          : Text(
              label,
              style: TextStyle(
                color: isPrimary ? Colors.white : HalalFintechTheme.accentGreen,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            );

      return CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isPrimary ? HalalFintechTheme.accentGreen : null,
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(12), minimumSize: Size(48, 48),
        child: childWidget,
      );
    } else {
      // Android: Use Material button
      if (icon != null) {
        return ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor: isPrimary ? HalalFintechTheme.accentGreen : null,
            foregroundColor: isPrimary ? Colors.white : null,
          ),
        );
      }
      return ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? HalalFintechTheme.accentGreen : null,
          foregroundColor: isPrimary ? Colors.white : null,
        ),
        child: Text(label),
      );
    }
  }
}
