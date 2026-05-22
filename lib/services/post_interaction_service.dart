import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import '../models/liker.dart';
import '../models/post_comment.dart';
import 'auth_service.dart';

/// HTTP wrapper for the like + comment endpoints on a post.
///
/// Every method returns a result record so the UI can distinguish "user is
/// signed out" vs "request failed" vs "all good".
class PostInteractionService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// POST /api/posts/:id/like — returns the new like count on success.
  /// Returns null when the request fails so the UI can revert the
  /// optimistic toggle.
  static Future<int?> like(int postId) async {
    try {
      final response = await http.post(
        Uri.parse('$_base/posts/$postId/like'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return null;
      }
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      return (body['likes'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// DELETE /api/posts/:id/like — same shape as [like].
  static Future<int?> unlike(int postId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_base/posts/$postId/like'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return null;
      }
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      return (body['likes'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// GET /api/posts/:id/likes — owner / admin only. Returns the users
  /// who liked the post (newest-first). Returns null on any non-200.
  static Future<List<Liker>?> listLikers(int postId, {int limit = 100}) async {
    try {
      final response = await http.get(
        Uri.parse('$_base/posts/$postId/likes?limit=$limit'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return null;
      }
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      return (body['likers'] as List<dynamic>? ?? [])
          .map((e) => Liker.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// GET /api/posts/:id/comments
  static Future<List<PostComment>?> listComments(int postId,
      {int limit = 50}) async {
    try {
      final response = await http.get(
        Uri.parse('$_base/posts/$postId/comments?limit=$limit'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return null;
      }
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      final list = (body['comments'] as List<dynamic>? ?? [])
          .map((e) => PostComment.fromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    } catch (_) {
      return null;
    }
  }

  /// POST /api/posts/:id/comments — body { body }
  static Future<({PostComment? comment, String? error})> addComment(
    int postId,
    String body,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_base/posts/$postId/comments'),
        headers: await _authHeaders(),
        body: json.encode({'body': body}),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (comment: null, error: 'Session expired — please sign in.');
      }
      if (response.statusCode == 201) {
        return (
          comment: PostComment.fromJson(
            json.decode(response.body) as Map<String, dynamic>,
          ),
          error: null,
        );
      }
      final err = _safeDecode(response.body)['error']?.toString() ??
          'Comment failed.';
      return (comment: null, error: err);
    } catch (e) {
      return (comment: null, error: 'Connection error: $e');
    }
  }

  /// PATCH /api/posts/:postId/comments/:commentId — body { body }
  ///
  /// Returns the updated PostComment (with edited_at set) on success.
  /// Only the comment's author can edit; the backend returns 403 otherwise.
  static Future<({PostComment? comment, String? error})> editComment(
    int postId,
    int commentId,
    String body,
  ) async {
    try {
      final response = await http.patch(
        Uri.parse('$_base/posts/$postId/comments/$commentId'),
        headers: await _authHeaders(),
        body: json.encode({'body': body}),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (comment: null, error: 'Session expired — please sign in.');
      }
      if (response.statusCode == 200) {
        return (
          comment: PostComment.fromJson(
            json.decode(response.body) as Map<String, dynamic>,
          ),
          error: null,
        );
      }
      final err = _safeDecode(response.body)['error']?.toString() ??
          'Edit failed.';
      return (comment: null, error: err);
    } catch (e) {
      return (comment: null, error: 'Connection error: $e');
    }
  }

  /// DELETE /api/posts/:postId/comments/:commentId
  static Future<String?> deleteComment(int postId, int commentId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_base/posts/$postId/comments/$commentId'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return 'Session expired — please sign in.';
      }
      if (response.statusCode == 200) return null;
      return _safeDecode(response.body)['error']?.toString() ??
          'Delete failed.';
    } catch (e) {
      return 'Connection error: $e';
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
