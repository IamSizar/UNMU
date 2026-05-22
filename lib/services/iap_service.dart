import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/api_config.dart';
import 'auth_service.dart';

/// One purchasable SKU. Wraps the plugin's [ProductDetails] so screens
/// don't have to depend on the package directly.
class IAPProduct {
  final String id;
  final String title;
  final String description;
  final String price; // localized price string, e.g. "$9.99"
  final String rawPrice; // raw numeric as a string ("9.99")
  final String currency; // ISO 4217 ("USD")
  final ProductDetails native;

  const IAPProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.rawPrice,
    required this.currency,
    required this.native,
  });

  factory IAPProduct.fromDetails(ProductDetails d) => IAPProduct(
        id: d.id,
        title: d.title,
        description: d.description,
        price: d.price,
        rawPrice: d.rawPrice.toString(),
        currency: d.currencyCode,
        native: d,
      );
}

/// Outcome of a server-side verification call.
class IAPVerificationResult {
  final bool ok;
  final String? error;
  final Map<String, dynamic>? payload;
  const IAPVerificationResult({required this.ok, this.error, this.payload});
}

/// Per-app singleton that owns the StoreKit / Play Billing connection.
///
/// Lifecycle:
///   1. `IAPService.instance.bootstrap()` once at app boot (after Firebase
///      etc.) — opens the purchase stream and starts listening.
///   2. `loadProducts([...])` whenever a screen needs to render prices
///      — caches results for the rest of the session.
///   3. `buy(product, expertId: ...)` from a UI button — kicks off the
///      native purchase sheet. The result eventually arrives on the
///      purchase stream and is dispatched to the matching pending Future
///      via `_pending`.
///   4. `restorePurchases()` from the settings screen for users
///      switching devices.
///
/// We deliberately do NOT extend ChangeNotifier — the app uses GetX
/// everywhere else, so this is a `Get.put`-able service. Reactive UI
/// reads `isAvailable.value`, `products.value`, etc.
class IAPService extends GetxService {
  IAPService._();
  static final IAPService instance = IAPService._();

  final InAppPurchase _store = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Whether the device can reach the store at all. On iOS this depends
  /// on App Store availability; on Android the Play Store must be
  /// installed + signed in.
  final RxBool isAvailable = false.obs;

  /// Cached product catalog from the last [loadProducts] call.
  final RxList<IAPProduct> products = <IAPProduct>[].obs;

  /// True while a buy() is awaiting a result on the stream.
  final RxBool isPurchasing = false.obs;

  /// Per-purchase-token Completer so the UI can `await buy(...)` and
  /// receive a typed outcome. Keyed on productID + nanoid so two
  /// concurrent buys (rare but possible) don't collide.
  final Map<String, _PendingBuy> _pending = {};

  /// Outermost product ID prefix — used to gate which receipts we even
  /// try to verify (defensive against unrelated stale purchases from a
  /// previous app on the same store account).
  static const String productPrefix = 'com.unmu.';

  /// Default platform-wide Premium SKUs — created in App Store Connect.
  /// Per-expert subscriptions use dynamic SKUs that look like
  /// `com.unmu.expert.{expertId}.monthly`.
  static const String monthlySubscriptionId = 'com.unmu.premium.monthly';
  static const String annualSubscriptionId = 'com.unmu.premium.yearly';

  bool _bootedOnce = false;

  /// One-shot init. Safe to call multiple times — extra calls no-op.
  Future<void> bootstrap() async {
    if (_bootedOnce) return;
    _bootedOnce = true;

    isAvailable.value = await _store.isAvailable();
    debugPrint('[iap] store available: ${isAvailable.value}');

    _sub?.cancel();
    _sub = _store.purchaseStream.listen(
      _onPurchaseUpdates,
      onDone: () => debugPrint('[iap] purchase stream closed'),
      onError: (e) => debugPrint('[iap] purchase stream error: $e'),
    );
  }

  /// Look up the SKUs we care about. The plugin returns the same list it
  /// queries the store for (minus unknown IDs in [ProductDetailsResponse
  /// .notFoundIDs]).
  Future<List<IAPProduct>> loadProducts(Set<String> ids) async {
    if (!isAvailable.value) {
      products.value = const [];
      return const [];
    }
    final resp = await _store.queryProductDetails(ids);
    if (resp.notFoundIDs.isNotEmpty) {
      debugPrint('[iap] products not found: ${resp.notFoundIDs}');
    }
    final list = resp.productDetails.map(IAPProduct.fromDetails).toList();
    products.value = list;
    return list;
  }

