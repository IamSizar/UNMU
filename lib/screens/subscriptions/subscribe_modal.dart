import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/api_config.dart';
import '../../controllers/subscription_controller.dart';
import '../../models/expert_subscription.dart';
import '../../services/expert_subscription_service.dart';
import '../../services/iap_service.dart';
import '../../services/upload_service.dart';
import '../../widgets/dismiss_keyboard_on_tap.dart';

/// Bottom sheet modal where the user picks a plan + payment method and
/// submits a subscription request. Shown from the expert profile screen.
///
/// Step B (mig 0024):
///   * Plan prices are fetched live from `/experts/:id` so admins can
///     change pricing without an app release (B2 + B3).
///   * Cash subscribers can attach a receipt image; FIB subscribers can
///     paste a transaction reference (B10).
///
/// Pops with the freshly-created [ExpertSubscription] on success so the
/// caller can update its UI without an extra fetch.
class SubscribeModal extends StatefulWidget {
  final String expertId;
  final String expertName;

  const SubscribeModal({
    super.key,
    required this.expertId,
    required this.expertName,
  });

  /// Helper — opens the modal and returns the new subscription (or null).
  static Future<ExpertSubscription?> show(
    BuildContext context, {
    required String expertId,
    required String expertName,
  }) {
    return showModalBottomSheet<ExpertSubscription>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SubscribeModal(
        expertId: expertId,
        expertName: expertName,
      ),
    );
  }

  @override
  State<SubscribeModal> createState() => _SubscribeModalState();
}

class _SubscribeModalState extends State<SubscribeModal> {
  SubPlan _plan = SubPlan.monthly;
  PaymentMethod _method = PaymentMethod.cash;
  final _refController = TextEditingController();
  final _noteController = TextEditingController();
  bool _submitting = false;
  String? _error;

  /// Fetched on init from `/experts/:id`. Falls back to legacy defaults
  /// if the call fails so the user is never stuck looking at a spinner.
  ExpertPricing? _pricing;
  bool _pricingLoading = true;

  /// Receipt image upload state for cash payments.
  String? _receiptUrl;
  bool _receiptUploading = false;

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  Future<void> _loadPricing() async {
    final res =
        await ExpertSubscriptionService.fetchExpertPricing(widget.expertId);
    if (!mounted) return;
    setState(() {
      // Fall back to plan-enum defaults so the form is always renderable.
      _pricing = res ??
          const ExpertPricing(
            monthlyCents: 1000,
            yearlyCents: 9600,
            currency: 'usd',
          );
      _pricingLoading = false;
    });
  }

  @override
  void dispose() {
    _refController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (picked == null) return;
    setState(() {
      _receiptUploading = true;
      _error = null;
    });
    final res = await UploadService.uploadImage(File(picked.path));
    if (!mounted) return;
    setState(() {
      _receiptUploading = false;
      if (res.error != null) {
        _error = res.error;
      } else {
        _receiptUrl = res.url;
      }
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    // Apple IAP branch — kick off StoreKit instead of the admin-verified
    // cash/FIB path. On success the backend's /me/iap/apple/verify
    // endpoint has already activated the subscription, so we just
    // refresh the controller's cache and pop with the resulting row.
    if (_method == PaymentMethod.appleIap) {
      await _submitAppleIap();
      return;
    }

    final result = await Get.find<SubscriptionController>().subscribe(
      expertId: widget.expertId,
      plan: _plan,
      method: _method,
      paymentRef: _refController.text.trim().isEmpty
          ? null
          : _refController.text.trim(),
      receiptUrl: _receiptUrl,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );

    if (!mounted) return;

    if (result.sub != null) {
      Navigator.of(context).pop(result.sub);
      return;
    }
    setState(() {
      _submitting = false;
      _error = result.error ?? 'subscribe.error.submitFailed'.tr;
    });
  }

  /// Apple IAP flow. Convention for SKU IDs:
  ///   `com.unmu.expert.{expertId}.monthly`
  ///   `com.unmu.expert.{expertId}.yearly`
  /// These need to be configured in App Store Connect. If the product
  /// isn't there yet the modal surfaces a friendly error instead of
  /// crashing.
  Future<void> _submitAppleIap() async {
    final productId = 'com.unmu.expert.${widget.expertId}.${_plan.wireValue}';
    final iap = IAPService.instance;

    if (!iap.isAvailable.value) {
      setState(() {
        _submitting = false;
        _error = 'subscribe.error.iapUnavailable'.tr;
      });
      return;
    }

    // Make sure the product catalog is loaded for the SKU we want. The
    // service caches results per-session so this is a one-time call.
    var product = iap.byId(productId);
    if (product == null) {
      await iap.loadProducts({productId});
      product = iap.byId(productId);
    }
    if (product == null) {
      setState(() {
        _submitting = false;
        _error = 'subscribe.error.planNotSetUp'.tr;
      });
      return;
    }

    final result = await iap.buy(product, expertId: widget.expertId);
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _submitting = false;
        _error = result.error ?? 'subscribe.error.purchaseFailed'.tr;
      });
      return;
    }

