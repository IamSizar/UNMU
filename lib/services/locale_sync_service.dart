import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'auth_service.dart';

/// Pushes the user's chosen UI language to the backend (PATCH /me/locale)
/// so notification pushes can be rendered in that language. The choice
/// otherwise lives only on-device (LanguageController + SharedPreferences).
///
/// Fire-and-forget: no-op when the user isn't logged in, and any error is
/// swallowed — failing to sync the locale must never block the language
/// toggle or the login flow. The next toggle / login retries.
class LocaleSyncService {
  static String get _base => ApiConfig.baseUrl;

  /// Best-effort sync. Safe to call when signed out (skips silently).
  static Future<void> sync(String languageCode) async {
    final code = languageCode.toLowerCase();
    if (code != 'en' && code != 'ar') return;

    final token = await AuthService.getToken();
    if (token == null) return; // not logged in — nothing to sync yet

    try {
      await http
          .patch(
            Uri.parse('$_base/me/locale'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({'locale': code}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Intentionally ignored — see class doc.
    }
  }

  /// Sync whatever language is currently saved on the device. Call after
  /// login so a returning user who already chose Arabic gets re-synced
  /// even if they don't touch the toggle this session.
  static Future<void> syncSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await sync(prefs.getString('language') ?? 'en');
  }
}
