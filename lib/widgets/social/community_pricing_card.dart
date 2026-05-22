import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../screens/social/social_tokens.dart';
import '../../utils/price_format.dart';

/// "Pricing" card rendered on the pre-join community preview screen
/// (step-23). Shows monthly / yearly plans with selectable chips and
/// a single Subscribe CTA. The caller fires [onSubscribe] with the
/// chosen plan; the actual payment sheet + service call live in the
/// parent screen.
///
/// Free communities (both prices 0) use the simpler `CommunityJoinFreeCta`
/// below — this card never renders for them.
class CommunityPricingCard extends StatefulWidget {
  /// Currency code (lowercased, e.g. "usd"). Display uppercases.
  final String currency;
  final int monthlyCents;
  final int yearlyCents;
  /// Pre-selected plan when the user has a pending subscription —
  /// helps continuity if they re-open the screen.
  final String? initialPlan;
  /// Disabled flag (e.g. the user already has an active sub for
  /// this community). When true, the CTA reads "Already subscribed"
  /// and tapping is a no-op.
  final bool alreadyActive;
  /// True while a parent is busy (network in flight) so we can grey
  /// the button.
  final bool busy;
  /// Fired with 'monthly' or 'yearly' on Subscribe tap.
  final ValueChanged<String> onSubscribe;

  const CommunityPricingCard({
    super.key,
    required this.currency,
    required this.monthlyCents,
    required this.yearlyCents,
    required this.onSubscribe,
    this.initialPlan,
    this.alreadyActive = false,
    this.busy = false,
  });

  @override
  State<CommunityPricingCard> createState() => _CommunityPricingCardState();
}

class _CommunityPricingCardState extends State<CommunityPricingCard> {
  late String _plan;

  @override
  void initState() {
    super.initState();
    // Default to the cheaper-per-month plan if both are set; falls
    // back to whichever is non-zero.
    if (widget.initialPlan != null) {
      _plan = widget.initialPlan!;
    } else if (widget.yearlyCents > 0 && widget.monthlyCents > 0) {
      _plan = 'yearly';
    } else if (widget.yearlyCents > 0) {
      _plan = 'yearly';
    } else {
      _plan = 'monthly';
    }
  }

  // Locale-aware, currency-aware price label with thousand separators.
  // Examples (depending on currency):
  //   USD 15000 cents  → "$ 150"        (was "USD 150")
  //   USD 150000 cents → "$ 1,500"      (was "USD 1500")
  //   IQD 15000        → "د.ع 15,000"   (was "IQD 150" — bug; div-by-100 doesn't apply)
  String _format(int cents) => PriceFormat.formatPrice(cents, widget.currency);

  /// "Save 17%" chip label, or null when the comparison doesn't apply
  /// (free community / single plan / yearly ≥ monthly×12). Returning
  /// null hides the badge entirely — see _PlanTile.
  String? _savingsBadge() {
    final pct = PriceFormat.yearlySavingsPercent(
      widget.monthlyCents,
      widget.yearlyCents,
    );
    return pct == null
        ? null
        : 'pricingCard.saveBadge'.trParams({'pct': '$pct'});
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final hasMonthly = widget.monthlyCents > 0;
    final hasYearly = widget.yearlyCents > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: SocialTokens.gold.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: SocialTokens.gold, size: 20),
              const SizedBox(width: 8),
              Text(
                'pricingCard.paidCommunity'.tr,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'pricingCard.intro'.tr,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (hasMonthly)
                Expanded(
                  child: _PlanTile(
                    label: 'pricingCard.monthly'.tr,
                    price: _format(widget.monthlyCents),
                    sub: 'pricingCard.perMonth'.tr,
                    selected: _plan == 'monthly',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _plan = 'monthly');
                    },
                    palette: palette,
                  ),
                ),
              if (hasMonthly && hasYearly) const SizedBox(width: 10),
              if (hasYearly)
                Expanded(
                  child: _PlanTile(
                    label: 'pricingCard.yearly'.tr,
                    price: _format(widget.yearlyCents),
                    sub: 'pricingCard.perYear'.tr,
                    // Compute actual savings % at display time. Returns
                    // null when math doesn't apply (one plan unset, or
                    // yearly ≥ monthly×12) — chip then hides.
                    badge: _savingsBadge(),
                    selected: _plan == 'yearly',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _plan = 'yearly');
                    },
                    palette: palette,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.alreadyActive
                    ? palette.surfaceElevated
                    : SocialTokens.gold,
                foregroundColor: widget.alreadyActive
                    ? palette.textMuted
                    : Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: widget.alreadyActive || widget.busy
                  ? null
                  : () => widget.onSubscribe(_plan),
              icon: Icon(
                widget.alreadyActive
                    ? Icons.check_circle_rounded
                    : Icons.lock_open_rounded,
              ),
              label: Text(
                widget.alreadyActive
                    ? 'pricingCard.alreadySubscribed'.tr
                    : widget.busy
                        ? 'pricingCard.submitting'.tr
                        : 'pricingCard.subscribePrice'.trParams({
                            'price': _plan == 'monthly'
                                ? _format(widget.monthlyCents)
                                : _format(widget.yearlyCents),
                          }),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'pricingCard.footnote'.tr,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  final String label;
  final String price;
  final String sub;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  final SocialPalette palette;
  const _PlanTile({
    required this.label,
    required this.price,
    required this.sub,
    required this.selected,
    required this.onTap,
    required this.palette,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? SocialTokens.gold.withValues(alpha: 0.14)
              : palette.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? SocialTokens.gold
                : palette.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: SocialTokens.up.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: SocialTokens.up,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            Text(
              sub,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
