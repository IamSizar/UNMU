// Value types for IAPService (iap_service.dart), split out to keep that
// file under 500 lines. Re-exported by iap_service.dart.
import 'package:in_app_purchase/in_app_purchase.dart';

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
