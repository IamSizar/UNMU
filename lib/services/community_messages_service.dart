import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import 'auth_service.dart';

/// One row in the community chat. Mirrors the backend
/// `repositories.CommunityMessage` shape so deserialisation is a
/// 1-to-1 field map.
///
/// Reply / quote fields are 0/empty when this is a top-level message.
/// When [parentId] > 0, [parentAuthorName] + [parentBody] are
/// pre-populated by the backend's LEFT JOIN so the reply renders
/// self-contained without a follow-up fetch.
class CommunityMessage {
  final int id;
  final String communityId;
  final int authorId;
  final String authorName;
  final String authorEmail;
  final String authorRole;
  final String body;
  final DateTime createdAt;
  final int parentId;
  final String parentAuthorName;
  final String parentBody;
  /// Aggregate reaction counts: `{emoji: count}`. Always non-null (the
  /// chat screen iterates without nil-checking). Empty when nobody has
  /// reacted yet.
  final Map<String, int> reactionCounts;
  /// The viewer's own reactions on this message — used to highlight
  /// chips the user has already tapped. Set semantics; comparisons
  /// against this should use [.contains]. With the one-reaction-per-
  /// user rule this set is always size 0 or 1.
  final Set<String> myReactions;
  /// Optional attachment — voice messages today, image/video later.
  /// All three are empty/zero when this is a plain text message.
  /// [attachmentUrl] is a public `/uploads/...` path the client
  /// can play directly.
  final String attachmentUrl;
  final String attachmentType;
  final int attachmentDurationMs;
  /// Non-null when this message is pinned to the top of the
  /// community chat. Pin/unpin is owner-or-admin only — see the
  /// togglePin service method.
  final DateTime? pinnedAt;

  /// Step-21 (mig 0021, item 5.22) — edit tracking. Non-null after
  /// the first edit; the bubble shows an "edited" pill keyed off this.
  final DateTime? editedAt;

  /// Step-21 (mig 0021, item 5.18) — read receipts.
  /// Server-counted distinct readers excluding the author.
  final int readCount;
  /// Whether the current viewer has read it; drives client-side
  /// "skip POSTing read again" optimisation.
  final bool myRead;

  /// Step-21 (mig 0021, item 5.21) — embedded poll.
  /// Non-null only on poll-style messages. The bubble renders the
  /// poll widget instead of the plain body.
  final CommunityPoll? poll;

  const CommunityMessage({
    required this.id,
    required this.communityId,
    required this.authorId,
    required this.authorName,
    required this.authorEmail,
    required this.authorRole,
    required this.body,
    required this.createdAt,
    this.parentId = 0,
    this.parentAuthorName = '',
    this.parentBody = '',
    this.reactionCounts = const {},
    this.myReactions = const {},
    this.attachmentUrl = '',
    this.attachmentType = '',
    this.attachmentDurationMs = 0,
    this.pinnedAt,
    this.editedAt,
    this.readCount = 0,
    this.myRead = false,
    this.poll,
  });

  /// True when the message has been edited at least once — drives the
  /// "edited" pill on the bubble.
  bool get isEdited => editedAt != null;

  /// True when this message is a poll. Used by the bubble layer to
  /// switch between text-bubble and poll-widget rendering.
  bool get isPoll => poll != null;

  /// True when this row references a parent message — drives the
  /// quote preview rendered above the bubble body.
  bool get isReply => parentId > 0;

  /// True when at least one user has reacted with any emoji — drives
  /// whether the chip strip renders below the bubble.
  bool get hasReactions => reactionCounts.values.any((n) => n > 0);

  /// True when this message carries an audio attachment — drives the
  /// audio-bubble variant in the chat screen.
  bool get isAudio => attachmentType == 'audio' && attachmentUrl.isNotEmpty;

  /// True when this message carries an image attachment (e.g. a shared
  /// index chart) — drives the image-bubble variant in the chat screen.
  bool get isImage => attachmentType == 'image' && attachmentUrl.isNotEmpty;

  /// True when this message is currently pinned. The chat screen
  /// renders pinned messages in a sticky strip at the top.
  bool get isPinned => pinnedAt != null;

