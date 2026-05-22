import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import '../models/user_notification.dart';
import 'auth_service.dart';

/// Notifications inbox HTTP layer — used by NotificationsController.
class NotificationService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/me/notifications — newest first.
  static Future<List<UserNotification>?> list({int limit = 50}) async {
    try {
      final response = await http.get(
        Uri.parse('$_base/me/notifications?limit=$limit'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return null;
      }
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      return (body['notifications'] as List<dynamic>? ?? [])
          .map((e) => UserNotification.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// GET /api/me/notifications/unread-count — drives the bell red dot.
  static Future<int?> unreadCount() async {
    try {
      final response = await http.get(
        Uri.parse('$_base/me/notifications/unread-count'),
        headers: await _authHeaders(),
      );
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      return (body['count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> markAllRead() async {
    try {
      final response = await http.post(
        Uri.parse('$_base/me/notifications/read-all'),
        headers: await _authHeaders(),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> markRead(int id) async {
    try {
      final response = await http.post(
        Uri.parse('$_base/me/notifications/$id/read'),
        headers: await _authHeaders(),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
