import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import '../models/expert_post.dart';
import 'auth_service.dart';

/// Network calls for the expert "studio" — list own posts, create a new one.
class ExpertPostService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/me/expert/posts — every post by the authed expert.
  ///
  /// Optional [type] filters by article / video / reel.
  static Future<List<ExpertPost>> myPosts({PostType? type}) async {
    try {
      final qs = type != null ? '?type=${type.wireValue}' : '';
      final response = await http.get(
        Uri.parse('$_base/me/expert/posts$qs'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return const [];
      }
      if (response.statusCode != 200) return const [];
      final body = json.decode(response.body) as Map<String, dynamic>;
      final posts = (body['posts'] as List<dynamic>? ?? [])
          .map((e) => ExpertPost.fromJson(e as Map<String, dynamic>))
          .toList();
      return posts;
    } catch (_) {
      return const [];
    }
  }

  /// GET /api/posts/:id — single-post fetch used by deep-link route
  /// resolution. The backend applies the same per-post visibility gate
  /// as the expert-profile listing (subscribers-only posts arrive locked
  /// to non-subscribers; hidden posts return 404).
  ///
  /// Returns:
  ///   * the post on a 200,
  ///   * `null` if the post doesn't exist (404),
  ///   * `null` on a network / server error so the UI can render a
  ///     "couldn't load" state.
  static Future<ExpertPost?> getById(int id) async {
    try {
      final response = await http.get(
        Uri.parse('$_base/posts/$id'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return null;
      }
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body) as Map<String, dynamic>;
      final raw = body['post'];
      if (raw is! Map<String, dynamic>) return null;
      return ExpertPost.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  /// GET /api/experts/:expertId/posts — every post on this expert's profile.
  ///
  /// The backend returns all posts but blanks out body / media / tickers
  /// for non-subscribers on subscriber-only rows (those rows arrive with
  /// `isLocked: true`). Also returns a `subscribed` flag the UI can use to
  /// switch between "Subscribe to view" CTAs and full content.
  ///
  /// Returns **null** when the request itself fails (network error, server
  /// 5xx, 4xx that isn't auth-related). Callers can use that to decide
  /// whether to show a mock fallback for unseeded demo experts vs. a clean
  /// "no posts yet" empty state for real experts who happen to have hidden
  /// or deleted everything.
  static Future<({List<ExpertPost> posts, bool subscribed})?> listForExpert(
      String expertId) async {
    try {
      final response = await http.get(
        Uri.parse('$_base/experts/$expertId/posts'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return null;
      }
      if (response.statusCode != 200) {
        return null;
      }
      final body = json.decode(response.body) as Map<String, dynamic>;
      final posts = (body['posts'] as List<dynamic>? ?? [])
          .map((e) => ExpertPost.fromJson(e as Map<String, dynamic>))
          .toList();
      final subscribed = body['subscribed'] as bool? ?? false;
      return (posts: posts, subscribed: subscribed);
    } catch (_) {
      return null;
    }
  }

  /// POST /api/experts/:expertId/posts — publish a new post on the expert's
  /// own profile. Returns null + an error message on failure.
  static Future<({ExpertPost? post, String? error})> create({
    required String expertId,
    required PostType type,
    required PostVisibility visibility,
    String? title,
    String body = '',
    String? mediaUrl,
    String? coverUrl,
    int? durationSeconds,
    List<String> tickers = const [],
  }) async {
    try {
      final payload = <String, dynamic>{
        'postType': type.wireValue,
        'visibility': visibility.wireValue,
        if (title != null && title.isNotEmpty) 'title': title,
        'body': body,
        if (mediaUrl != null && mediaUrl.isNotEmpty) 'mediaUrl': mediaUrl,
        if (coverUrl != null && coverUrl.isNotEmpty) 'coverUrl': coverUrl,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        'tickers': tickers,
      };
      final response = await http.post(
        Uri.parse('$_base/experts/$expertId/posts'),
        headers: await _authHeaders(),
        body: json.encode(payload),
      );
      if (response.statusCode == 201) {
        return (
          post: ExpertPost.fromJson(
            json.decode(response.body) as Map<String, dynamic>,
          ),
          error: null,
        );
      }
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (post: null, error: 'Session expired — please sign in again.');
      }
      final errBody = _safeDecode(response.body);
      return (
        post: null,
        error: errBody['error']?.toString() ?? 'Publish failed',
      );
    } catch (e) {
      return (post: null, error: 'Connection error: $e');
    }
  }

  /// POST /api/communities/:communityId/posts — publish into a
  /// community. Sibling of [create] for the multi-destination
  /// composer: when an expert wants to share the same article (or
  /// video, or reel) into her profile AND one or more communities,
  /// the composer fans out to [create] (once for the profile) plus
  /// this method (once per community).
  ///
  /// The community endpoint now accepts the same body shape as the
  /// expert endpoint — articles, videos, AND reels are supported.
  /// `ticker` (singular) is required for legacy reasons (the
  /// stocks-discovery query still keys off the primary symbol);
  /// pass the first item of [tickers] there. `stance` defaults
  /// to HOLD when the post type isn't an article.
  ///
  /// Server-side gates ensure the caller is an expert who joined
  /// the community.
  static Future<({String? error})> createCommunityPost({
    required String communityId,
    required PostType type,
    required PostVisibility visibility,
    required String title,
    required String body,
    required String ticker,
    required String stance, // 'BUY' | 'HOLD' | 'SELL'
    String? mediaUrl,
    String? coverUrl,
    int? durationSeconds,
    List<String> tickers = const [],
  }) async {
    try {
      final payload = <String, dynamic>{
        'title': title,
        'body': body,
        'ticker': ticker,
        'stance': stance,
        'postType': type.wireValue,
        'visibility': visibility.wireValue,
        if (mediaUrl != null && mediaUrl.isNotEmpty) 'mediaUrl': mediaUrl,
        if (coverUrl != null && coverUrl.isNotEmpty) 'coverUrl': coverUrl,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        'tickers': tickers,
      };
      final response = await http.post(
        Uri.parse('$_base/communities/$communityId/posts'),
        headers: await _authHeaders(),
        body: json.encode(payload),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return (error: null);
      }
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (error: 'Session expired — please sign in again.');
      }
      final errBody = _safeDecode(response.body);
      return (
        error: errBody['error']?.toString() ?? 'Publish failed ($communityId)',
      );
    } catch (e) {
      return (error: 'Connection error ($communityId): $e');
    }
  }

  /// PATCH /api/experts/:expertId/posts/:postId — partial update.
  ///
  /// Pass only the fields you want to change. Returns the updated post on
  /// success, or null + an error message on failure.
  static Future<({ExpertPost? post, String? error})> update({
    required String expertId,
    required int postId,
    String? title,
    String? body,
    String? mediaUrl,
    String? coverUrl,
    int? durationSeconds,
    PostVisibility? visibility,
    List<String>? tickers,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (title != null) payload['title'] = title;
      if (body != null) payload['body'] = body;
      if (mediaUrl != null) payload['mediaUrl'] = mediaUrl;
      if (coverUrl != null) payload['coverUrl'] = coverUrl;
      if (durationSeconds != null) payload['durationSeconds'] = durationSeconds;
      if (visibility != null) payload['visibility'] = visibility.wireValue;
      if (tickers != null) payload['tickers'] = tickers;

      final response = await http.patch(
        Uri.parse('$_base/experts/$expertId/posts/$postId'),
        headers: await _authHeaders(),
        body: json.encode(payload),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (post: null, error: 'Session expired — please sign in again.');
      }
      if (response.statusCode == 200) {
        return (
          post: ExpertPost.fromJson(
            json.decode(response.body) as Map<String, dynamic>,
          ),
          error: null,
        );
      }
      final errBody = _safeDecode(response.body);
      return (
        post: null,
        error: errBody['error']?.toString() ?? 'Update failed',
      );
    } catch (e) {
      return (post: null, error: 'Connection error: $e');
    }
  }

  /// PATCH /api/experts/:expertId/posts/:postId/visibility — flip is_hidden.
  ///
  /// When hidden=true, the post disappears from non-owner profile views;
  /// the owner still sees it in their studio with a "Hidden" badge so they
  /// can un-hide later.
  static Future<({ExpertPost? post, String? error})> setHidden({
    required String expertId,
    required int postId,
    required bool hidden,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$_base/experts/$expertId/posts/$postId/visibility'),
        headers: await _authHeaders(),
        body: json.encode({'hidden': hidden}),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (post: null, error: 'Session expired — please sign in again.');
      }
      if (response.statusCode == 200) {
        return (
          post: ExpertPost.fromJson(
            json.decode(response.body) as Map<String, dynamic>,
          ),
          error: null,
        );
      }
      final errBody = _safeDecode(response.body);
      return (
        post: null,
        error: errBody['error']?.toString() ??
            (hidden ? 'Hide failed' : 'Unhide failed'),
      );
    } catch (e) {
      return (post: null, error: 'Connection error: $e');
    }
  }

  /// DELETE /api/experts/:expertId/posts/:postId — permanent removal.
  /// Returns null on success, or an error string on failure.
  static Future<String?> delete({
    required String expertId,
    required int postId,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('$_base/experts/$expertId/posts/$postId'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return 'Session expired — please sign in again.';
      }
      if (response.statusCode == 200) return null;
      final errBody = _safeDecode(response.body);
      return errBody['error']?.toString() ?? 'Delete failed';
    } catch (e) {
      return 'Connection error: $e';
    }
  }

  // ──────────────────────────────────────────────────────────
  // Step-20 (mig 0020) — drafts, version history, attachments
  // ──────────────────────────────────────────────────────────

  /// POST /api/me/expert/drafts — save a new draft.
  /// Same body shape as create() but the row is saved with
  /// status='draft'. Required-field validation is deferred to the
  /// publish call.
  static Future<({ExpertPost? post, String? error})> saveDraft({
    required PostType postType,
    String? title,
    String? body,
    String? mediaUrl,
    String? coverUrl,
    int? durationSeconds,
    PostVisibility visibility = PostVisibility.subscribersOnly,
    List<String> tickers = const [],
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/me/expert/drafts'),
        headers: await _authHeaders(),
        body: json.encode({
          'postType': postType.wireValue,
          if (title != null) 'title': title,
          if (body != null) 'body': body,
          if (mediaUrl != null) 'mediaUrl': mediaUrl,
          if (coverUrl != null) 'coverUrl': coverUrl,
          if (durationSeconds != null) 'durationSeconds': durationSeconds,
          'visibility': visibility.wireValue,
          'tickers': tickers,
        }),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (post: null, error: 'Session expired.');
      }
      if (res.statusCode != 201) {
        return (
          post: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Save failed (${res.statusCode}).'
        );
      }
      return (
        post: ExpertPost.fromJson(
          json.decode(res.body) as Map<String, dynamic>,
        ),
        error: null,
      );
    } catch (e) {
      return (post: null, error: 'Connection error: $e');
    }
  }

  /// PATCH /api/me/expert/drafts/:id — partial update on a draft.
  /// Server rejects with 409 if the row is already published.
  static Future<({ExpertPost? post, String? error})> updateDraft({
    required int draftId,
    String? title,
    String? body,
    String? mediaUrl,
    String? coverUrl,
    int? durationSeconds,
    PostVisibility? visibility,
    List<String>? tickers,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (title != null) payload['title'] = title;
      if (body != null) payload['body'] = body;
      if (mediaUrl != null) payload['mediaUrl'] = mediaUrl;
      if (coverUrl != null) payload['coverUrl'] = coverUrl;
      if (durationSeconds != null) {
        payload['durationSeconds'] = durationSeconds;
      }
      if (visibility != null) payload['visibility'] = visibility.wireValue;
      if (tickers != null) payload['tickers'] = tickers;
      final res = await http.patch(
        Uri.parse('$_base/me/expert/drafts/$draftId'),
        headers: await _authHeaders(),
        body: json.encode(payload),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (post: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        return (
          post: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Update failed (${res.statusCode}).'
        );
      }
      return (
        post: ExpertPost.fromJson(
          json.decode(res.body) as Map<String, dynamic>,
        ),
        error: null,
      );
    } catch (e) {
      return (post: null, error: 'Connection error: $e');
    }
  }

  /// POST /api/me/expert/drafts/:id/publish
  ///
  /// When [publishAt] is null the draft publishes immediately. When
  /// non-null it must be at least 5 minutes in the future — server
  /// returns 400 otherwise.
  static Future<({ExpertPost? post, String? error})> publishDraft({
    required int draftId,
    DateTime? publishAt,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (publishAt != null) {
        body['publishAt'] = publishAt.toUtc().toIso8601String();
      }
      final res = await http.post(
        Uri.parse('$_base/me/expert/drafts/$draftId/publish'),
        headers: await _authHeaders(),
        body: json.encode(body),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (post: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        return (
          post: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Publish failed (${res.statusCode}).'
        );
      }
      return (
        post: ExpertPost.fromJson(
          json.decode(res.body) as Map<String, dynamic>,
        ),
        error: null,
      );
    } catch (e) {
      return (post: null, error: 'Connection error: $e');
    }
  }

  /// GET /api/me/expert/drafts — every draft + scheduled row authored
  /// by the caller.
  static Future<({List<ExpertPost>? drafts, String? error})>
      listDrafts() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/me/expert/drafts'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (drafts: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        return (
          drafts: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Load failed (${res.statusCode}).'
        );
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = (body['posts'] as List<dynamic>? ?? [])
          .map((e) => ExpertPost.fromJson(e as Map<String, dynamic>))
          .toList();
      return (drafts: list, error: null);
    } catch (e) {
      return (drafts: null, error: 'Connection error: $e');
    }
  }

  /// DELETE /api/me/expert/drafts/:id — permanent.
  static Future<String?> deleteDraft(int draftId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_base/me/expert/drafts/$draftId'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return 'Session expired.';
      }
      if (res.statusCode == 200) return null;
      return _safeDecode(res.body)['error']?.toString() ??
          'Delete failed (${res.statusCode}).';
    } catch (e) {
      return 'Connection error: $e';
    }
  }

  /// GET /api/posts/:id/history — every snapshot in post_versions for
  /// this post, newest-first. Owner + admin only (403 otherwise).
  static Future<({List<PostVersion>? versions, String? error})> listHistory(
    int postId,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/posts/$postId/history'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (versions: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        return (
          versions: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Load failed (${res.statusCode}).'
        );
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = (body['versions'] as List<dynamic>? ?? [])
          .map((e) => PostVersion.fromJson(e as Map<String, dynamic>))
          .toList();
      return (versions: list, error: null);
    } catch (e) {
      return (versions: null, error: 'Connection error: $e');
    }
  }

  /// POST /api/me/posts/:id/attachments
  ///
  /// [url] should be the `/uploads/images/...` path returned by
  /// UploadService.uploadImage. Server caps at 5 attachments per
  /// post — 6th call returns 409.
  static Future<({PostAttachment? attachment, String? error})>
      addAttachment({
    required int postId,
    required String url,
    int sortOrder = 0,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/me/posts/$postId/attachments'),
        headers: await _authHeaders(),
        body: json.encode({'url': url, 'sortOrder': sortOrder}),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (attachment: null, error: 'Session expired.');
      }
      if (res.statusCode != 201) {
        return (
          attachment: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Attach failed (${res.statusCode}).'
        );
      }
      return (
        attachment: PostAttachment.fromJson(
          json.decode(res.body) as Map<String, dynamic>,
        ),
        error: null,
      );
    } catch (e) {
      return (attachment: null, error: 'Connection error: $e');
    }
  }

  /// DELETE /api/me/posts/:postId/attachments/:attachmentId
  static Future<String?> deleteAttachment({
    required int postId,
    required int attachmentId,
  }) async {
    try {
      final res = await http.delete(
        Uri.parse('$_base/me/posts/$postId/attachments/$attachmentId'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return 'Session expired.';
      }
      if (res.statusCode == 200) return null;
      return _safeDecode(res.body)['error']?.toString() ??
          'Delete failed (${res.statusCode}).';
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
