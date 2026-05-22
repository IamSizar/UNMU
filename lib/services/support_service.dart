import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import 'auth_service.dart';

/// Built-in user ↔ admin support chat (mig 0029).
///
/// One thread per user — the backend creates / fetches it on demand
/// (see `EnsureThread` in `internal/repositories/support.go`), so the
/// service surface here is just send + list + mark-read.
class SupportService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/me/support/messages — full chat history + the thread row
  /// (status, unread_user, etc.). Returns an empty list when the user
  /// has never written before; the thread is auto-created server-side.
  static Future<({SupportThread? thread, List<SupportMessage> messages, String? error})>
      myMessages() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/me/support/messages'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (thread: null, messages: const <SupportMessage>[], error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        return (
          thread: null,
          messages: const <SupportMessage>[],
          error: _safeDecode(res.body)['error']?.toString() ??
              'Load failed (${res.statusCode}).',
        );
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final thread = body['thread'] == null
          ? null
          : SupportThread.fromJson(body['thread'] as Map<String, dynamic>);
      final msgs = ((body['messages'] as List?) ?? const [])
          .map((e) => SupportMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      return (thread: thread, messages: msgs, error: null);
    } catch (e) {
      debugPrint('SupportService.myMessages: $e');
      return (
        thread: null,
        messages: const <SupportMessage>[],
        error: 'Connection error: $e',
      );
    }
  }

  /// POST /api/me/support/messages — send a user message. Returns the
  /// newly-inserted row on success. 429 means the per-user rate limit
  /// (1 message / 2 seconds) kicked in — surface that as a friendly
  /// snackbar in the caller.
  static Future<({SupportMessage? message, String? error, bool rateLimited})>
      send(String text) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/me/support/messages'),
        headers: await _authHeaders(),
        body: json.encode({'body': text}),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (message: null, error: 'Session expired.', rateLimited: false);
      }
      if (res.statusCode == 429) {
        final err = _safeDecode(res.body)['error']?.toString() ??
            'Please wait a moment.';
        return (message: null, error: err, rateLimited: true);
      }
      if (res.statusCode != 201) {
        return (
          message: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Send failed (${res.statusCode}).',
          rateLimited: false,
        );
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      return (
        message: SupportMessage.fromJson(
          body['message'] as Map<String, dynamic>,
        ),
        error: null,
        rateLimited: false,
      );
    } catch (e) {
      return (message: null, error: 'Connection error: $e', rateLimited: false);
    }
  }

  /// PATCH /api/me/support/messages/:id — edit the user's own message.
  /// Returns the updated row (with `editedAt` populated) on success.
  /// 403 means the user tried to edit someone else's message; 400
  /// means the body was empty / too long / the message is deleted.
  static Future<({SupportMessage? message, String? error})> editMine(
    int messageId,
    String text,
  ) async {
    try {
      final res = await http.patch(
        Uri.parse('$_base/me/support/messages/$messageId'),
        headers: await _authHeaders(),
        body: json.encode({'body': text}),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (message: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        return (
          message: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Edit failed (${res.statusCode}).',
        );
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      return (
        message: SupportMessage.fromJson(
          body['message'] as Map<String, dynamic>,
        ),
        error: null,
      );
    } catch (e) {
      return (message: null, error: 'Connection error: $e');
    }
  }

  /// POST /api/me/support/read — zero the user-side unread counter.
  /// Called when the user opens the chat screen + after each new
  /// admin message they actually see. Idempotent; failures are
  /// silently swallowed so a flaky network doesn't surface a banner.
  static Future<void> markRead() async {
    try {
      await http.post(
        Uri.parse('$_base/me/support/read'),
        headers: await _authHeaders(),
      );
    } catch (_) {/* best-effort */}
  }

  static Map<String, dynamic> _safeDecode(String s) {
    try {
      final v = json.decode(s);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return {};
  }
}

/// Thread metadata. `unreadUser` drives the bell badge on the
/// settings → Contact Admin tile. Status flips to 'closed' when an
/// admin closes the thread (user re-opens implicitly by sending).
class SupportThread {
  final int id;
  final int userId;
  final String status;
  final DateTime lastMessageAt;
  final String lastMessageRole;
  final String lastMessageBody;
  final int unreadAdmin;
  final int unreadUser;
  /// Mig 0030 — id of the single pinned message in this thread.
  /// Null when nothing is pinned. The UI shows a small pinned banner
  /// at the top of the chat when this is set.
  final int? pinnedMessageId;

  const SupportThread({
    required this.id,
    required this.userId,
    required this.status,
    required this.lastMessageAt,
    required this.lastMessageRole,
    required this.lastMessageBody,
    required this.unreadAdmin,
    required this.unreadUser,
    this.pinnedMessageId,
  });

  bool get isClosed => status == 'closed';

  factory SupportThread.fromJson(Map<String, dynamic> j) => SupportThread(
        id: (j['id'] as num).toInt(),
        userId: (j['userId'] as num?)?.toInt() ?? 0,
        status: (j['status'] as String?) ?? 'open',
        lastMessageAt:
            DateTime.tryParse(j['lastMessageAt'] as String? ?? '') ??
                DateTime.now(),
        lastMessageRole: (j['lastMessageRole'] as String?) ?? '',
        lastMessageBody: (j['lastMessageBody'] as String?) ?? '',
        unreadAdmin: (j['unreadAdmin'] as num?)?.toInt() ?? 0,
        unreadUser: (j['unreadUser'] as num?)?.toInt() ?? 0,
        pinnedMessageId: (j['pinnedMessageId'] as num?)?.toInt(),
      );

  SupportThread copyWith({
    String? status,
    int? unreadAdmin,
    int? unreadUser,
    int? pinnedMessageId,
    bool clearPin = false,
  }) =>
      SupportThread(
        id: id,
        userId: userId,
        status: status ?? this.status,
        lastMessageAt: lastMessageAt,
        lastMessageRole: lastMessageRole,
        lastMessageBody: lastMessageBody,
        unreadAdmin: unreadAdmin ?? this.unreadAdmin,
        unreadUser: unreadUser ?? this.unreadUser,
        pinnedMessageId:
            clearPin ? null : (pinnedMessageId ?? this.pinnedMessageId),
      );
}

/// A single chat message. `senderRole` decides bubble alignment
/// (`user` → right, `admin` → left); `senderName` is only meaningful on
/// admin replies (so the user sees "Admin team" or the admin's actual
/// name when configured).
class SupportMessage {
  final int id;
  final int threadId;
  final int senderUserId;
  final String senderRole; // 'user' | 'admin'
  final String senderName;
  final String body;
  final DateTime createdAt;
  /// Mig 0030 — non-null when this message has been edited at least
  /// once. UI appends "(edited)" to distinguish.
  final DateTime? editedAt;
  /// Mig 0030 — non-null when admin soft-deleted this message. The
  /// row stays so the chat flow doesn't lose its rhythm; UI renders
  /// "[message deleted]" instead of the body.
  final DateTime? deletedAt;

  const SupportMessage({
    required this.id,
    required this.threadId,
    required this.senderUserId,
    required this.senderRole,
    required this.senderName,
    required this.body,
    required this.createdAt,
    this.editedAt,
    this.deletedAt,
  });

  bool get isUser => senderRole == 'user';
  bool get isAdmin => senderRole == 'admin';
  bool get isEdited => editedAt != null;
  bool get isDeleted => deletedAt != null;

  factory SupportMessage.fromJson(Map<String, dynamic> j) {
    DateTime? parseTs(Object? raw) =>
        raw == null ? null : DateTime.tryParse(raw.toString());
    return SupportMessage(
      id: (j['id'] as num).toInt(),
      threadId: (j['threadId'] as num?)?.toInt() ?? 0,
      senderUserId: (j['senderUserId'] as num?)?.toInt() ?? 0,
      senderRole: (j['senderRole'] as String?) ?? 'user',
      senderName: (j['senderName'] as String?) ?? '',
      body: (j['body'] as String?) ?? '',
      createdAt: parseTs(j['createdAt']) ?? DateTime.now(),
      editedAt: parseTs(j['editedAt']),
      deletedAt: parseTs(j['deletedAt']),
    );
  }

  SupportMessage copyWith({
    String? body,
    DateTime? editedAt,
    DateTime? deletedAt,
  }) =>
      SupportMessage(
        id: id,
        threadId: threadId,
        senderUserId: senderUserId,
        senderRole: senderRole,
        senderName: senderName,
        body: body ?? this.body,
        createdAt: createdAt,
        editedAt: editedAt ?? this.editedAt,
        deletedAt: deletedAt ?? this.deletedAt,
      );
}
