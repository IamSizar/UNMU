// Tier products that pay for an expert or a community.
//
// Since cash/FIB were cut off, access is bought only through the App Store
// or Google Play. Each expert / paid community has a price tier (t1..t4);
// each tier and plan is one store product `com.unmu.access.<tier>.<month|year>`
// (backend: internal/models/price_tier.go, docs/payments/IAP_ONLY_PLAN.md).
import 'package:shared_preferences/shared_preferences.dart';

import '../models/expert_subscription.dart';

/// What a tier purchase unlocks: an expert or a community.
class AccessTarget {
  final String type; // 'expert' | 'community'
  final String id;

  const AccessTarget.expert(this.id) : type = 'expert';
  const AccessTarget.community(this.id) : type = 'community';
  const AccessTarget._(this.type, this.id);

  String encode() => '$type:$id';

  /// Parses [encode]'s output; null for anything else.
  static AccessTarget? decode(String? raw) {
    if (raw == null) return null;
    final i = raw.indexOf(':');
    if (i <= 0 || i == raw.length - 1) return null;
    final type = raw.substring(0, i);
    if (type != 'expert' && type != 'community') return null;
    return AccessTarget._(type, raw.substring(i + 1));
  }
}

/// The fixed price tiers and their store products.
class AccessTiers {
  AccessTiers._();

  static const String _prefix = 'com.unmu.access.';
  static const List<String> tiers = ['t1', 't2', 't3', 't4'];

  /// USD cents per tier: monthly, yearly. Mirrors the backend table; the
  /// store's own localized price is shown when it has loaded.
  static const Map<String, (int, int)> _cents = {
    't1': (499, 4999),
    't2': (999, 9999),
    't3': (1999, 19999),
    't4': (4999, 49999),
  };

  static bool isTier(String? tier) => tier != null && _cents.containsKey(tier);

  /// USD cents for [tier] and [plan], or 0 when the tier is unknown.
  static int priceCents(String? tier, SubPlan plan) {
    final p = _cents[tier];
    if (p == null) return 0;
    return plan == SubPlan.monthly ? p.$1 : p.$2;
  }

  /// "$9.99" style USD label, used until the store price loads.
  static String usdLabel(String? tier, SubPlan plan) =>
      '\$${(priceCents(tier, plan) / 100).toStringAsFixed(2)}';

  /// Store product id, or null when the tier is unknown.
  static String? productId(String? tier, SubPlan plan) {
    if (!isTier(tier)) return null;
    return '$_prefix$tier.${plan == SubPlan.monthly ? 'month' : 'year'}';
  }

  static bool isAccessProduct(String productId) =>
      productId.startsWith(_prefix);
}

/// Remembers which target a tier purchase was for, per product, so a
/// purchase the store delivers after an app restart can still be applied.
///
/// One open purchase per product: while an entry exists, a purchase of the
/// same product for another target (or by another signed-in user) is not
/// started, so a redelivered purchase can never be applied to the wrong
/// target or account. Entries older than [maxAge] are ignored (Google
/// refunds a purchase that was never acknowledged within 3 days).
class AccessTargetStore {
  AccessTargetStore._();

  static const Duration maxAge = Duration(days: 3);

  static String _key(String productId) => 'iap_access_target.$productId';

  static Future<void> save(
    String productId,
    int userId,
    AccessTarget target,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final at = DateTime.now().millisecondsSinceEpoch;
    await prefs.setString(_key(productId), '$userId|$at|${target.encode()}');
  }

  /// The open entry for [productId] (any user), or null.
  static Future<({int userId, AccessTarget target})?> open(
    String productId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final parts = prefs.getString(_key(productId))?.split('|');
    if (parts == null || parts.length != 3) return null;
    final userId = int.tryParse(parts[0]);
    final at = int.tryParse(parts[1]);
    final target = AccessTarget.decode(parts[2]);
    if (userId == null || at == null || target == null) return null;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(at),
    );
    if (age > maxAge) return null;
    return (userId: userId, target: target);
  }

  /// The saved target for [productId] if it belongs to [userId].
  static Future<AccessTarget?> load(String productId, int userId) async {
    final entry = await open(productId);
    return entry != null && entry.userId == userId ? entry.target : null;
  }

  static Future<void> clear(String productId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(productId));
  }
}
