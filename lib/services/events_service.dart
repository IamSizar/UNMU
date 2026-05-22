import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';

/// Best-effort engagement / reliability event logging. Mirrors the
/// `post_events` table on the backend.
///
/// Three principles for everything in here:
///
///   1. **Never throw.** A logging hiccup must never break the user
///      flow that triggered it. Every method swallows network errors.
///   2. **Fire and forget.** Returns `void` — call sites don't await
///      anything actionable. The `Future` exists only so we can use
///      `await` internally.
///   3. **Auth-only.** Uses the current bearer token. If there's no
///      token, the call is dropped (anonymous events aren't tracked
///      from this surface — the server-side `deep_link_opened` event
///      catches anonymous deep-link taps via GET /api/posts/:id).
class EventsService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Tell the server that the user just tapped the Share button on a
  /// post. Drives the admin dashboard's "shares in last 24h" card
  /// + per-post share count.
  static Future<void> logShare(int postId) async {
    try {
      await http
          .post(
            Uri.parse('$_base/posts/$postId/share-event'),
            headers: await _authHeaders(),
            body: json.encode({
              'platform': Platform.isIOS ? 'ios' : 'android',
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Logging failed — that's fine. Share UX already happened.
    }
  }

  /// Tell the server that this reel's video controller failed to
  /// initialise. Drives the admin "reels failing to load" trend so
  /// the team knows when a CDN / codec regression breaks playback at
  /// scale.
  ///
  /// [errorKind] is an optional free-form tag — `timeout`, `codec`,
  /// `network`, `unknown`. Don't put PII in here.
  static Future<void> logReelLoadFailed({
    required int postId,
    String errorKind = 'unknown',
  }) async {
    try {
      await http
          .post(
            Uri.parse('$_base/me/events/reel-load-failed'),
            headers: await _authHeaders(),
            body: json.encode({
              'postId': postId,
              'errorKind': errorKind,
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Same as logShare — never escalate logging failures.
    }
  }
}
