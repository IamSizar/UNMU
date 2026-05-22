import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';

/// Mirror of backend `repositories.Payout` (mig 0042). Joined fields
/// (userEmail / userName / processorEmail) are empty on user-facing
/// reads — they're only populated by the admin queue.
class Payout {
  final int id;
  final int userId;
  final String expertId;
  final int amountCents;
  final String currency;
  final String method;
  final Map<String, dynamic> paymentDetails;
  final String status; // pending | paid | rejected | cancelled
  final String? adminNote;
  final DateTime? processedAt;
  final DateTime requestedAt;

  const Payout({
    required this.id,
    required this.userId,
    required this.expertId,
    required this.amountCents,
    required this.currency,
    required this.method,
    required this.paymentDetails,
    required this.status,
    required this.adminNote,
    required this.processedAt,
    required this.requestedAt,
  });

  factory Payout.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> details = {};
    final raw = j['paymentDetails'];
    if (raw is Map<String, dynamic>) {
      details = raw;
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is Map<String, dynamic>) details = decoded;
      } catch (_) {}
    }
    return Payout(
      id: (j['id'] as num).toInt(),
      userId: (j['userId'] as num?)?.toInt() ?? 0,
      expertId: (j['expertId'] as String?) ?? '',
      amountCents: (j['amountCents'] as num?)?.toInt() ?? 0,
      currency: (j['currency'] as String?) ?? 'usd',
      method: (j['method'] as String?) ?? '',
      paymentDetails: details,
      status: (j['status'] as String?) ?? 'pending',
      adminNote: j['adminNote'] as String?,
      processedAt: j['processedAt'] != null
          ? DateTime.tryParse(j['processedAt'] as String)
          : null,
      requestedAt: DateTime.tryParse(j['requestedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Composite payload for the earnings screen's payouts area.
class PayoutsSnapshot {
  final int availableCents;
  final int lifetimeCents;
  final String currency;
  final List<Payout> payouts;

  const PayoutsSnapshot({
    required this.availableCents,
    required this.lifetimeCents,
    required this.currency,
    required this.payouts,
  });

  factory PayoutsSnapshot.fromJson(Map<String, dynamic> j) => PayoutsSnapshot(
        availableCents: (j['availableCents'] as num?)?.toInt() ?? 0,
        lifetimeCents: (j['lifetimeCents'] as num?)?.toInt() ?? 0,
        currency: ((j['currency'] as String?) ?? 'usd').toLowerCase(),
        payouts: (j['payouts'] as List<dynamic>? ?? [])
            .map((e) => Payout.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Backend-accepted payout methods. Mirrors `allowedPayoutMethods` in
/// handlers/payouts.go — keep in sync if you add another option.
enum PayoutMethod { bank, fib, paypal, other }

extension PayoutMethodX on PayoutMethod {
  String get wireValue {
    switch (this) {
      case PayoutMethod.bank:
        return 'bank';
      case PayoutMethod.fib:
        return 'fib';
      case PayoutMethod.paypal:
        return 'paypal';
      case PayoutMethod.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case PayoutMethod.bank:
        return 'Bank transfer';
      case PayoutMethod.fib:
        return 'FIB (First Iraqi Bank)';
      case PayoutMethod.paypal:
        return 'PayPal';
      case PayoutMethod.other:
        return 'Other';
    }
  }

  static PayoutMethod fromWire(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'fib':
        return PayoutMethod.fib;
      case 'paypal':
        return PayoutMethod.paypal;
      case 'other':
        return PayoutMethod.other;
      default:
        return PayoutMethod.bank;
    }
  }
}

class PayoutService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/me/expert/payouts
  static Future<({PayoutsSnapshot? snapshot, String? error})> mine() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/me/expert/payouts'),
              headers: await _authHeaders())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        return (snapshot: PayoutsSnapshot.fromJson(body), error: null);
      }
      return (snapshot: null, error: _errorOf(res));
    } catch (e) {
      return (snapshot: null, error: 'Network error: $e');
    }
  }

  /// POST /api/me/expert/payouts/request
  static Future<({Payout? payout, String? error, bool insufficient})>
      request({
    required int amountCents,
    required PayoutMethod method,
    required Map<String, dynamic> paymentDetails,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/me/expert/payouts/request'),
            headers: await _authHeaders(),
            body: json.encode({
              'amountCents': amountCents,
              'method': method.wireValue,
              'paymentDetails': paymentDetails,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 201) {
        return (
          payout: Payout.fromJson(json.decode(res.body) as Map<String, dynamic>),
          error: null,
          insufficient: false,
        );
      }
      final body = _safeDecode(res.body);
      final insufficient = body['code'] == 'INSUFFICIENT_BALANCE';
      return (
        payout: null,
        error: (body['error'] ?? 'Request failed.').toString(),
        insufficient: insufficient,
      );
    } catch (e) {
      return (payout: null, error: 'Network error: $e', insufficient: false);
    }
  }

  /// POST /api/me/expert/payouts/:id/cancel
  static Future<({Payout? payout, String? error})> cancel(int id) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/me/expert/payouts/$id/cancel'),
              headers: await _authHeaders())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return (
          payout: Payout.fromJson(json.decode(res.body) as Map<String, dynamic>),
          error: null,
        );
      }
      return (payout: null, error: _errorOf(res));
    } catch (e) {
      return (payout: null, error: 'Network error: $e');
    }
  }

  static Map<String, dynamic> _safeDecode(String s) {
    try {
      final v = json.decode(s);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return {};
  }

  static String _errorOf(http.Response res) {
    final b = _safeDecode(res.body);
    return b['error']?.toString() ?? 'Request failed (${res.statusCode}).';
  }
}
