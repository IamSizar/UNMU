import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/api_config.dart';
import 'auth_service.dart';
import 'iap_access.dart';
import 'iap_models.dart';

export 'iap_models.dart';

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

  /// Bumped each time a restored purchase is verified by the backend, so
  /// screens listing subscriptions can reload.
  final RxInt verifiedRestores = 0.obs;

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
  ///
  /// `target` is set for tier products (com.unmu.access.*): the expert or
  /// community the purchase pays for. It is also saved on the device so a
  /// purchase the store delivers after a restart can still be applied.
  Future<IAPVerificationResult> buy(
    IAPProduct product, {
    String? expertId,
    AccessTarget? target,
  }) async {
    if (!isAvailable.value) {
      return const IAPVerificationResult(
        ok: false,
        error: 'In-app purchases are not available on this device.',
      );
    }

    if (target != null) {
      final blocked = await _reserveAccessTarget(product.id, target);
      if (blocked != null) return blocked;
    }
    isPurchasing.value = true;
    final completer = Completer<IAPVerificationResult>();
    final pendingKey = '${product.id}#${DateTime.now().microsecondsSinceEpoch}';
    _pending[pendingKey] = _PendingBuy(
      productId: product.id,
      expertId: expertId,
      target: target,
      completer: completer,
    );

    final param = PurchaseParam(productDetails: product.native);
    final isSub = _looksLikeSubscription(product.id);

    try {
      // Tier products are consumed by the backend after it grants access,
      // never by the plugin on Android (iOS requires autoConsume: true).
      final ok = isSub
          ? await _store.buyNonConsumable(purchaseParam: param)
          : await _store.buyConsumable(
              purchaseParam: param,
              autoConsume: Platform.isIOS || target == null,
            );
      if (!ok) {
        if (target != null) await AccessTargetStore.clear(product.id);
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
  ///
  /// Returns false when the store is unavailable (nothing was started).
  Future<bool> restorePurchases() async {
    if (!isAvailable.value) return false;
    await _store.restorePurchases();
    return true;
  }

  static const String _expertSkuPrefix = 'com.unmu.expert.';
  static const List<String> _planSuffixes = ['.monthly', '.yearly'];

  /// The expert id inside an expert SKU (`com.unmu.expert.{id}.{plan}`), or
  /// null for any other SKU. Restored purchases have no pending buy, so this
  /// is the only way to know which expert they belong to.
  static String? expertIdFromProductId(String productId) {
    if (!productId.startsWith(_expertSkuPrefix)) return null;
    final rest = productId.substring(_expertSkuPrefix.length);
    for (final suffix in _planSuffixes) {
      if (rest.endsWith(suffix)) {
        final id = rest.substring(0, rest.length - suffix.length);
        return id.isEmpty ? null : id;
      }
    }
    return null;
  }

  void _onPurchaseUpdates(List<PurchaseDetails> updates) {
    for (final p in updates) {
      _handleSingleUpdate(p);
    }
  }

  Future<void> _handleSingleUpdate(PurchaseDetails p) async {
    debugPrint(
      '[iap] purchase update: ${p.productID} status=${p.status} '
      'pending=${p.pendingCompletePurchase}',
    );

    switch (p.status) {
      case PurchaseStatus.pending:
        // Still in-flight — UI shows a loading spinner.
        return;
      case PurchaseStatus.canceled:
        if (AccessTiers.isAccessProduct(p.productID)) {
          await AccessTargetStore.clear(p.productID);
        }
        _completeMatching(
          p.productID,
          const IAPVerificationResult(ok: false, error: 'Purchase canceled.'),
        );
        if (p.pendingCompletePurchase) await _store.completePurchase(p);
        return;
      case PurchaseStatus.error:
        if (AccessTiers.isAccessProduct(p.productID)) {
          await AccessTargetStore.clear(p.productID);
        }
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
        if (AccessTiers.isAccessProduct(p.productID)) {
          await _handleAccessPurchase(p);
          return;
        }
        // Verify with backend; complete locally only if backend accepts.
        final pending = _firstPendingFor(p.productID);
        final expertId =
            pending?.expertId ?? expertIdFromProductId(p.productID);
        final result = await _verifyWithBackend(p, expertId);
        if (p.pendingCompletePurchase) await _store.completePurchase(p);
        if (p.status == PurchaseStatus.restored && result.ok) {
          verifiedRestores.value++;
        }
        _completeMatching(p.productID, result);
        return;
    }
  }

  /// A tier purchase is finished with the store only once the backend has
  /// granted it. Otherwise it stays open: the store delivers it again on
  /// the next launch (and Google refunds it if it is never acknowledged),
  /// so a paid purchase is never silently lost.
  Future<void> _handleAccessPurchase(PurchaseDetails p) async {
    final user = await AuthService.getUser();
    final target =
        _firstPendingFor(p.productID)?.target ??
        (user == null
            ? null
            : await AccessTargetStore.load(p.productID, user.id));
    if (target == null) {
      debugPrint('[iap] ${p.productID}: no target known, left open');
      _completeMatching(
        p.productID,
        const IAPVerificationResult(
          ok: false,
          error: 'Purchase could not be matched. Please try again.',
        ),
      );
      return;
    }
    final result = await _verifyWithBackend(p, null, target: target);
    if (result.ok) {
      if (p.pendingCompletePurchase) await _store.completePurchase(p);
      await AccessTargetStore.clear(p.productID);
    }
    _completeMatching(p.productID, result);
  }

  /// Saves [target] as the open purchase of [productId] for the signed-in
  /// user. Returns an error result when another target or account still
  /// has an open purchase of the same product.
  Future<IAPVerificationResult?> _reserveAccessTarget(
    String productId,
    AccessTarget target,
  ) async {
    final user = await AuthService.getUser();
    if (user == null) {
      return const IAPVerificationResult(
        ok: false,
        error: 'Please sign in first.',
      );
    }
    final open = await AccessTargetStore.open(productId);
    final sameBuy =
        open == null ||
        (open.userId == user.id && open.target.encode() == target.encode());
    if (!sameBuy) {
      return IAPVerificationResult(
        ok: false,
        error: 'subscribe.error.previousOpen'.tr,
      );
    }
    await AccessTargetStore.save(productId, user.id, target);
    return null;
  }

  /// The backend verify call for this platform, or null where purchases
  /// cannot be verified. iOS sends the App Store receipt; Android sends the
  /// Google Play purchase token (serverVerificationData on Android).
  @visibleForTesting
  static ({Uri uri, Map<String, dynamic> body})? verifyRequestFor({
    required bool isIOS,
    required bool isAndroid,
    required String baseUrl,
    required String storeData,
    required String productId,
    String? expertId,
    AccessTarget? target,
    String? transactionId,
  }) {
    if (!isIOS && !isAndroid) return null;
    if (target != null) {
      return (
        uri: Uri.parse('$baseUrl/me/iap/access/${isIOS ? 'apple' : 'google'}'),
        body: {
          isIOS ? 'receiptData' : 'purchaseToken': storeData,
          'productId': productId,
          if (isIOS) 'transactionId': transactionId ?? '',
          'targetType': target.type,
          'targetId': target.id,
        },
      );
    }
    return (
      uri: Uri.parse(
        isIOS
            ? '$baseUrl/me/iap/apple/verify'
            : '$baseUrl/me/iap/google/verify',
      ),
      body: {
        isIOS ? 'receiptData' : 'purchaseToken': storeData,
        'productId': productId,
        if (expertId != null && expertId.isNotEmpty) 'expertId': expertId,
      },
    );
  }

  Future<IAPVerificationResult> _verifyWithBackend(
    PurchaseDetails p,
    String? expertId, {
    AccessTarget? target,
  }) async {
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

    final request = verifyRequestFor(
      isIOS: Platform.isIOS,
      isAndroid: Platform.isAndroid,
      baseUrl: ApiConfig.baseUrl,
      storeData: receipt,
      productId: p.productID,
      expertId: expertId,
      target: target,
      transactionId: p.purchaseID,
    );
    if (request == null) {
      return const IAPVerificationResult(
        ok: false,
        error: 'Verification is not yet supported on this platform.',
      );
    }

    try {
      final response = await http
          .post(
            request.uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: json.encode(request.body),
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
  final AccessTarget? target;
  final Completer<IAPVerificationResult> completer;
  String key = '';
  _PendingBuy({
    required this.productId,
    required this.expertId,
    required this.completer,
    this.target,
  });
}
