// Bottom sheet that buys access to an expert or a paid community through
// the App Store (iOS) or Google Play (Android) — the only way to pay since
// cash/FIB were cut off (docs/payments/IAP_ONLY_PLAN.md).
//
// The target's price tier picks the store product; the store's localized
// price is shown once it loads (USD tier price until then). Pops with true
// once the backend has granted access.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../models/expert_subscription.dart';
import '../../services/iap_access.dart';
import '../../services/iap_service.dart';
import '../platform_adaptive/platform_spinner.dart';

class StorePurchaseSheet extends StatefulWidget {
  final String name;
  final AccessTarget target;
  final String? tier;
  final SubPlan initialPlan;

  const StorePurchaseSheet({
    super.key,
    required this.name,
    required this.target,
    required this.tier,
    this.initialPlan = SubPlan.monthly,
  });

  /// Opens the sheet; true when access was granted.
  static Future<bool> show(
    BuildContext context, {
    required String name,
    required AccessTarget target,
    required String? tier,
    SubPlan initialPlan = SubPlan.monthly,
  }) async {
    final granted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StorePurchaseSheet(
        name: name,
        target: target,
        tier: tier,
        initialPlan: initialPlan,
      ),
    );
    return granted ?? false;
  }

  @override
  State<StorePurchaseSheet> createState() => _StorePurchaseSheetState();
}

class _StorePurchaseSheetState extends State<StorePurchaseSheet> {
  final IAPService _iap = IAPService.instance;
  late SubPlan _plan = widget.initialPlan;
  bool _loading = true;
  bool _buying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final ids = SubPlan.values
        .map((p) => AccessTiers.productId(widget.tier, p))
        .whereType<String>()
        .toSet();
    String? error;
    if (ids.isEmpty) {
      error = 'subscribe.error.noPrice'.tr;
    } else {
      await _iap.bootstrap();
      if (!_iap.isAvailable.value) {
        error = 'subscribe.error.iapUnavailable'.tr;
      } else {
        await _iap.loadProducts(ids);
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
    });
  }

  IAPProduct? _product(SubPlan plan) {
    final id = AccessTiers.productId(widget.tier, plan);
    return id == null ? null : _iap.byId(id);
  }

  String _price(SubPlan plan) =>
      _product(plan)?.price ?? AccessTiers.usdLabel(widget.tier, plan);

  Future<void> _buy() async {
    final product = _product(_plan);
    if (product == null) {
      setState(() => _error = 'subscribe.error.planNotSetUp'.tr);
      return;
    }
    setState(() {
      _buying = true;
      _error = null;
    });
    final result = await _iap.buy(product, target: widget.target);
    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _buying = false;
      _error = result.error ?? 'subscribe.error.purchaseFailed'.tr;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _content(context),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final theme = Theme.of(context);
    final store = Platform.isIOS
        ? 'subscribe.storeApple'.tr
        : 'subscribe.storeGoogle'.tr;
    return [
      const _DragHandle(),
      const SizedBox(height: 20),
      Text(
        'subscribe.title'.trParams({'name': widget.name}),
        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        'subscribe.intro'.trParams({'store': store}),
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 20),
      Text('subscribe.choosePlan'.tr, style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      for (final plan in SubPlan.values)
        _PlanTile(
          plan: plan,
          price: _price(plan),
          selected: plan == _plan,
          onTap: _buying ? null : () => setState(() => _plan = plan),
        ),
      if (_error != null) _ErrorText(message: _error!),
      const SizedBox(height: 16),
      _primaryButton(),
      const SizedBox(height: 12),
      Text(
        'subscribe.footnote'.tr,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        textAlign: TextAlign.center,
      ),
    ];
  }

  Widget _primaryButton() {
    final busy = _loading || _buying;
    final canRetry = !busy && _error != null && _product(_plan) == null;
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: busy ? null : (canRetry ? _loadProducts : _buy),
        child: busy
            ? const PlatformSpinner()
            : Text(canRetry
                ? 'subscribe.retry'.tr
                : 'subscribe.buy'.trParams({'price': _price(_plan)})),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  final SubPlan plan;
  final String price;
  final bool selected;
  final VoidCallback? onTap;

  const _PlanTile({
    required this.plan,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final monthly = plan == SubPlan.monthly;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(monthly
              ? 'subscribe.planMonthly'.tr
              : 'subscribe.planYearly'.tr),
          subtitle: Text(monthly
              ? 'subscribe.planMonthlyTagline'.tr
              : 'subscribe.planYearlyTagline'.tr),
          trailing: Text(
            price,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          selected: selected,
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String message;
  const _ErrorText({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
