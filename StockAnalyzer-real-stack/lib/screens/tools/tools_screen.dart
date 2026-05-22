import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../providers/language_provider.dart';
import '../../localization/halal_strings.dart';
import '../../theme/halal_fintech_theme.dart';
import '../../widgets/platform_adaptive/platform_app_bar.dart';
import '../../utils/platform_utils.dart';
import '../../utils/haptic_utils.dart';
import 'zakat_calculator_screen.dart';
import 'dca_calculator_screen.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isArabic = context.watch<LanguageProvider>().isArabic;
    // Using static strings directly
    final theme = Theme.of(context);

    return Scaffold(
      appBar: PlatformAppBar(
        title: isArabic ? HalalStringsAr.tools : HalalStrings.tools,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Zakat Calculator Card
          Card(
            elevation: 0,
            child: InkWell(
              onTap: () async {
                await HapticUtils.lightTap();
                if (!context.mounted) return;
                if (PlatformUtils.isIOS) {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => const ZakatCalculatorScreen(),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ZakatCalculatorScreen(),
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: HalalFintechTheme.accentGreen.withValues(
                          alpha: 0.1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.calculate,
                        color: HalalFintechTheme.accentGreen,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isArabic
                                ? HalalStringsAr.zakatCalculator
                                : HalalStrings.zakatCalculator,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isArabic
                                ? 'احسب الزكاة على محفظتك'
                                : 'Calculate Zakat on your portfolio',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      PlatformUtils.isIOS
                          ? CupertinoIcons.chevron_right
                          : Icons.chevron_right,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // DCA Calculator Card
          Card(
            elevation: 0,
            child: InkWell(
              onTap: () async {
                await HapticUtils.lightTap();
                if (!context.mounted) return;

                if (PlatformUtils.isIOS) {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => const DcaCalculatorScreen(),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DcaCalculatorScreen(),
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: HalalFintechTheme.accentGreen.withValues(
                          alpha: 0.1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.trending_up,
                        color: HalalFintechTheme.accentGreen,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isArabic
                                ? HalalStringsAr.dcaCalculator
                                : HalalStrings.dcaCalculator,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isArabic
                                ? 'احسب نمو الاستثمار طويل الأجل'
                                : 'Calculate long-term investment growth',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      PlatformUtils.isIOS
                          ? CupertinoIcons.chevron_right
                          : Icons.chevron_right,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
