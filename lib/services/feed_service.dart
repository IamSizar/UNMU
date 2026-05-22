import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import '../models/expert_post.dart';
import 'auth_service.dart';

/// Network call for the bottom-nav Feed tab — every post from every
/// expert the authenticated user has an active subscription to.
class FeedService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/me/feed — latest posts from active subscriptions, newest first.
  ///
  /// Optional [type] filter narrows to one post type (article / video / reel).
  ///
  /// Optional [before] is a keyset pagination cursor — pass the oldest
  /// currently-loaded post's `createdAt` to fetch the next page. The
  /// backend returns posts strictly older than this timestamp.
  ///
  /// Returns **null** on a real network / server error so the UI can keep
  /// any cached posts and show a small error banner — vs a successful 200
  /// with an empty list (user has no active subs yet) which the UI renders
  /// as a "subscribe to see posts" empty state.
  static Future<List<ExpertPost>?> myFeed({
    PostType? type,
    DateTime? before,
    int limit = 50,
  }) async {
    try {
      final params = <String, String>{
        'limit': '$limit',
        if (type != null) 'type': type.wireValue,
        if (before != null) 'before': before.toUtc().toIso8601String(),
      };
      final qs = Uri(queryParameters: params).query;
      final url = qs.isEmpty ? '$_base/me/feed' : '$_base/me/feed?$qs';
      final response = await http.get(
        Uri.parse(url),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return null;
      }
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      final posts = (body['posts'] as List<dynamic>? ?? [])
          .map((e) => ExpertPost.fromJson(e as Map<String, dynamic>))
          .toList();
      return posts;
    } catch (_) {
      return null;
    }
  }
}
