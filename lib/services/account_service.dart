import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/user.dart';
import 'auth_service.dart';

/// Network plumbing for the "Account" settings screens — change
/// password, change email (two-step), delete account.
///
/// Each method returns a record:
///   - `error: null` on success
///   - `error: <message>` on failure (HTTP non-2xx or network error)
///
/// The matching Flutter screens (Phase 2.7) consume these.
class AccountService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ─── change password ─────────────────────────────────────────────────

  /// POST /api/me/change-password
  ///
  /// Verifies the current password, then writes a new bcrypt hash. The
  /// caller's JWT stays valid afterwards.
  static Future<({String? error})> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/me/change-password'),
            headers: await _authHeaders(),
            body: json.encode({
              'currentPassword': currentPassword,
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return (error: null);
      return (error: _errorOf(response));
    } catch (e) {
      return (error: 'Network error: $e');
    }
  }

  // ─── change email (two-step) ─────────────────────────────────────────

  /// POST /api/me/change-email/request — sends a 6-digit code to the
  /// NEW address. Caller follows up with [confirmEmailChange] once the
  /// user types the code into the UI.
  ///
  /// In dev mode the response includes `verificationCode` so testers
  /// can skip the email round-trip; production responses omit it.
  static Future<({String? error, String? devCode})> requestEmailChange({
    required String newEmail,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/me/change-email/request'),
            headers: await _authHeaders(),
            body: json.encode({
              'newEmail': newEmail,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final body = _safeDecode(response.body);
        return (
          error: null,
          devCode: body['verificationCode'] as String?,
        );
      }
      return (error: _errorOf(response), devCode: null);
    } catch (e) {
      return (error: 'Network error: $e', devCode: null);
    }
  }

  /// POST /api/me/change-email/confirm — consumes the code from
  /// [requestEmailChange] and flips users.email. Returns the refreshed
  /// User on success so the AuthController can swap it into its
  /// session cache.
  static Future<({User? user, String? error})> confirmEmailChange(String code) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/me/change-email/confirm'),
            headers: await _authHeaders(),
            body: json.encode({'code': code}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final body = _safeDecode(response.body);
        return (user: User.fromJson(body), error: null);
      }
      return (user: null, error: _errorOf(response));
    } catch (e) {
      return (user: null, error: 'Network error: $e');
    }
  }

  // ─── delete account ──────────────────────────────────────────────────

  /// DELETE /api/me/account — soft-deletes the row (anonymized).
  ///
  /// Password is required for password-auth accounts; OAuth-only
  /// accounts can pass an empty string. The `confirm` field must be
  /// the literal string "DELETE" — this is a server-side guard against
  /// accidental triggers. The Flutter screen prompts the user to type
  /// it in.
  static Future<({String? error})> deleteAccount({
    required String password,
    required String confirm,
  }) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$_base/me/account'),
            headers: await _authHeaders(),
            body: json.encode({
              'password': password,
              'confirm': confirm,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return (error: null);
      return (error: _errorOf(response));
    } catch (e) {
      return (error: 'Network error: $e');
    }
  }

  // ─── helpers ─────────────────────────────────────────────────────────

  static Map<String, dynamic> _safeDecode(String s) {
    try {
      final v = json.decode(s);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return {};
  }

  static String _errorOf(http.Response response) {
    final body = _safeDecode(response.body);
    return body['error']?.toString() ?? 'Request failed (${response.statusCode}).';
  }
}
