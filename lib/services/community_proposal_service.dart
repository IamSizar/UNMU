import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import '../models/community_proposal.dart';
import 'auth_service.dart';

/// Network calls for the "expert proposes a community" flow.
///
/// Backend routes (wired in `backend/cmd/api/main.go` 631..632):
///   * `POST /api/me/community-proposals` — submit a new proposal
///   * `GET  /api/me/community-proposals` — list the current user's proposals
///
/// Both require a JWT. Submit is also gated EXPERT-only on the server, so
/// callers should hide the entry point unless `auth.user.role == EXPERT`.
class CommunityProposalService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Submit a new proposal. Returns either:
  ///
  ///   * `(proposal: X, error: null, pendingExists: false)` on 200
  ///   * `(proposal: null, error: msg, pendingExists: true)` on 409 — the
  ///     user already has a pending proposal awaiting admin review.
  ///   * `(proposal: null, error: msg)` for anything else (400 validation,
  ///     403 not-expert, 500, network)
  static Future<
      ({
        CommunityProposal? proposal,
        String? error,
        bool pendingExists,
      })> submit({
    required String name,
    required String description,
    String? regionCode,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_base/me/community-proposals'),
        headers: await _authHeaders(),
        body: json.encode({
          'name': name.trim(),
          'description': description.trim(),
          if (regionCode != null && regionCode.isNotEmpty)
            'regionCode': regionCode.toUpperCase(),
        }),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final p = body['proposal'] as Map<String, dynamic>?;
        if (p == null) {
          return (
            proposal: null,
            error: 'Unexpected server response.',
            pendingExists: false,
          );
        }
        return (
          proposal: CommunityProposal.fromJson(p),
          error: null,
          pendingExists: false,
        );
      }

      if (response.statusCode == 401) {
        // Stale token — kick back to login.
        await Get.find<AuthController>().handleAuthFailure();
        return (
          proposal: null,
          error: 'Session expired — please sign in again.',
          pendingExists: false,
        );
      }

      final body = _safeDecode(response.body);

      if (response.statusCode == 409) {
        return (
          proposal: null,
          error: body['error']?.toString() ??
              'You already have a pending proposal.',
          pendingExists: true,
        );
      }

      return (
        proposal: null,
        error: body['error']?.toString() ?? 'Submit failed (HTTP ${response.statusCode})',
        pendingExists: false,
      );
    } catch (e) {
      return (
        proposal: null,
        error: 'Connection error: $e',
        pendingExists: false,
      );
    }
  }

  /// Returns every proposal the current user has ever submitted, newest
  /// first. Returns an empty list on network failure (matches the calling
  /// UI's expectation — "no proposals yet" is rendered when empty).
  static Future<List<CommunityProposal>> listMine() async {
    try {
      final response = await http.get(
        Uri.parse('$_base/me/community-proposals'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return const [];
      }
      if (response.statusCode != 200) return const [];

      final body = json.decode(response.body) as Map<String, dynamic>;
      final raw = (body['proposals'] as List?) ?? const [];
      return raw
          .map((e) => CommunityProposal.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return const [];
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