  /// Convenience: returns the cached IAPProduct or null. Useful when
  /// the SubscribeModal already loaded the catalog and just wants to
  /// look up by ID.
  IAPProduct? byId(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Kick off a purchase. Returns when the store either confirms the
  /// purchase (success), the user cancels (canceled error), or the
  /// store reports a failure.
  ///
  /// `expertId` is forwarded to the backend so we can immediately
  /// activate the matching expert_subscription row when verification
  /// succeeds.
  Future<IAPVerificationResult> buy(
    IAPProduct product, {
    String? expertId,
  }) async {
    if (!isAvailable.value) {
      return const IAPVerificationResult(
        ok: false,
        error: 'In-app purchases are not available on this device.',
      );
    }

    isPurchasing.value = true;
    final completer = Completer<IAPVerificationResult>();
    final pendingKey = '${product.id}#${DateTime.now().microsecondsSinceEpoch}';
    _pending[pendingKey] = _PendingBuy(
      productId: product.id,
      expertId: expertId,
      completer: completer,
    );

    final param = PurchaseParam(productDetails: product.native);
    final isSub = _looksLikeSubscription(product.id);

    try {
      final ok = isSub
          ? await _store.buyNonConsumable(purchaseParam: param)
          : await _store.buyConsumable(purchaseParam: param);
      if (!ok) {
        _pending.remove(pendingKey);
        isPurchasing.value = false;
        return const IAPVerificationResult(
          ok: false,
          error: 'Purchase request was rejected by the store.',
        );
      }
    } catch (e) {
      _pending.remove(pendingKey);
      isPurchasing.value = false;
      return IAPVerificationResult(ok: false, error: 'Store error: $e');
    }

    return completer.future;
  }

  /// Restore previously-bought subscriptions. The store re-delivers
  /// PurchaseDetails for every active SKU; each one is sent to the
  /// backend for verification just like a fresh buy.
  Future<void> restorePurchases() async {
    if (!isAvailable.value) return;
    await _store.restorePurchases();
  }

  void _onPurchaseUpdates(List<PurchaseDetails> updates) {
    for (final p in updates) {
      _handleSingleUpdate(p);
    }
  }

  Future<void> _handleSingleUpdate(PurchaseDetails p) async {
    debugPrint('[iap] purchase update: ${p.productID} status=${p.status} '
        'pending=${p.pendingCompletePurchase}');

    switch (p.status) {
      case PurchaseStatus.pending:
        // Still in-flight — UI shows a loading spinner.
        return;
      case PurchaseStatus.canceled:
        _completeMatching(
          p.productID,
          const IAPVerificationResult(ok: false, error: 'Purchase canceled.'),
        );
        if (p.pendingCompletePurchase) await _store.completePurchase(p);
        return;
      case PurchaseStatus.error:
        _completeMatching(
          p.productID,
          IAPVerificationResult(
            ok: false,
            error: p.error?.message ?? 'Purchase failed.',
          ),
        );
        if (p.pendingCompletePurchase) await _store.completePurchase(p);
        return;
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        // Verify with backend; complete locally only if backend accepts.
        final pending = _firstPendingFor(p.productID);
        final result = await _verifyWithBackend(p, pending?.expertId);
        if (p.pendingCompletePurchase) await _store.completePurchase(p);
        _completeMatching(p.productID, result);
        return;
    }
  }

  Future<IAPVerificationResult> _verifyWithBackend(
    PurchaseDetails p,
    String? expertId,
  ) async {
    final receipt = p.verificationData.serverVerificationData;
    if (receipt.isEmpty) {
      return const IAPVerificationResult(
        ok: false,
        error: 'Store did not return a verifiable receipt.',
      );
    }
    final authToken = await AuthService.getToken();
    if (authToken == null || authToken.isEmpty) {
      return const IAPVerificationResult(
        ok: false,
        error: 'Not signed in — please log in and tap Restore Purchases.',
      );
    }

    // Today we only support Apple; once a Google handler exists, fork
    // on Platform.isAndroid.
    final endpoint = Platform.isIOS
        ? '${ApiConfig.baseUrl}/me/iap/apple/verify'
        : null;
    if (endpoint == null) {
      return const IAPVerificationResult(
        ok: false,
        error: 'Verification is not yet supported on this platform.',
      );
    }

    try {
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: json.encode({
              'receiptData': receipt,
              'productId': p.productID,
              if (expertId != null && expertId.isNotEmpty) 'expertId': expertId,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return IAPVerificationResult(
          ok: true,
          payload: json.decode(response.body) as Map<String, dynamic>,
        );
      }
      final body = _safeDecode(response.body);
      return IAPVerificationResult(
        ok: false,
        error: (body['error'] ?? 'Server rejected the receipt.').toString(),
      );
    } catch (e) {
      return IAPVerificationResult(
        ok: false,
        error: 'Could not reach server for verification: $e',
      );
    }
  }

  void _completeMatching(String productID, IAPVerificationResult result) {
    final pending = _firstPendingFor(productID);
    if (pending == null) {
      // No awaiter — likely a restore-purchases delivery for a SKU the
      // user didn't actively buy this session. Silent verification still
      // happened above; nothing more to do.
      return;
    }
    _pending.remove(pending.key);
    if (_pending.isEmpty) {
      isPurchasing.value = false;
    }
    pending.completer.complete(result);
  }

  _PendingBuy? _firstPendingFor(String productID) {
    for (final entry in _pending.entries) {
      if (entry.value.productId == productID) {
        return entry.value..key = entry.key;
      }
    }
    return null;
  }

  bool _looksLikeSubscription(String productID) {
    final s = productID.toLowerCase();
    return s.endsWith('.monthly') ||
        s.endsWith('.yearly') ||
        s.contains('subscription');
  }

  static Map<String, dynamic> _safeDecode(String s) {
    try {
      final v = json.decode(s);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return {};
  }

  @override
  void onClose() {
    _sub?.cancel();
    _sub = null;
    super.onClose();
  }
}

class _PendingBuy {
  final String productId;
  final String? expertId;
  final Completer<IAPVerificationResult> completer;
  String key = '';
  _PendingBuy({
    required this.productId,
    required this.expertId,
    required this.completer,
  });
}
