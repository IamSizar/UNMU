import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/subscription_controller.dart';
import '../../models/expert_subscription.dart';
import '../../services/expert_subscription_service.dart';
import '../../services/iap_access.dart';
import '../../widgets/subscriptions/store_purchase_sheet.dart';

/// Subscribing to an expert. Payment is App Store / Google Play only
/// (cash/FIB were cut off — docs/payments/IAP_ONLY_PLAN.md): this reads the
/// expert's price tier, opens [StorePurchaseSheet], and returns the fresh
/// subscription once the backend has granted it.
class SubscribeModal {
  SubscribeModal._();

  /// Opens the purchase sheet; returns the active subscription, or null
  /// when the user did not buy.
  static Future<ExpertSubscription?> show(
    BuildContext context, {
    required String expertId,
    required String expertName,
  }) async {
    final pricing = await ExpertSubscriptionService.fetchExpertPricing(expertId);
    if (!context.mounted) return null;
    final granted = await StorePurchaseSheet.show(
      context,
      name: expertName,
      target: AccessTarget.expert(expertId),
      tier: pricing?.tier,
    );
    if (!granted) return null;
    final sub =
        await Get.find<SubscriptionController>().refreshExpert(expertId);
    if (sub == null) Get.snackbar('', 'subscribe.error.subDidNotShow'.tr);
    return sub;
  }
}
