import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../theme/halal_fintech_theme.dart';
import '../../widgets/platform_adaptive/platform_app_bar.dart';
import '../../widgets/platform_adaptive/platform_button.dart';
import '../../widgets/platform_adaptive/platform_dialog.dart';
import '../../services/promo_service.dart';
import '../../services/iap_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isLoading = false;
  final IAPService _iapService = IAPService.instance;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: bootstrap is idempotent and loadProducts caches
    // results in the service's RxList so an Obx rebuilds the body.
    _initStore();
  }

  Future<void> _initStore() async {
    await _iapService.bootstrap();
    await _iapService.loadProducts({
      IAPService.monthlySubscriptionId,
      IAPService.annualSubscriptionId,
    });
  }

  Future<void> _handlePurchase(IAPProduct product) async {
    setState(() => _isLoading = true);
    final result = await _iapService.buy(product);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!result.ok) {
      PlatformDialog.show(
        context: context,
        title: 'common.error'.tr,
        content: result.error ?? 'common.error'.tr,
        confirmText: 'common.ok'.tr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Get.find<AuthController>();
    final isPremium = authProvider.isPremium;

    return Scaffold(
      appBar: PlatformAppBar(title: 'subscription.title'.tr),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildPlanCard(
              context,
              title: 'subscription.planFree'.tr,
              price: '\$0 ${'subscription.perMonth'.tr}',
              features: [
                'subscription.feature.basicStockSearch'.tr,
                'subscription.feature.limitedReports'.tr,
                'subscription.feature.adSupported'.tr,
              ],
              isActive: !isPremium,
              isCurrent: !isPremium,
              onTap: null, // Cannot downgrade to free explicitly in this UI yet
            ),
            const SizedBox(height: 16),
            Obx(() {
              if (_iapService.isPurchasing.value || _isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_iapService.products.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('subscription.productsUnavailable'.tr),
                );
              }
              return Column(
                children: _iapService.products.map((product) {
                  final isAnnual = product.id == IAPService.annualSubscriptionId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildPlanCard(
                      context,
                      title: isAnnual
                          ? 'subscription.planPremiumAnnual'.tr
                          : 'subscription.planPremiumMonthly'.tr,
                      price: product.price,
                      features: [
                        'subscription.feature.unlimitedScreening'.tr,
                        'subscription.feature.advancedCharts'.tr,
                        'subscription.feature.adFree'.tr,
                        'subscription.feature.prioritySupport'.tr,
                      ],
                      isActive: isPremium,
                      isCurrent: isPremium,
                      isRecommended: isAnnual,
                      onTap: isPremium ? null : () => _handlePurchase(product),
                      isLoading: _isLoading && !isPremium,
                    ),
                  );
                }).toList(),
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
    final borderColor = isRecommended
        ? HalalFintechTheme.accentGreen
        : Colors.grey.withValues(alpha: 0.3);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isRecommended ? 2 : 1),
        boxShadow: isRecommended
            ? [
                BoxShadow(
                  color: HalalFintechTheme.accentGreen.withValues(alpha: 0.2),
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
                'subscription.recommended'.tr,
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
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'subscription.currentPlan'.tr,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : PlatformButton(
                          label: 'subscription.upgradeNow'.tr,
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'subscription.promo.title'.tr,
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
                    hintText: 'subscription.promo.hint'.tr,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PlatformButton(
                label: 'subscription.promo.apply'.tr,
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