    // Backend already activated the row via /me/iap/apple/verify.
    // Refresh the controller's cache so MySubscriptions + the expert
    // profile screen see the new state, then pop with the fresh row.
    final sub = await Get.find<SubscriptionController>()
        .refreshExpert(widget.expertId);
    if (!mounted) return;

    if (sub != null) {
      Navigator.of(context).pop(sub);
      return;
    }
    setState(() {
      _submitting = false;
      _error = 'subscribe.error.subDidNotShow'.tr;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final pricing = _pricing;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DismissKeyboardOnTap(
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
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'subscribe.title'.trParams({'name': widget.expertName}),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  Platform.isIOS
                      ? 'subscribe.introIos'.tr
                      : 'subscribe.introOther'.tr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),

                const SizedBox(height: 22),
                _SectionLabel('subscribe.choosePlan'.tr),
                const SizedBox(height: 8),
                if (_pricingLoading || pricing == null)
                  Container(
                    height: 64,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  _PlanCard(
                    plan: SubPlan.monthly,
                    pricing: pricing,
                    selected: _plan == SubPlan.monthly,
                    onTap: () => setState(() => _plan = SubPlan.monthly),
                  ),
                  const SizedBox(height: 8),
                  _PlanCard(
                    plan: SubPlan.yearly,
                    pricing: pricing,
                    selected: _plan == SubPlan.yearly,
                    onTap: () => setState(() => _plan = SubPlan.yearly),
                  ),
                ],

                const SizedBox(height: 22),
                _SectionLabel('subscribe.paymentMethod'.tr),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _MethodTile(
                        method: PaymentMethod.cash,
                        selected: _method == PaymentMethod.cash,
                        onTap: () => setState(() => _method = PaymentMethod.cash),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MethodTile(
                        method: PaymentMethod.fib,
                        selected: _method == PaymentMethod.fib,
                        onTap: () => setState(() => _method = PaymentMethod.fib),
                      ),
                    ),
                  ],
                ),
                // Apple IAP — iOS only. Surfaced as a separate row below
                // the cash/FIB pair so the existing layout stays untouched
                // on non-iOS clients (where this row collapses to nothing).
                if (Platform.isIOS) ...[
                  const SizedBox(height: 8),
                  _MethodTile(
                    method: PaymentMethod.appleIap,
                    selected: _method == PaymentMethod.appleIap,
                    onTap: () => setState(() => _method = PaymentMethod.appleIap),
                  ),
                ],

