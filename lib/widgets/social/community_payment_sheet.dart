import 'package:flutter/material.dart';

import '../../models/expert_subscription.dart';
import '../../services/iap_access.dart';
import '../subscriptions/store_purchase_sheet.dart';

/// Joining a paid community. Payment is App Store / Google Play only
/// (cash/FIB were cut off — docs/payments/IAP_ONLY_PLAN.md). Returns true
/// once the backend has granted membership.
class CommunityPaymentSheet {
  CommunityPaymentSheet._();

  static Future<bool> show(
    BuildContext context, {
    required String communityId,
    required String communityName,
    required String plan, // monthly | yearly, chosen on the pricing card
    required String? priceTier,
  }) {
    return StorePurchaseSheet.show(
      context,
      name: communityName,
      target: AccessTarget.community(communityId),
      tier: priceTier,
      initialPlan: plan == 'yearly' ? SubPlan.yearly : SubPlan.monthly,
    );
  }
}
