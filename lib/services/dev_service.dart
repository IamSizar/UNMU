import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/user.dart';

/// Wrapper around the dev-only routes added in backend/handlers/dev.go.
///
/// Both `/api/dev/users` and `/api/dev/impersonate` are gated server-side
/// by `APP_ENV != "production"` — they return 404 in real deploys. The
/// "Switch account" sheet uses these to list every DB account and swap
/// session without a password.
class DevService {
  static String get _base => '${ApiConfig.baseUrl}/dev';

  /// Returns every account currently in the DB (dev mode only).
  ///
  /// `null` when the backend is unreachable OR the route returns 404
  /// (production). The switcher falls back to the hardcoded preset list
  /// in that case.
  static Future<List<DevUser>?> listUsers() async {
    try {
      final response = await http
          .get(Uri.parse('$_base/users'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        debugPrint('DevService.listUsers: HTTP ${response.statusCode}');
        return null;
      }
      final body = json.decode(response.body) as Map<String, dynamic>;
      final raw = (body['users'] as List?) ?? const [];
      return raw
          .map((e) => DevUser.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      debugPrint('DevService.listUsers error: $e');
      return null;
    }
  }

  /// Wipes every user-generated row in the dev database except the admin
  /// account (id=1000) — see backend `dev.go:Reset`. Returns the wiped-row
  /// summary on success, or `null` if the backend rejected / errored.
  ///
  /// Requires the `X-Confirm` header so a stray request can't accidentally
  /// nuke the DB. Dev-mode gated server-side.
  static Future<DevResetSummary?> resetAll() async {
    try {
      final response = await http.post(
        Uri.parse('$_base/reset'),
        headers: const {
          'Content-Type': 'application/json',
          'X-Confirm': 'yes-wipe-everything',
        },
      );
      if (response.statusCode != 200) {
        debugPrint('DevService.resetAll: HTTP ${response.statusCode} body=${response.body}');
        return null;
      }
      final body = json.decode(response.body) as Map<String, dynamic>;
      final wipedRaw = body['wiped'] as Map<String, dynamic>? ?? {};
      final wiped = <String, int>{};
      wipedRaw.forEach((k, v) {
        if (v is num) wiped[k] = v.toInt();
      });
      return DevResetSummary(wiped: wiped);
    } catch (e) {
      debugPrint('DevService.resetAll error: $e');
      return null;
    }
  }

  /// Issues a JWT for the given email without checking a password. Returns
  /// `(token, user)` on success, `null` if the backend rejected it. The
  /// caller passes the result to [AuthController.applySession].
  static Future<({String token, User user})?> impersonate(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$_base/impersonate'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      );
      if (response.statusCode != 200) {
        debugPrint('DevService.impersonate: HTTP ${response.statusCode}');
        return null;
      }
      final body = json.decode(response.body) as Map<String, dynamic>;
      final token = body['token'] as String?;
      final userJson = body['user'] as Map<String, dynamic>?;
      if (token == null || userJson == null) return null;
      return (token: token, user: User.fromJson(userJson));
    } catch (e) {
      debugPrint('DevService.impersonate error: $e');
      return null;
    }
  }
}

/// A row from `/api/dev/users` — used to render the switcher list.
class DevUser {
  final int id;
  final String email;
  final String? name;
  final String role; // USER / EXPERT / ADMIN
  final String? expertId;
  final String subscriptionTier;
  final bool emailVerified;
  final String createdAt;

  const DevUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.expertId,
    required this.subscriptionTier,
    required this.emailVerified,
    required this.createdAt,
  });

  factory DevUser.fromJson(Map<String, dynamic> j) => DevUser(
        id: (j['id'] as num).toInt(),
        email: j['email'] as String,
        name: j['name'] as String?,
        role: (j['role'] as String?) ?? 'USER',
        expertId: j['expertId'] as String?,
        subscriptionTier: (j['subscriptionTier'] as String?) ?? 'FREE',
        emailVerified: j['emailVerified'] == true,
        createdAt: (j['createdAt'] as String?) ?? '',
      );

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return email.split('@').first;
  }
}

/// Result of a successful [DevService.resetAll] call.
class DevResetSummary {
  /// Row counts per table BEFORE the wipe — handy for showing the user
  /// what disappeared ("18 users, 9 communities, 34 posts, ...").
  final Map<String, int> wiped;
  const DevResetSummary({required this.wiped});

  int get totalRows => wiped.values.fold(0, (a, b) => a + b);
  int get users => wiped['users'] ?? 0;
  int get communities => wiped['communities'] ?? 0;
  int get posts => wiped['posts'] ?? 0;
  int get experts => wiped['experts'] ?? 0;
}
