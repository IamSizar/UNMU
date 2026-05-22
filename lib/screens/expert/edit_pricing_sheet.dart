import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/expert_dashboard_controller.dart';
import '../../services/studio_service.dart';
import '../../utils/haptic_utils.dart';

/// Phase 3.2 — sheet that lets an expert update their own subscription
/// price tiers. Hits PATCH /me/expert/pricing.
///
/// We use a bottom sheet rather than a full screen because the action
/// is two text fields and a button — the screen-of-text overhead of
/// pushing a route would feel heavy for what amounts to a quick edit.
///
/// On success the parent controller is told to apply the new pricing
/// locally so the dashboard tile reflects the change without a full
/// /me/expert/dashboard refresh.
class EditPricingSheet extends StatefulWidget {
  final ExpertDashboardController controller;
  final int initialMonthlyCents;
  final int initialYearlyCents;

  const EditPricingSheet({
    super.key,
    required this.controller,
    required this.initialMonthlyCents,
    required this.initialYearlyCents,
  });

  static Future<void> show(
    BuildContext context, {
    required ExpertDashboardController controller,
    required int initialMonthlyCents,
    required int initialYearlyCents,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: EditPricingSheet(
          controller: controller,
          initialMonthlyCents: initialMonthlyCents,
          initialYearlyCents: initialYearlyCents,
        ),
      ),
    );
  }

  @override
  State<EditPricingSheet> createState() => _EditPricingSheetState();
}

class _EditPricingSheetState extends State<EditPricingSheet> {
  late final TextEditingController _monthly;
  late final TextEditingController _yearly;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _monthly = TextEditingController(
        text: _centsToText(widget.initialMonthlyCents));
    _yearly = TextEditingController(
        text: _centsToText(widget.initialYearlyCents));
    for (final c in [_monthly, _yearly]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _monthly.dispose();
    _yearly.dispose();
    super.dispose();
  }

  /// Display form: integer dollars when the original price ended in a
  /// whole dollar (e.g. 1000 cents → "10"), otherwise two decimals.
  String _centsToText(int cents) {
    if (cents <= 0) return '';
    final dollars = cents / 100.0;
    return dollars.truncateToDouble() == dollars
        ? dollars.toStringAsFixed(0)
        : dollars.toStringAsFixed(2);
  }

  int? _parseCents(String raw) {
    final cleaned = raw.trim().replaceAll(',', '');
    if (cleaned.isEmpty) return 0;
    final dollars = double.tryParse(cleaned);
    if (dollars == null) return null;
    if (dollars < 0) return null;
    return (dollars * 100).round();
  }

  bool get _canSubmit {
    if (_submitting) return false;
    final m = _parseCents(_monthly.text);
    final y = _parseCents(_yearly.text);
    if (m == null || y == null) return false;
    // No-op if both unchanged.
    if (m == widget.initialMonthlyCents && y == widget.initialYearlyCents) {
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_canSubmit) return;
    final m = _parseCents(_monthly.text);
    final y = _parseCents(_yearly.text);
    if (m == null || y == null) {
      setState(() => _error = 'pricing.invalidAmounts'.tr);
      return;
    }
    HapticUtils.lightTap();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await StudioService.setPricing(
      monthlyCents: m,
      yearlyCents: y,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res.error != null) {
      setState(() => _error = res.error);
      return;
    }
    // Optimistically reflect the new price in the dashboard's cache so
    // the tile updates without a full refresh.
    widget.controller.applyPricing(monthlyCents: m, yearlyCents: y);
    if (!mounted) return;
    await HapticUtils.success();
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('pricing.updatedSnack'.tr)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'pricing.title'.tr,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'pricing.subtitle'.tr,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 20),
              _PriceField(
                controller: _monthly,
                label: 'pricing.monthly'.tr,
                hint: 'pricing.monthlyHint'.tr,
              ),
              const SizedBox(height: 12),
              _PriceField(
                controller: _yearly,
                label: 'pricing.yearly'.tr,
                hint: 'pricing.yearlyHint'.tr,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
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
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text('common.cancel'.tr),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _canSubmit ? _save : null,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text('pricing.save'.tr),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  const _PriceField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: false),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: '\$ ',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
