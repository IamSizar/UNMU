import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';

/// Mirror of backend `repositories.NotificationPrefs` (mig 0041).
class NotificationPrefs {
  final bool pushEnabled;
  final bool emailEnabled;
  final bool likesEnabled;
  final bool commentsEnabled;
  final bool subscriptionsEnabled;
  final bool communitiesEnabled;
  final bool marketingEnabled;

  const NotificationPrefs({
    required this.pushEnabled,
    required this.emailEnabled,
    required this.likesEnabled,
    required this.commentsEnabled,
    required this.subscriptionsEnabled,
    required this.communitiesEnabled,
    required this.marketingEnabled,
  });

  /// Backend defaults — used as the on-screen starting state while the
  /// initial GET is in flight. Matches mig 0041's column defaults.
  factory NotificationPrefs.initial() => const NotificationPrefs(
        pushEnabled: true,
        emailEnabled: true,
        likesEnabled: true,
        commentsEnabled: true,
        subscriptionsEnabled: true,
        communitiesEnabled: true,
        marketingEnabled: false,
      );

  factory NotificationPrefs.fromJson(Map<String, dynamic> json) =>
      NotificationPrefs(
        pushEnabled: json['pushEnabled'] as bool? ?? true,
        emailEnabled: json['emailEnabled'] as bool? ?? true,
        likesEnabled: json['likesEnabled'] as bool? ?? true,
        commentsEnabled: json['commentsEnabled'] as bool? ?? true,
        subscriptionsEnabled: json['subscriptionsEnabled'] as bool? ?? true,
        communitiesEnabled: json['communitiesEnabled'] as bool? ?? true,
        marketingEnabled: json['marketingEnabled'] as bool? ?? false,
      );

  NotificationPrefs copyWith({
    bool? pushEnabled,
    bool? emailEnabled,
    bool? likesEnabled,
    bool? commentsEnabled,
    bool? subscriptionsEnabled,
    bool? communitiesEnabled,
    bool? marketingEnabled,
  }) =>
      NotificationPrefs(
        pushEnabled: pushEnabled ?? this.pushEnabled,
        emailEnabled: emailEnabled ?? this.emailEnabled,
        likesEnabled: likesEnabled ?? this.likesEnabled,
        commentsEnabled: commentsEnabled ?? this.commentsEnabled,
        subscriptionsEnabled: subscriptionsEnabled ?? this.subscriptionsEnabled,
        communitiesEnabled: communitiesEnabled ?? this.communitiesEnabled,
        marketingEnabled: marketingEnabled ?? this.marketingEnabled,
      );
}

class NotificationPrefsService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/me/notification-prefs — fetches the user's row (creates
  /// a defaults row server-side if missing). On any error returns the
  /// defaults so the settings screen still renders something usable.
  static Future<({NotificationPrefs prefs, String? error})> get() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/me/notification-prefs'),
              headers: await _authHeaders())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        return (prefs: NotificationPrefs.fromJson(body), error: null);
      }
      return (
        prefs: NotificationPrefs.initial(),
        error: _errorOf(res),
      );
    } catch (e) {
      return (
        prefs: NotificationPrefs.initial(),
        error: 'Network error: $e',
      );
    }
  }

  /// PATCH /api/me/notification-prefs — partial update. Returns the
  /// refreshed prefs on success so the UI can swap in the canonical
  /// server state (in case of a race with another device).
  static Future<({NotificationPrefs? prefs, String? error})> update({
    bool? pushEnabled,
    bool? emailEnabled,
    bool? likesEnabled,
    bool? commentsEnabled,
    bool? subscriptionsEnabled,
    bool? communitiesEnabled,
    bool? marketingEnabled,
  }) async {
    final body = <String, dynamic>{};
    if (pushEnabled != null) body['pushEnabled'] = pushEnabled;
    if (emailEnabled != null) body['emailEnabled'] = emailEnabled;
    if (likesEnabled != null) body['likesEnabled'] = likesEnabled;
    if (commentsEnabled != null) body['commentsEnabled'] = commentsEnabled;
    if (subscriptionsEnabled != null) {
      body['subscriptionsEnabled'] = subscriptionsEnabled;
    }
    if (communitiesEnabled != null) {
      body['communitiesEnabled'] = communitiesEnabled;
    }
    if (marketingEnabled != null) body['marketingEnabled'] = marketingEnabled;

    try {
      final res = await http
          .patch(
            Uri.parse('$_base/me/notification-prefs'),
            headers: await _authHeaders(),
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        return (prefs: NotificationPrefs.fromJson(body), error: null);
      }
      return (prefs: null, error: _errorOf(res));
    } catch (e) {
      return (prefs: null, error: 'Network error: $e');
    }
  }

  static String _errorOf(http.Response response) {
    try {
      final v = json.decode(response.body);
      if (v is Map<String, dynamic> && v['error'] != null) {
        return v['error'].toString();
      }
    } catch (_) {}
    return 'Request failed (${response.statusCode}).';
  }
}
