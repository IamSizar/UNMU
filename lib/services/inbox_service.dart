import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import '../models/inbox_item.dart';
import 'auth_service.dart';

/// Network surface for the unified notification inbox.
///
/// Backed by `GET /api/me/inbox` which merges the two backend
/// notification tables. The mobile inbox screen calls these
/// methods directly; the legacy per-table services
/// (UserNotificationsService, NotificationsController for stock)
/// stay around for now but the bell icon + screen route through
/// here.
class InboxService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/me/inbox — merged inbox newest-first.
  ///
  /// [cursor] is the oldest currently-loaded item's `createdAt` —
  /// pass it for the next page. [unreadOnly] flips the server-side
  /// filter so already-read rows are excluded. Server caps `limit`
  /// to 200; default 50.
  ///
  /// Returns the list AND the unified unread count so callers can
  /// update both their list and their bell badge in one round-trip.
  static Future<({List<InboxItem>? items, int unreadCount, String? error})>
      list({
    DateTime? cursor,
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    try {
      final params = <String, String>{'limit': '$limit'};
      if (cursor != null) {
        params['cursor'] = cursor.toUtc().toIso8601String();
      }
      if (unreadOnly) params['filter'] = 'unread';
      final qs = Uri(queryParameters: params).query;
      final url =
          qs.isEmpty ? '$_base/me/inbox' : '$_base/me/inbox?$qs';
      final res = await http.get(
        Uri.parse(url),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (items: null, unreadCount: 0, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        final err = _safeDecode(res.body)['error']?.toString() ??
            'Failed (${res.statusCode}).';
        return (items: null, unreadCount: 0, error: err);
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = (body['items'] as List<dynamic>? ?? [])
          .map((e) => InboxItem.fromJson(e as Map<String, dynamic>))
          .toList();
      final unread = (body['unreadCount'] as num?)?.toInt() ?? 0;
      return (items: list, unreadCount: unread, error: null);
    } catch (e) {
      return (items: null, unreadCount: 0, error: 'Connection error: $e');
    }
  }

  /// GET /api/me/inbox/unread-count — cheap badge probe.
  static Future<int> unreadCount() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/me/inbox/unread-count'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) return 0;
      final body = json.decode(res.body) as Map<String, dynamic>;
      return (body['unreadCount'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// POST /api/me/inbox/:source/:id/read — mark one row read.
  /// Idempotent — calling on an already-read row returns 200.
  static Future<bool> markRead(String source, int id) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/me/inbox/$source/$id/read'),
        headers: await _authHeaders(),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// POST /api/me/inbox/read-all — flips every unread row across
  /// both backend tables.
  static Future<bool> markAllRead() async {
    try {
      final res = await http.post(
        Uri.parse('$_base/me/inbox/read-all'),
        headers: await _authHeaders(),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
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
