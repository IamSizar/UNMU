import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import 'auth_service.dart';

/// Mirrors the backend `repositories.CommunitySubscription` shape
/// (mig 0022). Used by:
///
///   * the social hub's "Pending payment" sub-section
///   * the user's own community-subscription history
///   * the community-preview screen (when status=pending|active for
///     this community, drives the CTA copy)
class CommunitySubscriptionRow {
  final int id;
  final int userId;
  final String communityId;
  final String communityName;
  final String plan; // monthly | yearly
  final String status; // pending | active | rejected | cancelled | expired
  final int priceCents;
  final String currency;
  final String paymentMethod; // cash | fib
  final String paymentRef;
  /// Cash-receipt image URL (mig 0025). Empty when not uploaded.
  final String receiptUrl;
  final String userNote;
  final String rejectionReason;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? rejectedAt;
  final DateTime? cancelledAt;
  final DateTime? expiresAt;

  const CommunitySubscriptionRow({
    required this.id,
    required this.userId,
    required this.communityId,
    required this.communityName,
    required this.plan,
    required this.status,
    required this.priceCents,
    required this.currency,
    required this.paymentMethod,
    required this.paymentRef,
    required this.receiptUrl,
    required this.userNote,
    required this.rejectionReason,
    required this.createdAt,
    this.acceptedAt,
    this.rejectedAt,
    this.cancelledAt,
    this.expiresAt,
  });

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';

  factory CommunitySubscriptionRow.fromJson(Map<String, dynamic> json) {
    DateTime? parseTs(Object? raw) =>
        raw == null ? null : DateTime.tryParse(raw.toString());
    return CommunitySubscriptionRow(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      communityId: json['communityId'] as String? ?? '',
      communityName: json['communityName'] as String? ?? '',
      plan: json['plan'] as String? ?? 'monthly',
      status: json['status'] as String? ?? 'pending',
      priceCents: (json['priceCents'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'usd',
      paymentMethod: json['paymentMethod'] as String? ?? 'cash',
      paymentRef: json['paymentRef'] as String? ?? '',
      receiptUrl: json['receiptUrl'] as String? ?? '',
      userNote: json['userNote'] as String? ?? '',
      rejectionReason: json['rejectionReason'] as String? ?? '',
      createdAt: parseTs(json['createdAt']) ?? DateTime.now(),
      acceptedAt: parseTs(json['acceptedAt']),
      rejectedAt: parseTs(json['rejectedAt']),
      cancelledAt: parseTs(json['cancelledAt']),
      expiresAt: parseTs(json['expiresAt']),
    );
  }
}

/// REST surface for paid community memberships (step-23 / mig 0022).
class CommunitySubscriptionService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// POST /api/communities/:id/subscribe
  ///
  /// `receiptUrl` is the relative path to a cash-receipt image (uploaded
  /// via [UploadService.uploadImage]). Mirrors the expert subscription
  /// flow's receipt support added in mig 0024.
  static Future<({CommunitySubscriptionRow? sub, String? error})> subscribe({
    required String communityId,
    required String plan, // monthly | yearly
    required String paymentMethod, // cash | fib
    String? paymentRef,
    String? receiptUrl,
    String? userNote,
    String? promoCode,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/communities/$communityId/subscribe'),
        headers: await _authHeaders(),
        body: json.encode({
          'plan': plan,
          'paymentMethod': paymentMethod,
          if (paymentRef != null && paymentRef.isNotEmpty)
            'paymentRef': paymentRef,
          if (receiptUrl != null && receiptUrl.isNotEmpty)
            'receiptUrl': receiptUrl,
          if (userNote != null && userNote.isNotEmpty) 'userNote': userNote,
          if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode,
        }),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (sub: null, error: 'Session expired.');
      }
      if (res.statusCode != 201) {
        return (
          sub: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Subscribe failed (${res.statusCode}).',
        );
      }
      return (
        sub: CommunitySubscriptionRow.fromJson(
          json.decode(res.body) as Map<String, dynamic>,
        ),
        error: null,
      );
    } catch (e) {
      return (sub: null, error: 'Connection error: $e');
    }
  }

  /// GET /api/me/community-subscriptions — user's own history.
  static Future<({List<CommunitySubscriptionRow>? rows, String? error})>
      mySubs() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/me/community-subscriptions'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (rows: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        return (
          rows: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Load failed (${res.statusCode}).',
        );
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = (body['subscriptions'] as List<dynamic>? ?? const [])
          .map((e) => CommunitySubscriptionRow.fromJson(
                e as Map<String, dynamic>,
              ))
          .toList();
      return (rows: list, error: null);
    } catch (e) {
      return (rows: null, error: 'Connection error: $e');
    }
  }

  /// Convenience helper for the social hub: returns the set of
  /// community IDs the current user has a PENDING subscription for
  /// (status=pending — submitted, admin reviewing payment). Drives the
  /// gold "Pending" pill on community cards.
  ///
  /// On any failure (network down, 401 already handled) returns an
  /// empty set so the UI degrades gracefully — worst case the card
  /// reverts to its plain Join/Joined logic.
  static Future<Set<String>> myPendingCommunityIds() async {
    final res = await mySubs();
    final rows = res.rows;
    if (rows == null) return const <String>{};
    return rows
        .where((r) => r.isPending)
        .map((r) => r.communityId)
        .toSet();
  }

  /// DELETE /api/community-subscriptions/:id — cancel own.
  static Future<({bool ok, String? error})> cancel(int subId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_base/community-subscriptions/$subId'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (ok: false, error: 'Session expired.');
      }
      if (res.statusCode == 200) return (ok: true, error: null);
      return (
        ok: false,
        error: _safeDecode(res.body)['error']?.toString() ??
            'Cancel failed (${res.statusCode}).',
      );
    } catch (e) {
      return (ok: false, error: 'Connection error: $e');
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