  factory CommunityMessage.fromJson(Map<String, dynamic> json) {
    final rawCounts = json['reactionCounts'];
    final counts = <String, int>{};
    if (rawCounts is Map) {
      rawCounts.forEach((k, v) {
        if (k is String && v is num) counts[k] = v.toInt();
      });
    }
    final rawMine = json['myReactions'];
    final mine = <String>{};
    if (rawMine is List) {
      for (final e in rawMine) {
        if (e is String) mine.add(e);
      }
    }
    return CommunityMessage(
      id: (json['id'] as num).toInt(),
      communityId: json['communityId'] as String? ?? '',
      authorId: (json['authorId'] as num?)?.toInt() ?? 0,
      authorName: json['authorName'] as String? ?? '',
      authorEmail: json['authorEmail'] as String? ?? '',
      authorRole: json['authorRole'] as String? ?? 'USER',
      body: json['body'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      parentId: (json['parentId'] as num?)?.toInt() ?? 0,
      parentAuthorName: json['parentAuthorName'] as String? ?? '',
      parentBody: json['parentBody'] as String? ?? '',
      reactionCounts: counts,
      myReactions: mine,
      attachmentUrl: json['attachmentUrl'] as String? ?? '',
      attachmentType: json['attachmentType'] as String? ?? '',
      attachmentDurationMs:
          (json['attachmentDurationMs'] as num?)?.toInt() ?? 0,
      pinnedAt: json['pinnedAt'] == null
          ? null
          : DateTime.tryParse(json['pinnedAt'] as String),
      editedAt: json['editedAt'] == null
          ? null
          : DateTime.tryParse(json['editedAt'] as String),
      readCount: (json['readCount'] as num?)?.toInt() ?? 0,
      myRead: json['myRead'] as bool? ?? false,
      poll: json['poll'] == null
          ? null
          : CommunityPoll.fromJson(json['poll'] as Map<String, dynamic>),
    );
  }

  /// Returns a copy of this message with [reactionCounts] /
  /// [myReactions] replaced. Used by the chat screen to patch a
  /// realtime reaction event into its local state without rebuilding
  /// the whole list.
  CommunityMessage copyWithReactions({
    Map<String, int>? reactionCounts,
    Set<String>? myReactions,
  }) {
    return CommunityMessage(
      id: id,
      communityId: communityId,
      authorId: authorId,
      authorName: authorName,
      authorEmail: authorEmail,
      authorRole: authorRole,
      body: body,
      createdAt: createdAt,
      parentId: parentId,
      parentAuthorName: parentAuthorName,
      parentBody: parentBody,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      myReactions: myReactions ?? this.myReactions,
      attachmentUrl: attachmentUrl,
      attachmentType: attachmentType,
      attachmentDurationMs: attachmentDurationMs,
      pinnedAt: pinnedAt,
      editedAt: editedAt,
      readCount: readCount,
      myRead: myRead,
      poll: poll,
    );
  }

  /// Returns a copy with the pin state replaced. Used by the chat
  /// screen to patch a single message after a pin toggle without
  /// rebuilding the whole list.
  CommunityMessage copyWithPin({DateTime? pinnedAt, bool clearPin = false}) {
    return CommunityMessage(
      id: id,
      communityId: communityId,
      authorId: authorId,
      authorName: authorName,
      authorEmail: authorEmail,
      authorRole: authorRole,
      body: body,
      createdAt: createdAt,
      parentId: parentId,
      parentAuthorName: parentAuthorName,
      parentBody: parentBody,
      reactionCounts: reactionCounts,
      myReactions: myReactions,
      attachmentUrl: attachmentUrl,
      attachmentType: attachmentType,
      attachmentDurationMs: attachmentDurationMs,
      pinnedAt: clearPin ? null : (pinnedAt ?? this.pinnedAt),
      editedAt: editedAt,
      readCount: readCount,
      myRead: myRead,
      poll: poll,
    );
  }

  /// Step-21 (mig 0021) — copy that replaces edit fields. Used by the
  /// chat screen to patch a bubble after an edit / read / poll-vote
  /// realtime event without rebuilding the whole list.
  CommunityMessage copyWith({
    String? body,
    DateTime? editedAt,
    int? readCount,
    bool? myRead,
    CommunityPoll? poll,
  }) {
    return CommunityMessage(
      id: id,
      communityId: communityId,
      authorId: authorId,
      authorName: authorName,
      authorEmail: authorEmail,
      authorRole: authorRole,
      body: body ?? this.body,
      createdAt: createdAt,
      parentId: parentId,
      parentAuthorName: parentAuthorName,
      parentBody: parentBody,
      reactionCounts: reactionCounts,
      myReactions: myReactions,
      attachmentUrl: attachmentUrl,
      attachmentType: attachmentType,
      attachmentDurationMs: attachmentDurationMs,
      pinnedAt: pinnedAt,
      editedAt: editedAt ?? this.editedAt,
      readCount: readCount ?? this.readCount,
      myRead: myRead ?? this.myRead,
      poll: poll ?? this.poll,
    );
  }
}

/// One option inside a chat poll (mig 0021, item 5.21). Mirrors the
/// backend `repositories.PollOption` shape.
class CommunityPollOption {
  final int id;
  final String label;
  final int sortOrder;
  final int voteCount;
  const CommunityPollOption({
    required this.id,
    required this.label,
    required this.sortOrder,
    required this.voteCount,
  });
  factory CommunityPollOption.fromJson(Map<String, dynamic> json) =>
      CommunityPollOption(
        id: (json['id'] as num).toInt(),
        label: json['label'] as String? ?? '',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        voteCount: (json['voteCount'] as num?)?.toInt() ?? 0,
      );
}

/// Embedded poll on a chat message (mig 0021, item 5.21). Mirrors the
/// backend `repositories.PollSummary` shape.
class CommunityPoll {
  final int id;
  final String question;
  final bool isAnonymous;
  final DateTime? closedAt;
  final DateTime? expiresAt;
  final List<CommunityPollOption> options;
  final int totalVotes;
  /// The viewer's chosen option id; 0 when they haven't voted yet.
  final int myOptionId;

