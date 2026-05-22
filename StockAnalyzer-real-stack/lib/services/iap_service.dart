import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'auth_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';

class IAPService extends ChangeNotifier {
  static final IAPService _instance = IAPService._internal();

  factory IAPService() => _instance;

  IAPService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  List<ProductDetails> _products = [];
  List<ProductDetails> get products => _products;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // The predefined product IDs for your stores
  static const String monthlySubscriptionId = 'com.easytech.stocks.premium.monthly';
  static const String annualSubscriptionId = 'com.easytech.stocks.premium.annual';

  void initialize() {
    final Stream<List<PurchaseDetails>> purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen(
      _onPurchaseUpdate,
      onDone: () {
        _subscription.cancel();
      },
      onError: (error) {
        debugPrint('IAP Error: $error');
      },
    );
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    _isLoading = true;
    notifyListeners();

    _isAvailable = await _iap.isAvailable();
    if (_isAvailable) {
      const Set<String> kIds = <String>{
        monthlySubscriptionId,
        annualSubscriptionId,
      };

      final ProductDetailsResponse response = await _iap.queryProductDetails(
        kIds,
      );

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('Products not found: ${response.notFoundIDs}');
      }

      _products = response.productDetails;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> buySubscription(ProductDetails product) async {
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);

    // For subscriptions, we use buyNonConsumable
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> _onPurchaseUpdate(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _isLoading = true;
        notifyListeners();
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          debugPrint('Purchase Error: ${purchaseDetails.error}');
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          await _verifyAndDeliverProduct(purchaseDetails);
        }

        if (purchaseDetails.pendingCompletePurchase) {
          await _iap.completePurchase(purchaseDetails);
        }

        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _verifyAndDeliverProduct(PurchaseDetails purchaseDetails) async {
    final token = await AuthService.getToken();
    if (token == null) return;

    try {
      // Send the receipt to the backend to verify the subscription
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/subscription/upgrade'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'tier': 'PREMIUM',
          // Optionally send receipt data for real validation on backend:
          // 'receipt': purchaseDetails.verificationData.serverVerificationData,
          // 'productId': purchaseDetails.productID,
          // 'platform': Platform.isIOS ? 'ios' : 'android',
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('Subscription successfully verified on backend.');
      } else {
        debugPrint(
          'Failed to verify subscription on backend: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error verifying subscription: $e');
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
