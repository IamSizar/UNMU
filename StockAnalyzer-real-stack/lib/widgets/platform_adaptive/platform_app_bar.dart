import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../utils/platform_utils.dart';
import '../../theme/halal_fintech_theme.dart';
import '../../providers/language_provider.dart';

class PlatformAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const PlatformAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.centerTitle = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final isDarkMode = theme.brightness == Brightness.dark;
    final isRTL = languageProvider.isArabic;
    
    // Determine colors based on theme
    // Use explicit colors to ensure correct light/dark mode
    final bgColor = backgroundColor ?? 
        (isDarkMode ? HalalFintechTheme.backgroundDark : HalalFintechTheme.backgroundLight);
    final fgColor = foregroundColor ?? 
        (isDarkMode ? HalalFintechTheme.textPrimaryDark : HalalFintechTheme.textPrimaryLight);
    
    // Determine text direction
    final textDirection = isRTL ? TextDirection.rtl : TextDirection.ltr;

    if (PlatformUtils.isIOS) {
      // iOS: Use Cupertino navigation bar
      // In RTL mode, leading/trailing are automatically swapped by CupertinoNavigationBar
      return Directionality(
        textDirection: textDirection,
        child: CupertinoNavigationBar(
          middle: title != null 
              ? Text(
                  title!,
                  style: TextStyle(color: fgColor),
                ) 
              : null,
          // trailing = right in LTR, left in RTL
          trailing: actions != null && actions!.isNotEmpty
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions!,
                )
              : null,
          // leading = left in LTR, right in RTL
          leading: leading,
          backgroundColor: bgColor,
          border: null,
          transitionBetweenRoutes: false,
        ),
      );
    } else {
      // Android: Use Material AppBar
      return Directionality(
        textDirection: textDirection,
        child: AppBar(
          title: title != null ? Text(title!) : null,
          actions: actions,
          leading: leading,
          centerTitle: centerTitle,
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          elevation: 0,
        ),
      );
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

