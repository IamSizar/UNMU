import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/language_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/currency_provider.dart';
import '../../localization/halal_strings.dart';
import '../../localization/app_localizations.dart';
import '../../theme/halal_fintech_theme.dart';
import '../../screens/auth/login_screen.dart';
import '../../widgets/platform_adaptive/platform_app_bar.dart';
import '../../widgets/platform_adaptive/platform_switch.dart';
import '../../widgets/platform_adaptive/platform_dialog.dart';
import '../../utils/platform_utils.dart';
import '../../utils/haptic_utils.dart';
import '../tools/dca_calculator_screen.dart';
import '../tools/zakat_calculator_screen.dart';
import '../subscription/subscription_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isArabic = context.watch<LanguageProvider>().isArabic;
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final languageProvider = context.watch<LanguageProvider>();
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      appBar: PlatformAppBar(
        title: isArabic ? HalalStringsAr.profile : HalalStrings.profile,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Settings Section
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    PlatformUtils.isIOS ? CupertinoIcons.moon : Icons.dark_mode,
                  ),
                  title: Text(
                    isArabic ? HalalStringsAr.darkMode : HalalStrings.darkMode,
                  ),
                  trailing: PlatformSwitch(
                    value: themeProvider.isDarkMode,
                    onChanged: (_) async {
                      await HapticUtils.selection();
                      themeProvider.toggleTheme();
                    },
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(
                    isArabic ? HalalStringsAr.language : HalalStrings.language,
                  ),
                  trailing: DropdownButton<String>(
                    value: languageProvider.locale.languageCode,
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(
                          isArabic
                              ? HalalStringsAr.english
                              : HalalStrings.english,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'ar',
                        child: Text(
                          isArabic
                              ? HalalStringsAr.arabic
                              : HalalStrings.arabic,
                        ),
                      ),
                    ],
                    onChanged: (value) async {
                      if (value != null) {
                        await HapticUtils.selection();
                        languageProvider.setLanguage(value);
                      }
                    },
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.attach_money),
                  title: Text(
                    isArabic ? HalalStringsAr.currency : HalalStrings.currency,
                  ),
                  trailing: Consumer<CurrencyProvider>(
                    builder: (context, currencyProvider, _) {
                      return DropdownButton<String>(
                        value: currencyProvider.selectedCurrency.code,
                        underline: const SizedBox(),
                        items: CurrencyProvider.availableCurrencies.map((c) {
                          return DropdownMenuItem(
                            value: c.code,
                            child: Text('${c.flag} ${c.code}'),
                          );
                        }).toList(),
                        onChanged: (value) async {
                          if (value != null) {
                            await HapticUtils.selection();
                            final currency = CurrencyProvider
                                .availableCurrencies
                                .firstWhere((c) => c.code == value);
                            currencyProvider.updateCurrency(currency);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Account Section
          if (authProvider.isAuthenticated) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: HalalFintechTheme.accentGreen.withValues(
                        alpha: 0.1,
                      ),
                      child: const Icon(
                        Icons.person,
                        color: HalalFintechTheme.accentGreen,
                      ),
                    ),
                    title: Text(
                      authProvider.user?.name ??
                          authProvider.user?.email ??
                          AppLocalizations(context).user,
                      style: theme.textTheme.titleMedium,
                    ),
                    subtitle: authProvider.user?.email != null
                        ? Text(
                            authProvider.user?.email ?? '',
                            style: theme.textTheme.bodyMedium,
                          )
                        : null,
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(
                      Icons.star,
                      color: authProvider.isPremium
                          ? Colors.amber
                          : Colors.grey,
                    ),
                    title: Text(
                      authProvider.isPremium
                          ? AppLocalizations(context).premiumMember
                          : AppLocalizations(context).freeMember,
                      style: TextStyle(
                        color: authProvider.isPremium
                            ? Colors.amber[700]
                            : null,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: !authProvider.isPremium
                        ? Text(AppLocalizations(context).upgradeToUnlock)
                        : null,
                    trailing: !authProvider.isPremium
                        ? TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SubscriptionScreen(),
                                ),
                              );
                            },
                            child: Text(AppLocalizations(context).upgrade),
                          )
                        : null,
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.logout,
                      color: HalalFintechTheme.haramRed,
                    ),
                    title: Text(
                      isArabic ? HalalStringsAr.logout : HalalStrings.logout,
                      style: const TextStyle(color: HalalFintechTheme.haramRed),
                    ),
                    onTap: () async {
                      await HapticUtils.lightTap();
                      final shouldLogout = await PlatformDialog.show(
                        context: context,
                        title: isArabic ? 'تسجيل الخروج' : 'Logout',
                        content: isArabic
                            ? 'هل أنت متأكد من تسجيل الخروج؟'
                            : 'Are you sure you want to logout?',
                        confirmText: isArabic ? 'تسجيل الخروج' : 'Logout',
                        cancelText: isArabic ? 'إلغاء' : 'Cancel',
                        isDestructive: true,
                      );

                      if (shouldLogout == true && context.mounted) {
                        await HapticUtils.success();
                        await authProvider.logout();
                        if (!context.mounted) return;
                        if (PlatformUtils.isIOS) {
                          Navigator.pushReplacement(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        } else {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ] else ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.login),
                title: Text(isArabic ? 'تسجيل الدخول' : 'Login'),
                onTap: () async {
                  await HapticUtils.lightTap();
                  if (PlatformUtils.isIOS) {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(builder: (_) => const LoginScreen()),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  }
                },
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Tools Section
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.calculate,
                    color: HalalFintechTheme.accentGreen,
                  ),
                  title: Text(isArabic ? 'حاسبة DCA' : 'DCA Calculator'),
                  onTap: () async {
                    await HapticUtils.lightTap();
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
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.volunteer_activism,
                    color: HalalFintechTheme.accentGreen,
                  ),
                  title: Text(isArabic ? 'حاسبة الزكاة' : 'Zakat Calculator'),
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
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // App Info Section
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(isArabic ? 'حول التطبيق' : 'About'),
                  onTap: () async {
                    await HapticUtils.lightTap();
                    PlatformDialog.show(
                      context: context,
                      title: isArabic ? 'حول التطبيق' : 'About',
                      content: isArabic
                          ? 'تطبيق تحليل الأسهم الحلال\nالإصدار 1.0.0'
                          : 'Halal Stocks Analytics App\nVersion 1.0.0',
                      confirmText: isArabic ? 'إغلاق' : 'Close',
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: Text(isArabic ? 'المساعدة' : 'Help'),
                  onTap: () async {
                    await HapticUtils.lightTap();
                    PlatformDialog.show(
                      context: context,
                      title: isArabic ? 'المساعدة' : 'Help',
                      content: isArabic
                          ? 'للمساعدة والدعم، يرجى التواصل معنا عبر البريد الإلكتروني.'
                          : 'For help and support, please contact us via email.',
                      confirmText: isArabic ? 'إغلاق' : 'Close',
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
