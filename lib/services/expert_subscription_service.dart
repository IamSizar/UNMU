import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import '../models/expert_subscription.dart';
import 'auth_service.dart';

/// Network calls for the user-facing subscription flow (Step 4).
class ExpertSubscriptionService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// POST /api/experts/:id/subscriptions — create a pending subscription.
  ///
  /// `receiptUrl` is the relative path to a cash-receipt image uploaded
  /// via [UploadService.uploadImage] (mig 0024 / B10). Null = no image.
  static Future<({ExpertSubscription? sub, String? error})> subscribe({
    required String expertId,
    required SubPlan plan,
    required PaymentMethod method,
    String? paymentRef,
    String? receiptUrl,
    String? note,
    String? promoCode,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_base/experts/$expertId/subscriptions'),
        headers: await _authHeaders(),
        body: json.encode({
          'plan': plan.wireValue,
          'paymentMethod': method.wireValue,
          if (paymentRef != null && paymentRef.isNotEmpty) 'paymentRef': paymentRef,
          if (receiptUrl != null && receiptUrl.isNotEmpty) 'receiptUrl': receiptUrl,
          if (note != null && note.isNotEmpty) 'userNote': note,
          if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode,
        }),
      );
      if (response.statusCode == 201) {
        return (
          sub: ExpertSubscription.fromJson(
            json.decode(response.body) as Map<String, dynamic>,
          ),
          error: null,
        );
      }
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (sub: null, error: 'Session expired — please sign in again.');
      }
      final body = _safeDecode(response.body);
      return (sub: null, error: body['error']?.toString() ?? 'Subscribe failed');
    } catch (e) {
      return (sub: null, error: 'Connection error: $e');
    }
  }

  /// GET /api/me/subscriptions/expert/:id — current sub for one expert, or null.
  static Future<ExpertSubscription?> currentForExpert(String expertId) async {
    try {
      final response = await http.get(
        Uri.parse('$_base/me/subscriptions/expert/$expertId'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return null;
      }
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      if (body['status'] == 'none' || body['id'] == null) return null;
      return ExpertSubscription.fromJson(body);
    } catch (_) {
      return null;
    }
  }

  /// GET /api/me/subscriptions — every sub the user has across all experts.
  static Future<List<ExpertSubscription>> mySubscriptions() async {
    try {
      final response = await http.get(
        Uri.parse('$_base/me/subscriptions'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return const [];
      }
      if (response.statusCode != 200) return const [];
      final body = json.decode(response.body) as Map<String, dynamic>;
      final list = (body['subscriptions'] as List<dynamic>? ?? [])
          .map((e) => ExpertSubscription.fromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// GET /api/experts/:id — fetch the expert row so the SubscribeModal can
  /// render live per-plan prices (mig 0024). Returns null on any failure
  /// (caller should fall back to defaults).
  static Future<ExpertPricing?> fetchExpertPricing(String expertId) async {
    try {
      final response = await http.get(
        Uri.parse('$_base/experts/$expertId'),
        headers: await _authHeaders(),
      );
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      return ExpertPricing(
        monthlyCents: (body['monthlyPriceCents'] as num?)?.toInt() ?? 1000,
        yearlyCents: (body['yearlyPriceCents'] as num?)?.toInt() ?? 9600,
        currency: (body['priceCurrency'] as String?)?.toLowerCase() ?? 'usd',
      );
    } catch (_) {
      return null;
    }
  }

  /// DELETE /api/subscriptions/:id — user cancels.
  static Future<({ExpertSubscription? sub, String? error})> cancel(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$_base/subscriptions/$id'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 200) {
        return (
          sub: ExpertSubscription.fromJson(
            json.decode(response.body) as Map<String, dynamic>,
          ),
          error: null,
        );
      }
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (sub: null, error: 'Session expired — please sign in again.');
      }
      final body = _safeDecode(response.body);
      return (sub: null, error: body['error']?.toString() ?? 'Cancel failed');
    } catch (e) {
      return (sub: null, error: 'Connection error: $e');
    }
  }

  static Map<String, dynamic> _safeDecode(String s) {
    try {
      final v = json.decode(s);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return {};
  }
}

/// Lightweight per-expert pricing — what the SubscribeModal needs to
/// render the current plan prices live from the backend.
class ExpertPricing {
  final int monthlyCents;
  final int yearlyCents;
  final String currency;
  const ExpertPricing({
    required this.monthlyCents,
    required this.yearlyCents,
    required this.currency,
  });

  String formatCents(int cents) {
    final dollars = cents / 100;
    final symbol = currency.toLowerCase() == 'usd'
        ? '\$'
        : '${currency.toUpperCase()} ';
    return '$symbol${dollars.toStringAsFixed(dollars.truncateToDouble() == dollars ? 0 : 2)}';
  }

  String get monthlyLabel => formatCents(monthlyCents);
  String get yearlyLabel => formatCents(yearlyCents);

  /// Closer-to-monthly figure for the yearly plan ("works out to $8/mo").
  String get yearlyMonthlyEquivalent => formatCents((yearlyCents / 12).round());

  int centsForPlan(SubPlan plan) {
    switch (plan) {
      case SubPlan.monthly:
        return monthlyCents;
      case SubPlan.yearly:
        return yearlyCents;
    }
  }
}
