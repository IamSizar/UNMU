import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';

/// User-facing API for abuse reports.
///
/// Pair with a Material bottom-sheet that:
///   1. Lets the user pick a reason from [reasons]
///   2. Optionally adds a free-text note
///   3. Calls [ReportService.submit] with the targetType + targetId
class ReportService {
  static String get _base => ApiConfig.baseUrl;

  /// What the user is reporting. Mirrors the backend `allowedTargetTypes`
  /// — keep in sync if you add another option there.
  static const Set<String> targetTypes = {
    'post',
    'user',
    'comment',
    'community',
    'message',
  };

  /// Reason codes the backend accepts. Mirrored from
  /// handlers/reports.go::allowedReasons. The displayed label for each
  /// code is up to the UI layer — see [reasonLabel].
  static const List<String> reasons = [
    'spam',
    'harassment',
    'hate_speech',
    'violence',
    'sexual_content',
    'financial_scam',
    'impersonation',
    'misinformation',
    'copyright',
    'underage',
    'self_harm',
    'shariah_concern',
    'other',
  ];

  /// Human-friendly label for a reason code. Default English; localized
  /// strings can replace this from AppLocalizations later.
  static String reasonLabel(String code) {
    switch (code) {
      case 'spam':
        return 'Spam or repetitive content';
      case 'harassment':
        return 'Harassment or bullying';
      case 'hate_speech':
        return 'Hate speech';
      case 'violence':
        return 'Violence or threats';
      case 'sexual_content':
        return 'Sexual or adult content';
      case 'financial_scam':
        return 'Financial scam / fraud';
      case 'impersonation':
        return 'Impersonation';
      case 'misinformation':
        return 'Misleading information';
      case 'copyright':
        return 'Copyright violation';
      case 'underage':
        return 'Underage user';
      case 'self_harm':
        return 'Self-harm or suicide';
      case 'shariah_concern':
        return 'Non-halal / shariah concern';
      case 'other':
        return 'Other';
      default:
        return code;
    }
  }

  /// Submit a report. Returns ({error}) when the call fails — the UI
  /// shows the error inline. On 409 the message says "already reported";
  /// callers can show that as a friendly state rather than an error.
  ///
  /// targetType ∈ [targetTypes], reason ∈ [reasons]. details is optional
  /// free text up to 2000 chars.
  static Future<({String? error, bool alreadyReported})> submit({
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        return (error: 'Sign in to report content.', alreadyReported: false);
      }
      final response = await http
          .post(
            Uri.parse('$_base/me/reports'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'targetType': targetType,
              'targetId': targetId,
              'reason': reason,
              if (details != null && details.isNotEmpty) 'details': details,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 201) {
        return (error: null, alreadyReported: false);
      }
      if (response.statusCode == 409) {
        return (error: null, alreadyReported: true);
      }
      final body = _safeDecode(response.body);
      return (
        error: (body['error'] ?? 'Could not submit report.').toString(),
        alreadyReported: false,
      );
    } catch (e) {
      return (error: 'Network error: $e', alreadyReported: false);
    }
  }

  /// Pull the current user's report history. Newest first.
  static Future<List<Map<String, dynamic>>> mine({int limit = 50}) async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) return const [];
      final response = await http.get(
        Uri.parse('$_base/me/reports?limit=$limit'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) return const [];
      final body = json.decode(response.body) as Map<String, dynamic>;
      final list = (body['reports'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return list;
    } catch (_) {
      return const [];
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
