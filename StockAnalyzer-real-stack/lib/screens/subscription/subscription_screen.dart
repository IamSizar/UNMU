import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../localization/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../theme/halal_fintech_theme.dart';
import '../../widgets/platform_adaptive/platform_app_bar.dart';
import '../../widgets/platform_adaptive/platform_button.dart';
import '../../widgets/platform_adaptive/platform_dialog.dart';
import '../../services/promo_service.dart';
import '../../services/iap_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isLoading = false;
  late final IAPService _iapService;

  @override
  void initState() {
    super.initState();
    _iapService = IAPService();
    _iapService.addListener(_onIAPChanged);
    _iapService.initialize();
  }

  @override
  void dispose() {
    _iapService.removeListener(_onIAPChanged);
    super.dispose();
  }

  void _onIAPChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handlePurchase(ProductDetails product) async {
    setState(() => _isLoading = true);
    try {
      await _iapService.buySubscription(product);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations(context);
        PlatformDialog.show(
          context: context,
          title: l10n.error,
          content: '${l10n.error}: $e',
          confirmText: l10n.ok,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isPremium = authProvider.isPremium;
    final l10n = AppLocalizations(context);

    return Scaffold(
      appBar: PlatformAppBar(title: l10n.subscriptionPlans),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildPlanCard(
              context,
              title: l10n.freePlan,
              price: '\$0 / Month', // Or fallback l10n.perMonth
              features: [
                l10n.basicStockSearch,
                l10n.limitedScreeningReports,
                l10n.adSupported,
              ],
              isActive: !isPremium,
              isCurrent: !isPremium,
              onTap: null, // Cannot downgrade to free explicitly in this UI yet
            ),
            const SizedBox(height: 16),
            if (_iapService.isLoading || _isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_iapService.products.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Products unavailable or Store is configured improperly.',
                ),
              )
            else
              ..._iapService.products.map((product) {
                final isAnnual = product.id == IAPService.annualSubscriptionId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildPlanCard(
                    context,
                    title: isAnnual ? 'Premium Annual' : 'Premium Monthly',
                    price: product.price,
                    features: [
                      l10n.unlimitedScreening,
                      l10n.advancedCharts,
                      l10n.adFreeExperience,
                      l10n.prioritySupport,
                    ],
                    isActive: isPremium,
                    isCurrent: isPremium,
                    isRecommended: isAnnual,
                    onTap: isPremium ? null : () => _handlePurchase(product),
                    isLoading: _isLoading && !isPremium,
                  ),
                );
              }),
            const SizedBox(height: 24),
            const _PromoCodeSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(
    BuildContext context, {
    required String title,
    required String price,
    required List<String> features,
    required bool isActive,
    required bool isCurrent,
    bool isRecommended = false,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations(context);
    final borderColor = isRecommended
        ? HalalFintechTheme.accentGreen
        : Colors.grey.withOpacity(0.3);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isRecommended ? 2 : 1),
        boxShadow: isRecommended
            ? [
                BoxShadow(
                  color: HalalFintechTheme.accentGreen.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isRecommended)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: const BoxDecoration(
                color: HalalFintechTheme.accentGreen,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: Text(
                l10n.recommended,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  price,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: HalalFintechTheme.accentGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                ...features.map(
                  (feature) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: HalalFintechTheme.accentGreen,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(feature, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (isCurrent)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.currentPlan,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : PlatformButton(
                          label: l10n.upgradeNow,
                          onPressed: onTap,
                          isPrimary: true,
                        ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PromoCodeSection extends StatefulWidget {
  const _PromoCodeSection();

  @override
  State<_PromoCodeSection> createState() => _PromoCodeSectionState();
}

class _PromoCodeSectionState extends State<_PromoCodeSection> {
  final _promoController = TextEditingController();
  bool _isLoading = false;
  String? _message;
  bool _isValid = false;

  Future<void> _validatePromo() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      // Import PromoService first
      final result = await PromoService.validatePromo(code);
      if (!mounted) return;

      setState(() {
        _isValid = result['valid'] == true;
        _message = result['message'];

        if (_isValid) {
          // In a real app, apply discount here
          // For now, just showing success
        }
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.havePromoCode,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promoController,
                  decoration: InputDecoration(
                    hintText: l10n.enterCode,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PlatformButton(
                label: l10n.apply,
                onPressed: _isLoading ? null : _validatePromo,
                isPrimary: false,
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: TextStyle(
                color: _isValid
                    ? HalalFintechTheme.accentGreen
                    : HalalFintechTheme.haramRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
