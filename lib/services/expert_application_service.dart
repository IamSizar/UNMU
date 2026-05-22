import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import '../models/expert_application.dart';
import 'auth_service.dart';

/// Network calls for the "become an expert" flow (Step 1).
///
/// All endpoints require a valid JWT — we read it from [AuthService.getToken].
class ExpertApplicationService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Submit a new application for the current user.
  ///
  /// Returns the created application on success, or an error message on
  /// failure (validation, already pending, cool-down, server error).
  ///
  /// `retryAfterSeconds` is non-null when the server returns 429 — the
  /// caller can show a "you can re-apply on (date)" copy.
  static Future<
      ({
        ExpertApplication? app,
        String? error,
        int? retryAfterSeconds,
      })> submit({
    required String fullName,
    required String expertise,
    required String bio,
    List<String> credentials = const [],
    String? country,
    List<String> sampleLinks = const [],
    String? resumeUrl,
    String? avatarUrl,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_base/expert-applications'),
        headers: await _authHeaders(),
        body: json.encode({
          'fullName': fullName,
          'expertise': expertise,
          'bio': bio,
          'credentials': credentials,
          if (country != null && country.isNotEmpty) 'country': country,
          'sampleLinks': sampleLinks,
          if (resumeUrl != null && resumeUrl.isNotEmpty) 'resumeUrl': resumeUrl,
          if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
        }),
      );
      if (response.statusCode == 201) {
        return (
          app: ExpertApplication.fromJson(
            json.decode(response.body) as Map<String, dynamic>,
          ),
          error: null,
          retryAfterSeconds: null,
        );
      }
      if (response.statusCode == 401) {
        // Stale token — kick the user back to login.
        await Get.find<AuthController>().handleAuthFailure();
        return (
          app: null,
          error: 'Session expired — please sign in again.',
          retryAfterSeconds: null,
        );
      }
      final body = _safeDecode(response.body);
      // Cool-down (HTTP 429) — pass the seconds back to the caller so
      // it can render a localized "available on …" message.
      int? retryAfter;
      if (response.statusCode == 429) {
        final v = body['retryAfterSeconds'];
        if (v is num) retryAfter = v.toInt();
      }
      return (
        app: null,
        error: body['error']?.toString() ?? 'Submit failed',
        retryAfterSeconds: retryAfter,
      );
    } catch (e) {
      return (app: null, error: 'Connection error: $e', retryAfterSeconds: null);
    }
  }

  /// Withdraw the user's own pending application (A9). Returns true on
  /// success; on failure the error string explains why.
  static Future<({bool ok, String? error})> withdraw(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$_base/me/expert-applications/$id'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 200) return (ok: true, error: null);
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (ok: false, error: 'Session expired — please sign in again.');
      }
      final body = _safeDecode(response.body);
      return (ok: false, error: body['error']?.toString() ?? 'Withdraw failed');
    } catch (e) {
      return (ok: false, error: 'Connection error: $e');
    }
  }

  /// Get the current user's most recent application — or null if they've
  /// never applied. The server returns `{ "status": "none" }` for that case.
  static Future<ExpertApplication?> myApplication() async {
    try {
      final response = await http.get(
        Uri.parse('$_base/me/expert-application'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return null;
      }
      if (response.statusCode != 200) return null;

      final body = json.decode(response.body) as Map<String, dynamic>;
      if (body['status'] == 'none' || body['id'] == null) return null;
      return ExpertApplication.fromJson(body);
    } catch (_) {
      return null;
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