  const CommunityPoll({
    required this.id,
    required this.question,
    required this.isAnonymous,
    required this.options,
    required this.totalVotes,
    required this.myOptionId,
    this.closedAt,
    this.expiresAt,
  });

  factory CommunityPoll.fromJson(Map<String, dynamic> json) {
    return CommunityPoll(
      id: (json['id'] as num).toInt(),
      question: json['question'] as String? ?? '',
      isAnonymous: json['isAnonymous'] as bool? ?? false,
      closedAt: json['closedAt'] == null
          ? null
          : DateTime.tryParse(json['closedAt'] as String),
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.tryParse(json['expiresAt'] as String),
      options: ((json['options'] as List<dynamic>?) ?? const [])
          .map((e) =>
              CommunityPollOption.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalVotes: (json['totalVotes'] as num?)?.toInt() ?? 0,
      myOptionId: (json['myOptionId'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isClosed =>
      closedAt != null ||
      (expiresAt != null && expiresAt!.isBefore(DateTime.now()));
}

/// One row in the "Seen by N" sheet (mig 0021, item 5.18).
class MessageReader {
  final int userId;
  final String name;
  final String email;
  final String role;
  final DateTime readAt;
  const MessageReader({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.readAt,
  });
  factory MessageReader.fromJson(Map<String, dynamic> json) =>
      MessageReader(
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        role: json['role'] as String? ?? 'USER',
        readAt: DateTime.tryParse(json['readAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// One row in the "who reacted with what" detail sheet — returned by
/// [CommunityMessagesService.listReactors]. Mirrors the backend
/// `repositories.Reactor` shape.
class CommunityReactor {
  final int userId;
  final String userName;
  final String email;
  final String role;
  final String emoji;
  final DateTime at;

  const CommunityReactor({
    required this.userId,
    required this.userName,
    required this.email,
    required this.role,
    required this.emoji,
    required this.at,
  });

  factory CommunityReactor.fromJson(Map<String, dynamic> json) {
    return CommunityReactor(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: json['userName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'USER',
      emoji: json['emoji'] as String? ?? '',
      at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Network calls for the per-community real-time chat. The chat
/// screen pairs this with a `RealtimeController` listener — sends are
/// optimistic-friendly (the broadcast event also lands on the sender,
/// so the screen de-dupes by id).
class CommunityMessagesService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/communities/:id/messages — newest-first.
  ///
  /// [before] is a keyset cursor — pass the oldest currently-loaded
  /// message's `createdAt` to fetch the next page. The server returns
  /// rows strictly older than this.
  ///
  /// Returns:
  ///   * the list on a 200,
  ///   * `null` on 401 (auth fail) — caller should show a sign-in
  ///     prompt; AuthController has already cleared the session.
  ///   * `null` on 403 (not a member) — caller renders a "Join to chat"
  ///     state.
  ///   * `null` on any other failure with [errorMessage] populated.
  static Future<({List<CommunityMessage>? messages, String? error})> list(
    String communityId, {
    DateTime? before,
    int limit = 50,
  }) async {
    try {
      final params = <String, String>{'limit': '$limit'};
      if (before != null) {
        params['before'] = before.toUtc().toIso8601String();
      }
      final qs = Uri(queryParameters: params).query;
      final url = qs.isEmpty
          ? '$_base/communities/$communityId/messages'
          : '$_base/communities/$communityId/messages?$qs';
      final response = await http.get(
        Uri.parse(url),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (messages: null, error: 'Session expired.');
      }
      if (response.statusCode == 403) {
        return (messages: null, error: 'Join the community to read messages.');
      }
      if (response.statusCode != 200) {
        final err = _safeDecode(response.body)['error']?.toString() ??
            'Failed (${response.statusCode}).';
        return (messages: null, error: err);
      }
      final body = json.decode(response.body) as Map<String, dynamic>;
      final list = (body['messages'] as List<dynamic>? ?? [])
          .map((e) => CommunityMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      return (messages: list, error: null);
    } catch (e) {
      return (messages: null, error: 'Connection error: $e');
    }
  }

  /// POST /api/communities/:id/messages — body `{body, parentId?}`.
  ///
  /// [parentId] is optional — pass the parent message's id to make
  /// this a reply. The backend validates the parent belongs to the
  /// same community before linking.
  ///
  /// Server-side, the row is persisted AND broadcast on the
  /// `community:<id>` realtime channel; the sender will also receive
  /// the broadcast event (chat screen de-dupes by message.id).
  static Future<({CommunityMessage? message, String? error})> send(
    String communityId,
    String body, {
    int? parentId,
    String? attachmentUrl,
    String? attachmentType,
  }) async {
    try {
      final reqBody = <String, dynamic>{'body': body};
      if (parentId != null && parentId > 0) reqBody['parentId'] = parentId;
      if (attachmentUrl != null && attachmentUrl.isNotEmpty) {
        reqBody['attachmentUrl'] = attachmentUrl;
        reqBody['attachmentType'] = attachmentType ?? 'image';
      }
      final response = await http.post(
        Uri.parse('$_base/communities/$communityId/messages'),
        headers: await _authHeaders(),
        body: json.encode(reqBody),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (message: null, error: 'Session expired.');
      }
      if (response.statusCode == 403) {
        return (message: null, error: 'Join the community to send messages.');
      }
      if (response.statusCode != 200) {
        final err = _safeDecode(response.body)['error']?.toString() ??
            'Failed (${response.statusCode}).';
        return (message: null, error: err);
      }
      final raw = json.decode(response.body) as Map<String, dynamic>;
      final m = raw['message'];
      if (m is! Map<String, dynamic>) {
        return (message: null, error: 'Server returned no message.');
      }
      return (message: CommunityMessage.fromJson(m), error: null);
    } catch (e) {
      return (message: null, error: 'Connection error: $e');
    }
  }

  /// POST /api/communities/:id/messages/:mid/pin — toggle the
  /// pinned state of a message. Owner-or-admin only at the server;
  /// 403 for everyone else. Returns the new state so the caller
  /// can patch its local copy.
  static Future<({bool? pinned, DateTime? pinnedAt, String? error})>
      togglePin(String communityId, int messageId) async {
    try {
      final response = await http.post(
        Uri.parse(
          '$_base/communities/$communityId/messages/$messageId/pin',
        ),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (pinned: null, pinnedAt: null, error: 'Session expired.');
      }
      if (response.statusCode == 403) {
        return (
          pinned: null,
          pinnedAt: null,
          error: 'Only the owner or an admin can pin.',
        );
      }
      if (response.statusCode != 200) {
        final err = _safeDecode(response.body)['error']?.toString() ??
            'Failed (${response.statusCode}).';
        return (pinned: null, pinnedAt: null, error: err);
      }
      final raw = json.decode(response.body) as Map<String, dynamic>;
      final pinned = raw['pinned'] as bool? ?? false;
      final pinnedAt = raw['pinnedAt'] == null
          ? null
          : DateTime.tryParse(raw['pinnedAt'] as String);
      return (pinned: pinned, pinnedAt: pinnedAt, error: null);
    } catch (e) {
      return (pinned: null, pinnedAt: null, error: 'Connection error: $e');
    }
  }

  /// DELETE /api/communities/:id/messages/:mid — removes a message
  /// the caller authored (or any message if the caller is an admin).
  ///
  /// Server broadcasts `community_message_deleted` on success; the
  /// chat screen listens and removes the bubble locally. We also
  /// return the success bool so the caller can do an immediate
  /// optimistic remove without waiting for the realtime round-trip.
  static Future<({bool ok, String? error})> deleteMessage(
    String communityId,
    int messageId,
  ) async {
    try {
      final response = await http.delete(
        Uri.parse('$_base/communities/$communityId/messages/$messageId'),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (ok: false, error: 'Session expired.');
      }
      if (response.statusCode == 403) {
        return (ok: false, error: 'You can only delete your own messages.');
      }
      if (response.statusCode == 404) {
        return (ok: false, error: 'Message no longer exists.');
      }
      if (response.statusCode != 200) {
        final err = _safeDecode(response.body)['error']?.toString() ??
            'Failed (${response.statusCode}).';
        return (ok: false, error: err);
      }
      return (ok: true, error: null);
    } catch (e) {
      return (ok: false, error: 'Connection error: $e');
    }
  }

  /// POST /api/communities/:id/messages/audio — multipart upload of
  /// a recorded voice message file.
  ///
  /// [filePath] is an on-device absolute path produced by the
  /// `record` package. The server saves it under /uploads/audio/,
  /// inserts a community_messages row pointing at the saved file,
  /// and broadcasts the resulting message just like a text Send.
  ///
  /// [durationMs] is the recorded length the client measured — the
  /// server stores it for chip-row rendering on receivers.
  /// [parentId] threads this voice note as a reply (optional).
  static Future<({CommunityMessage? message, String? error})> sendAudio(
    String communityId,
    String filePath, {
    int? durationMs,
    int? parentId,
  }) async {
    try {
      final uri = Uri.parse('$_base/communities/$communityId/messages/audio');
      final req = http.MultipartRequest('POST', uri);
      final token = await AuthService.getToken();
      if (token != null) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      // Attach the file. Field name MUST be "file" — matches
      // c.FormFile("file") on the server.
      req.files.add(await http.MultipartFile.fromPath('file', filePath));
      if (durationMs != null && durationMs > 0) {
        req.fields['durationMs'] = '$durationMs';
      }
      if (parentId != null && parentId > 0) {
        req.fields['parentId'] = '$parentId';
      }
      final streamed = await req.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (message: null, error: 'Session expired.');
      }
      if (response.statusCode == 403) {
        return (
          message: null,
          error: 'Join the community to send messages.',
        );
      }
      if (response.statusCode != 200) {
        final err = _safeDecode(response.body)['error']?.toString() ??
            'Failed (${response.statusCode}).';
        return (message: null, error: err);
      }
      final raw = json.decode(response.body) as Map<String, dynamic>;
      final m = raw['message'];
      if (m is! Map<String, dynamic>) {
        return (message: null, error: 'Server returned no message.');
      }
      return (message: CommunityMessage.fromJson(m), error: null);
    } catch (e) {
      return (message: null, error: 'Connection error: $e');
    }
  }

  /// POST /api/communities/:id/messages/:mid/reactions — toggles
  /// the (viewer, emoji) row on a message.
  ///
  /// Server emits a `community_message_reaction` realtime event; this
  /// method's return value is the immediate REST response so the
  /// caller can update its local state without waiting for the
  /// realtime round-trip.
  ///
  /// Returns:
  ///   * `(added, counts)` on 200 — `added` is true when the reaction
  ///     was newly placed, false when it was removed; `counts` is the
  ///     post-toggle full `{emoji: int}` map for the message.
  ///   * `(null, error)` on any failure.
  static Future<({bool? added, Map<String, int>? counts, String? error})>
      toggleReaction(String communityId, int messageId, String emoji) async {
    try {
      final response = await http.post(
        Uri.parse(
          '$_base/communities/$communityId/messages/$messageId/reactions',
        ),
        headers: await _authHeaders(),
        body: json.encode({'emoji': emoji}),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (added: null, counts: null, error: 'Session expired.');
      }
      if (response.statusCode == 403) {
        return (
          added: null,
          counts: null,
          error: 'Join the community to react.',
        );
      }
      if (response.statusCode != 200) {
        final err = _safeDecode(response.body)['error']?.toString() ??
            'Failed (${response.statusCode}).';
        return (added: null, counts: null, error: err);
      }
      final raw = json.decode(response.body) as Map<String, dynamic>;
      final added = raw['added'] as bool? ?? false;
      final rawCounts = raw['counts'];
      final counts = <String, int>{};
      if (rawCounts is Map) {
        rawCounts.forEach((k, v) {
          if (k is String && v is num) counts[k] = v.toInt();
        });
      }
      return (added: added, counts: counts, error: null);
    } catch (e) {
      return (added: null, counts: null, error: 'Connection error: $e');
    }
  }

  /// GET /api/communities/:id/messages/:mid/reactions — full per-user
  /// reactor list, drives the "who reacted with what" detail sheet.
  static Future<({List<CommunityReactor>? reactors, String? error})>
      listReactors(String communityId, int messageId) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$_base/communities/$communityId/messages/$messageId/reactions',
        ),
        headers: await _authHeaders(),
      );
      if (response.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (reactors: null, error: 'Session expired.');
      }
      if (response.statusCode != 200) {
        final err = _safeDecode(response.body)['error']?.toString() ??
            'Failed (${response.statusCode}).';
        return (reactors: null, error: err);
      }
      final body = json.decode(response.body) as Map<String, dynamic>;
      final list = (body['reactors'] as List<dynamic>? ?? [])
          .map((e) => CommunityReactor.fromJson(e as Map<String, dynamic>))
          .toList();
      return (reactors: list, error: null);
    } catch (e) {
      return (reactors: null, error: 'Connection error: $e');
    }
  }

  // ──────────────────────────────────────────────────────────
  // Step-21 (mig 0021) — search, edit, read, polls, typing, settings
  // ──────────────────────────────────────────────────────────

  /// GET /api/communities/:id/messages/search?q=<q>
  /// Returns up to 50 matching messages, newest-first.
  static Future<({List<CommunityMessage>? results, String? error})>
      search(String communityId, String query) async {
    try {
      final res = await http.get(
        Uri.parse(
          '$_base/communities/$communityId/messages/search?q=${Uri.encodeQueryComponent(query)}',
        ),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (results: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        return (
          results: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Search failed (${res.statusCode}).',
        );
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = (body['messages'] as List<dynamic>? ?? [])
          .map((e) => CommunityMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      return (results: list, error: null);
    } catch (e) {
      return (results: null, error: 'Connection error: $e');
    }
  }

  /// POST /api/communities/:id/messages/:mid/read — idempotent.
  static Future<bool> markRead(String communityId, int messageId) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/communities/$communityId/messages/$messageId/read'),
        headers: await _authHeaders(),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// POST /api/communities/:id/messages/read-batch
  /// Body: { messageIds: [N, M, ...] } — up to 200 ids.
  static Future<int> markBatchRead(
    String communityId,
    List<int> messageIds,
  ) async {
    if (messageIds.isEmpty) return 0;
    try {
      final res = await http.post(
        Uri.parse('$_base/communities/$communityId/messages/read-batch'),
        headers: await _authHeaders(),
        body: json.encode({'messageIds': messageIds}),
      );
      if (res.statusCode != 200) return 0;
      final body = json.decode(res.body) as Map<String, dynamic>;
      return (body['inserted'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// GET /api/communities/:id/messages/:mid/reads — avatar list.
  static Future<({List<MessageReader>? readers, String? error})>
      listReaders(String communityId, int messageId) async {
    try {
      final res = await http.get(
        Uri.parse(
          '$_base/communities/$communityId/messages/$messageId/reads',
        ),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (readers: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        return (
          readers: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Failed (${res.statusCode}).',
        );
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = (body['readers'] as List<dynamic>? ?? [])
          .map((e) => MessageReader.fromJson(e as Map<String, dynamic>))
          .toList();
      return (readers: list, error: null);
    } catch (e) {
      return (readers: null, error: 'Connection error: $e');
    }
  }

  /// PATCH /api/communities/:id/messages/:mid — edit own message.
  /// Returns 409 with a friendly error past the 15-min window.
  static Future<({CommunityMessage? message, String? error})> editMessage({
    required String communityId,
    required int messageId,
    required String body,
  }) async {
    try {
      final res = await http.patch(
        Uri.parse('$_base/communities/$communityId/messages/$messageId'),
        headers: await _authHeaders(),
        body: json.encode({'body': body}),
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
      final body0 = json.decode(res.body) as Map<String, dynamic>;
      final m = CommunityMessage.fromJson(
        body0['message'] as Map<String, dynamic>,
      );
      return (message: m, error: null);
    } catch (e) {
      return (message: null, error: 'Connection error: $e');
    }
  }

  /// POST /api/communities/:id/typing — pure realtime fan-out, no
  /// optimistic state. Throttle the caller; we do NOT debounce here.
  static Future<void> sendTyping(String communityId, {bool stopped = false}) async {
    try {
      await http.post(
        Uri.parse('$_base/communities/$communityId/typing'),
        headers: await _authHeaders(),
        body: json.encode({'stopped': stopped}),
      );
    } catch (_) {
      // Best-effort. Typing is fire-and-forget.
    }
  }

  /// POST /api/communities/:id/polls — create + broadcast.
  /// Returns the host CommunityMessage with `.poll` embedded.
  static Future<({CommunityMessage? message, String? error})> createPoll({
    required String communityId,
    required String question,
    required List<String> options,
    bool isAnonymous = false,
    int expiresInHours = 0,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/communities/$communityId/polls'),
        headers: await _authHeaders(),
        body: json.encode({
          'question': question,
          'options': options,
          'isAnonymous': isAnonymous,
          'expiresInHours': expiresInHours,
        }),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (message: null, error: 'Session expired.');
      }
      if (res.statusCode != 201) {
        return (
          message: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Create poll failed (${res.statusCode}).',
        );
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final m = CommunityMessage.fromJson(
        body['message'] as Map<String, dynamic>,
      );
      return (message: m, error: null);
    } catch (e) {
      return (message: null, error: 'Connection error: $e');
    }
  }

  /// POST /api/communities/:id/polls/:pid/vote
  static Future<({bool ok, String? error})> votePoll({
    required String communityId,
    required int pollId,
    required int optionId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/communities/$communityId/polls/$pollId/vote'),
        headers: await _authHeaders(),
        body: json.encode({'optionId': optionId}),
      );
      if (res.statusCode == 200) return (ok: true, error: null);
      return (
        ok: false,
        error: _safeDecode(res.body)['error']?.toString() ??
            'Vote failed (${res.statusCode}).',
      );
    } catch (e) {
      return (ok: false, error: 'Connection error: $e');
    }
  }

  /// POST /api/communities/:id/polls/:pid/close — author / community
  /// owner / admin only.
  static Future<({bool ok, String? error})> closePoll({
    required String communityId,
    required int pollId,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/communities/$communityId/polls/$pollId/close'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 200) return (ok: true, error: null);
      return (
        ok: false,
        error: _safeDecode(res.body)['error']?.toString() ??
            'Close failed (${res.statusCode}).',
      );
    } catch (e) {
      return (ok: false, error: 'Connection error: $e');
    }
  }

  /// GET /api/me/settings/read-receipts — current toggle state.
  static Future<bool> getReadReceiptsEnabled() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/me/settings/read-receipts'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) return true;
      final body = json.decode(res.body) as Map<String, dynamic>;
      return body['enabled'] as bool? ?? true;
    } catch (_) {
      return true;
    }
  }

  /// PATCH /api/me/settings/read-receipts — flip the per-user toggle.
  static Future<bool> setReadReceiptsEnabled(bool enabled) async {
    try {
      final res = await http.patch(
        Uri.parse('$_base/me/settings/read-receipts'),
        headers: await _authHeaders(),
        body: json.encode({'enabled': enabled}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
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
