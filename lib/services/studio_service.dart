import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';

/// Mirror of backend `repositories.ExpertTotals` (Phase 3.1).
class ExpertSubscriberTotals {
  final int activeSubscribers;
  final int pendingSubscribers;
  final int lifetimeSubscribers;
  final int lifetimeRevenueCents;
  final int activeRevenueCents;
  final String currency;

  const ExpertSubscriberTotals({
    required this.activeSubscribers,
    required this.pendingSubscribers,
    required this.lifetimeSubscribers,
    required this.lifetimeRevenueCents,
    required this.activeRevenueCents,
    required this.currency,
  });

  factory ExpertSubscriberTotals.fromJson(Map<String, dynamic> j) =>
      ExpertSubscriberTotals(
        activeSubscribers: (j['activeSubscribers'] as num?)?.toInt() ?? 0,
        pendingSubscribers: (j['pendingSubscribers'] as num?)?.toInt() ?? 0,
        lifetimeSubscribers: (j['lifetimeSubscribers'] as num?)?.toInt() ?? 0,
        lifetimeRevenueCents:
            (j['lifetimeRevenueCents'] as num?)?.toInt() ?? 0,
        activeRevenueCents: (j['activeRevenueCents'] as num?)?.toInt() ?? 0,
        currency: (j['currency'] as String?) ?? 'usd',
      );
}

/// Mirror of `repositories.ExpertEngagementTotals`.
class ExpertEngagementTotals {
  final int posts;
  final int likes;
  final int comments;
  final int saves;
  final int shares;

  const ExpertEngagementTotals({
    required this.posts,
    required this.likes,
    required this.comments,
    required this.saves,
    required this.shares,
  });

  factory ExpertEngagementTotals.fromJson(Map<String, dynamic> j) =>
      ExpertEngagementTotals(
        posts: (j['posts'] as num?)?.toInt() ?? 0,
        likes: (j['likes'] as num?)?.toInt() ?? 0,
        comments: (j['comments'] as num?)?.toInt() ?? 0,
        saves: (j['saves'] as num?)?.toInt() ?? 0,
        shares: (j['shares'] as num?)?.toInt() ?? 0,
      );
}

/// One row of the daily earnings chart.
class EarningsDayPoint {
  final String day; // YYYY-MM-DD
  final int revenueCents;
  final int newSubs;

  const EarningsDayPoint({
    required this.day,
    required this.revenueCents,
    required this.newSubs,
  });

  factory EarningsDayPoint.fromJson(Map<String, dynamic> j) => EarningsDayPoint(
        day: (j['day'] as String?) ?? '',
        revenueCents: (j['revenueCents'] as num?)?.toInt() ?? 0,
        newSubs: (j['newSubs'] as num?)?.toInt() ?? 0,
      );
}

/// Composite shape returned by GET /me/expert/dashboard.
class StudioDashboard {
  final String expertId;
  final String expertName;
  final int monthlyPriceCents;
  final int yearlyPriceCents;
  final String currency;
  final ExpertSubscriberTotals? subscribers;
  final ExpertEngagementTotals? engagement;

  const StudioDashboard({
    required this.expertId,
    required this.expertName,
    required this.monthlyPriceCents,
    required this.yearlyPriceCents,
    required this.currency,
    required this.subscribers,
    required this.engagement,
  });

  factory StudioDashboard.fromJson(Map<String, dynamic> j) => StudioDashboard(
        expertId: (j['expertId'] as String?) ?? '',
        expertName: (j['expertName'] as String?) ?? '',
        monthlyPriceCents: (j['monthlyPriceCents'] as num?)?.toInt() ?? 0,
        yearlyPriceCents: (j['yearlyPriceCents'] as num?)?.toInt() ?? 0,
        currency: ((j['priceCurrency'] as String?) ?? 'usd').toLowerCase(),
        subscribers: j['subscribers'] is Map<String, dynamic>
            ? ExpertSubscriberTotals.fromJson(
                j['subscribers'] as Map<String, dynamic>)
            : null,
        engagement: j['engagement'] is Map<String, dynamic>
            ? ExpertEngagementTotals.fromJson(
                j['engagement'] as Map<String, dynamic>)
            : null,
      );
}

/// Earnings screen payload.
class EarningsResponse {
  final int days;
  final int windowRevenueCents;
  final int lifetimeRevenueCents;
  final int activeRevenueCents;
  final String currency;
  final List<EarningsDayPoint> history;

  const EarningsResponse({
    required this.days,
    required this.windowRevenueCents,
    required this.lifetimeRevenueCents,
    required this.activeRevenueCents,
    required this.currency,
    required this.history,
  });

  factory EarningsResponse.fromJson(Map<String, dynamic> j) => EarningsResponse(
        days: (j['days'] as num?)?.toInt() ?? 0,
        windowRevenueCents: (j['windowRevenue'] as num?)?.toInt() ?? 0,
        lifetimeRevenueCents: (j['lifetimeRevenue'] as num?)?.toInt() ?? 0,
        activeRevenueCents: (j['activeRevenue'] as num?)?.toInt() ?? 0,
        currency: ((j['currency'] as String?) ?? 'usd').toLowerCase(),
        history: (j['history'] as List<dynamic>? ?? [])
            .map((e) => EarningsDayPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Network plumbing for the expert studio (Phase 3.1–3.3).
///
/// All endpoints are gated server-side: callers who aren't experts get
/// 403 NOT_EXPERT. The methods here translate that into a typed error
/// so the UI can route the user to the Become-Expert flow instead of
/// dead-ending at a generic toast.
class StudioService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/me/expert/dashboard
  static Future<({StudioDashboard? dashboard, String? error})> dashboard() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/me/expert/dashboard'),
              headers: await _authHeaders())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        return (dashboard: StudioDashboard.fromJson(body), error: null);
      }
      return (dashboard: null, error: _errorOf(res));
    } catch (e) {
      return (dashboard: null, error: 'Network error: $e');
    }
  }

  /// GET /api/me/expert/earnings?days=N
  static Future<({EarningsResponse? earnings, String? error})> earnings({
    int days = 30,
  }) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/me/expert/earnings?days=$days'),
              headers: await _authHeaders())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        return (earnings: EarningsResponse.fromJson(body), error: null);
      }
      return (earnings: null, error: _errorOf(res));
    } catch (e) {
      return (earnings: null, error: 'Network error: $e');
    }
  }

  /// PATCH /api/me/expert/pricing  body { monthlyCents, yearlyCents }
  static Future<({String? error})> setPricing({
    required int monthlyCents,
    required int yearlyCents,
  }) async {
    try {
      final res = await http
          .patch(
            Uri.parse('$_base/me/expert/pricing'),
            headers: await _authHeaders(),
            body: json.encode({
              'monthlyCents': monthlyCents,
              'yearlyCents': yearlyCents,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return (error: null);
      return (error: _errorOf(res));
    } catch (e) {
      return (error: 'Network error: $e');
    }
  }

  static String _errorOf(http.Response response) {
    try {
      final v = json.decode(response.body);
      if (v is Map<String, dynamic> && v['error'] != null) {
        return v['error'].toString();
      }
    } catch (_) {}
    return 'Request failed (${response.statusCode}).';
  }
}

/// Helper for the on-screen pretty prices.
String formatCents(int cents, String currency) {
  final dollars = cents / 100;
  final symbol = currency.toLowerCase() == 'usd'
      ? '\$'
      : '${currency.toUpperCase()} ';
  return '$symbol${dollars.toStringAsFixed(dollars.truncateToDouble() == dollars ? 0 : 2)}';
}
