import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import '../models/expert_post.dart';
import 'auth_service.dart';

/// Wrapper around the bookmark endpoints. Save / unsave a post and list
/// the user's saved posts.
///
/// Returns null on transport failure so the controller can revert the
/// optimistic toggle. A null return for the list means "couldn't reach
/// backend" — distinct from an empty list, which is "no saves yet".
class SaveService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// POST /api/posts/:id/save  — returns true on success.
  static Future<bool> save(int postId) async {
    try {
      final response = await http.post(
        Uri.parse('$_base/posts/$postId/save'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return false;
      }
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// DELETE /api/posts/:id/save  — returns true on success.
  static Future<bool> unsave(int postId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_base/posts/$postId/save'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return false;
      }
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// GET /api/me/saved-posts — newest-saved first.
  static Future<List<ExpertPost>?> list({int limit = 50}) async {
    try {
      final response = await http.get(
        Uri.parse('$_base/me/saved-posts?limit=$limit'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return null;
      }
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      return (body['posts'] as List<dynamic>? ?? [])
          .map((e) => ExpertPost.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }
}