                if (_method == PaymentMethod.fib) ...[
                  const SizedBox(height: 14),
                  _SectionLabel('subscribe.fibRefLabel'.tr),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _refController,
                    decoration: InputDecoration(
                      hintText: 'subscribe.fibRefHint'.tr,
                    ),
                    enabled: !_submitting,
                  ),
                ],

                if (_method == PaymentMethod.cash) ...[
                  const SizedBox(height: 14),
                  _SectionLabel('subscribe.receiptLabel'.tr),
                  const SizedBox(height: 6),
                  _ReceiptPickerTile(
                    receiptUrl: _receiptUrl,
                    uploading: _receiptUploading,
                    onTap: _receiptUploading || _submitting ? null : _pickReceipt,
                    onClear: _receiptUrl == null
                        ? null
                        : () => setState(() => _receiptUrl = null),
                  ),
                ],

                // Admin-verified flows (cash + FIB) accept a freeform note.
                // IAP doesn't go through admin review so the note input
                // would be misleading there.
                if (_method == PaymentMethod.cash ||
                    _method == PaymentMethod.fib) ...[
                  const SizedBox(height: 14),
                  _SectionLabel('subscribe.noteLabel'.tr),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'subscribe.noteHint'.tr,
                    ),
                    enabled: !_submitting,
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: cs.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!)),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _submitting || pricing == null ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('subscribe.submit'.trParams({
                          'price': pricing == null
                              ? ''
                              : pricing.formatCents(pricing.centsForPlan(_plan)),
                        })),
                ),
                const SizedBox(height: 10),
                Text(
                  _method == PaymentMethod.appleIap
                      ? 'subscribe.footnoteIap'.tr
                      : 'subscribe.footnoteAdmin'.tr,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final SubPlan plan;
  final ExpertPricing pricing;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard({
    required this.plan,
    required this.pricing,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isYearly = plan == SubPlan.yearly;

    final priceLabel = pricing.formatCents(pricing.centsForPlan(plan));
    final tagline = isYearly
        ? 'subscribe.planYearlyTagline'.trParams({
            'yearly': pricing.yearlyLabel,
            'monthly': pricing.yearlyMonthlyEquivalent,
          })
        : 'subscribe.planMonthlyTagline'
            .trParams({'monthly': pricing.monthlyLabel});

    // Yearly "savings" badge — only show if the yearly plan actually beats
    // monthly × 12. Avoids a misleading "SAVE 20%" stamp when the admin
    // forgets to discount the yearly tier.
    final monthlyTotalForYear = pricing.monthlyCents * 12;
    final saved = monthlyTotalForYear - pricing.yearlyCents;
    final savedPct = monthlyTotalForYear > 0
        ? ((saved / monthlyTotalForYear) * 100).round()
        : 0;
    final showSaveBadge = isYearly && saved > 0 && savedPct >= 5;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.14)
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        (isYearly
                                ? 'subscribe.planYearly'
                                : 'subscribe.planMonthly')
                            .tr,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (showSaveBadge) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            'subscribe.saveBadge'.trParams({'pct': '$savedPct'}),
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tagline,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Text(
              priceLabel,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: selected ? cs.primary : cs.onSurface,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    IconData icon;
    String sub;
    String title;
    switch (method) {
      case PaymentMethod.cash:
        icon = Icons.payments_outlined;
        sub = 'subscribe.method.cashSub'.tr;
        title = 'subscribe.method.cashTitle'.tr;
        break;
      case PaymentMethod.fib:
        icon = Icons.account_balance_outlined;
        sub = 'subscribe.method.fibSub'.tr;
        title = method.label;
        break;
      case PaymentMethod.appleIap:
        icon = Icons.apple_rounded;
        sub = 'subscribe.method.appleSub'.tr;
        title = method.label;
        break;
      case PaymentMethod.googleIap:
        icon = Icons.shop_outlined;
        sub = 'subscribe.method.googleSub'.tr;
        title = method.label;
        break;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.14)
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(height: 6),
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? cs.primary : cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cash receipt picker — same visual style as the apply-form's avatar /
/// resume tiles. Shows a thumbnail when populated, "tap to add" otherwise.
class _ReceiptPickerTile extends StatelessWidget {
  final String? receiptUrl;
  final bool uploading;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  const _ReceiptPickerTile({
    required this.receiptUrl,
    required this.uploading,
    required this.onTap,
    required this.onClear,
  });

  String _absolute(String relative) {
    if (relative.startsWith('http')) return relative;
    final base = ApiConfig.baseUrl;
    final origin = base.split('/api').first;
    return '$origin$relative';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  image: receiptUrl == null
                      ? null
                      : DecorationImage(
                          image: NetworkImage(_absolute(receiptUrl!)),
                          fit: BoxFit.cover,
                        ),
                ),
                child: receiptUrl == null
                    ? Icon(Icons.receipt_long_rounded, color: cs.primary)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      receiptUrl == null
                          ? 'subscribe.receipt.addTitle'.tr
                          : 'subscribe.receipt.uploadedTitle'.tr,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      receiptUrl == null
                          ? 'subscribe.receipt.addSub'.tr
                          : 'subscribe.receipt.uploadedSub'.tr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (uploading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (onClear != null)
                IconButton(
                  tooltip: 'common.remove'.tr,
                  onPressed: onClear,
                  icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                )
              else
                Icon(Icons.add_a_photo_outlined, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}
