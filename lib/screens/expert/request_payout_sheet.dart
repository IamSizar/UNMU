import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../services/payout_service.dart';
import '../../services/studio_service.dart';
import '../../utils/haptic_utils.dart';

/// Phase 3.4 — sheet for an expert to request a payout. Hits
/// POST /me/expert/payouts/request. The amount input is validated
/// against [availableCents] so the user can't submit something the
/// backend will reject — backend still re-checks atomically inside a
/// transaction so concurrent submits can't slip past.
///
/// The free-form `paymentDetails` JSON is captured as one operator-
/// readable text field rather than a method-specific form. Mobile
/// wallets / bank IBANs / PayPal emails all fit cleanly into "a
/// string the admin reads off the queue".
class RequestPayoutSheet extends StatefulWidget {
  final int availableCents;
  final String currency;
  /// Called after a successful submit with the freshly-created Payout
  /// so the caller can prepend it to the on-screen history list.
  final void Function(Payout payout) onCreated;

  const RequestPayoutSheet({
    super.key,
    required this.availableCents,
    required this.currency,
    required this.onCreated,
  });

  static Future<void> show(
    BuildContext context, {
    required int availableCents,
    required String currency,
    required void Function(Payout payout) onCreated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Read viewInsets from the sheet's own context (ctx) so the padding
      // tracks the keyboard and lifts the fields above it.
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: RequestPayoutSheet(
          availableCents: availableCents,
          currency: currency,
          onCreated: onCreated,
        ),
      ),
    );
  }

  @override
  State<RequestPayoutSheet> createState() => _RequestPayoutSheetState();
}

class _RequestPayoutSheetState extends State<RequestPayoutSheet> {
  final _amount = TextEditingController();
  final _details = TextEditingController();
  PayoutMethod _method = PayoutMethod.bank;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_amount, _details]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _details.dispose();
    super.dispose();
  }

  int? _parseCents() {
    final raw = _amount.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return null;
    final dollars = double.tryParse(raw);
    if (dollars == null || dollars <= 0) return null;
    return (dollars * 100).round();
  }

  bool get _canSubmit {
    if (_submitting) return false;
    final cents = _parseCents();
    if (cents == null || cents <= 0) return false;
    if (cents > widget.availableCents) return false;
    if (_details.text.trim().isEmpty) return false;
    return true;
  }

  String _detailsHint() {
    switch (_method) {
      case PayoutMethod.bank:
        return 'payout.hintBank'.tr;
      case PayoutMethod.fib:
        return 'payout.hintFib'.tr;
      case PayoutMethod.paypal:
        return 'payout.hintPaypal'.tr;
      case PayoutMethod.other:
        return 'payout.hintOther'.tr;
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final cents = _parseCents()!;
    HapticUtils.lightTap();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await PayoutService.request(
      amountCents: cents,
      method: _method,
      paymentDetails: {
        // We pack the user's free-form details into one string so the
        // admin queue renders cleanly regardless of method. Method-
        // specific fields can be added later (separate ticket).
        'note': _details.text.trim(),
      },
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res.error != null) {
      setState(() => _error = res.error);
      return;
    }
    if (res.payout != null) {
      widget.onCreated(res.payout!);
    }
    await HapticUtils.success();
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('payout.submittedSnack'.tr),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final availLabel = formatCents(widget.availableCents, widget.currency);
    return Container(
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
                'payout.requestTitle'.tr,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'payout.availableLabel'.trParams({'amount': availLabel}),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: false),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'payout.amount'.tr,
                  prefixText: '\$ ',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<PayoutMethod>(
                initialValue: _method,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _method = v);
                },
                decoration: InputDecoration(
                  labelText: 'payout.method'.tr,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: PayoutMethod.values
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m.label),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _details,
                maxLines: 3,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: 'payout.details'.tr,
                  hintText: _detailsHint(),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_error != null) ...[
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
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 6),
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
                      onPressed: _canSubmit ? _submit : null,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text('payout.submit'.tr),
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
