import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';

/// Wraps the community co-ownership endpoints introduced in mig 0032
/// (`backend/internal/handlers/community_owners.go`).
///
/// Flow:
///   Sizar (primary owner) -> sendInvite(communityId, invitedUserId)
///   Ali  (invitee)        -> listMyIncoming() -> accept(invitationId)
///                                              | reject(invitationId)
///   Sizar (primary owner) -> cancel(invitationId)
///   anyone                -> listOwners(communityId) -> { primary, coOwners }
///
/// Errors come back as Dart `Exception`s with the backend's `error`
/// string so the UI can show a meaningful snackbar.
class CommunityOwnersService {
  static String get _base => ApiConfig.baseUrl;

  // ── helpers ──────────────────────────────────────────────────────

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _decode(http.Response r) {
    try {
      final v = json.decode(r.body);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return <String, dynamic>{};
  }

  // ── invitations ─────────────────────────────────────────────────

  /// Owner sends an invitation. Pass `invitedExpertId` for the mobile
  /// path (the `/api/experts` feed only exposes the public expert id
  /// like "ex_26"); admin tools that already have the platform user id
  /// can use `invitedUserId` instead. Exactly one is required.
  ///
  /// `message` is optional flavor text the invitee sees in their inbox.
  ///
  /// Returns the inserted [CommunityInvitation] on success, or `null`
  /// + `errorMessage` populated on failure (e.g. invitee not an expert,
  /// pending invite already exists, etc.).
  static Future<InviteResult> sendInvite({
    required String communityId,
    int? invitedUserId,
    String? invitedExpertId,
    String? message,
  }) async {
    try {
      final r = await http.post(
        Uri.parse('$_base/me/communities/$communityId/invitations'),
        headers: await _authHeaders(),
        body: json.encode({
          if (invitedUserId != null) 'invitedUserId': invitedUserId,
          if (invitedExpertId != null && invitedExpertId.isNotEmpty)
            'invitedExpertId': invitedExpertId,
          if (message != null && message.trim().isNotEmpty)
            'message': message.trim(),
        }),
      );
      final body = _decode(r);
      if (r.statusCode == 200) {
        return InviteResult(
          invitation: CommunityInvitation.fromJson(
            body['invitation'] as Map<String, dynamic>,
          ),
        );
      }
      return InviteResult(
        errorMessage:
            (body['error'] as String?) ?? 'Failed to send invitation',
        errorCode: body['code'] as String?,
      );
    } catch (e) {
      debugPrint('sendInvite error: $e');
      return InviteResult(errorMessage: 'Connection error: $e');
    }
  }

  /// Invitee's inbox. Defaults to `pending` only (the UI shows the
  /// active ones — resolved invites are out of date by definition).
  static Future<List<CommunityInvitation>> listMyIncoming({
    String status = 'pending',
  }) async {
    try {
      final r = await http.get(
        Uri.parse('$_base/me/community-invitations?status=$status'),
        headers: await _authHeaders(),
      );
      if (r.statusCode != 200) return const [];
      final body = _decode(r);
      final raw = (body['invitations'] as List?) ?? const [];
      return raw
          .map(
            (e) => CommunityInvitation.fromJson(e as Map<String, dynamic>),
          )
          .toList(growable: false);
    } catch (e) {
      debugPrint('listMyIncoming error: $e');
      return const [];
    }
  }

  /// Invitee accepts. Backend wraps the status flip + co-owner
  /// insertion in one transaction so we either get both or neither.
  static Future<InviteResult> accept(int invitationId) =>
      _resolveInvite(invitationId, 'accept');

  /// Invitee rejects.
  static Future<InviteResult> reject(int invitationId) =>
      _resolveInvite(invitationId, 'reject');

  static Future<InviteResult> _resolveInvite(
    int invitationId,
    String action,
  ) async {
    try {
      final r = await http.post(
        Uri.parse('$_base/me/community-invitations/$invitationId/$action'),
        headers: await _authHeaders(),
        body: '{}',
      );
      final body = _decode(r);
      if (r.statusCode == 200) {
        return InviteResult(
          invitation: CommunityInvitation.fromJson(
            body['invitation'] as Map<String, dynamic>,
          ),
        );
      }
      return InviteResult(
        errorMessage: (body['error'] as String?) ?? 'Failed to $action',
        errorCode: body['code'] as String?,
      );
    } catch (e) {
      return InviteResult(errorMessage: 'Connection error: $e');
    }
  }

  // ── owners ──────────────────────────────────────────────────────

  /// `(primary, coOwners)` for a community. Used by the settings
  /// view to render the full list. `primary` may be null in the
  /// edge case where owner_id is 0/missing.
  static Future<CommunityOwners> listOwners(String communityId) async {
    try {
      final r = await http.get(
        Uri.parse('$_base/communities/$communityId/owners'),
        headers: await _authHeaders(),
      );
      if (r.statusCode != 200) return const CommunityOwners.empty();
      final body = _decode(r);
      return CommunityOwners.fromJson(body);
    } catch (e) {
      return const CommunityOwners.empty();
    }
  }
}

// ── DTOs ──────────────────────────────────────────────────────────

class CommunityInvitation {
  final int id;
  final String communityId;
  final String communityName;
  final int invitedUserId;
  final int invitedBy;
  final String invitedByName;
  final String status; // pending | accepted | rejected | cancelled | expired
  final String message;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const CommunityInvitation({
    required this.id,
    required this.communityId,
    required this.communityName,
    required this.invitedUserId,
    required this.invitedBy,
    required this.invitedByName,
    required this.status,
    required this.message,
    required this.createdAt,
    this.resolvedAt,
  });

  factory CommunityInvitation.fromJson(Map<String, dynamic> j) =>
      CommunityInvitation(
        id: (j['id'] as num).toInt(),
        communityId: j['communityId'] as String? ?? '',
        communityName: j['communityName'] as String? ?? '',
        invitedUserId: (j['invitedUserId'] as num).toInt(),
        invitedBy: (j['invitedBy'] as num).toInt(),
        invitedByName: j['invitedByName'] as String? ?? '',
        status: j['status'] as String? ?? 'pending',
        message: j['message'] as String? ?? '',
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        resolvedAt: j['resolvedAt'] == null
            ? null
            : DateTime.tryParse(j['resolvedAt'] as String),
      );
}

class CommunityOwners {
  final CommunityOwnerEntry? primary;
  final List<CommunityOwnerEntry> coOwners;
  const CommunityOwners({required this.primary, required this.coOwners});
  const CommunityOwners.empty()
      : primary = null,
        coOwners = const [];

  factory CommunityOwners.fromJson(Map<String, dynamic> j) {
    final primaryJson = j['primary'] as Map<String, dynamic>?;
    final rawCo = (j['coOwners'] as List?) ?? const [];
    return CommunityOwners(
      primary: primaryJson == null
          ? null
          : CommunityOwnerEntry.fromJson(primaryJson, isPrimary: true),
      coOwners: rawCo
          .map(
            (e) => CommunityOwnerEntry.fromJson(
              e as Map<String, dynamic>,
              isPrimary: false,
            ),
          )
          .toList(growable: false),
    );
  }
}

class CommunityOwnerEntry {
  final int userId;
  final String name;
  final String email;
  final String expertId;
  final bool isPrimary;
  const CommunityOwnerEntry({
    required this.userId,
    required this.name,
    required this.email,
    required this.expertId,
    required this.isPrimary,
  });
  factory CommunityOwnerEntry.fromJson(
    Map<String, dynamic> j, {
    required bool isPrimary,
  }) =>
      CommunityOwnerEntry(
        userId: (j['userId'] as num).toInt(),
        name: j['name'] as String? ?? '',
        email: j['email'] as String? ?? '',
        expertId: j['expertId'] as String? ?? '',
        isPrimary: isPrimary,
      );
}

class InviteResult {
  final CommunityInvitation? invitation;
  final String? errorMessage;
  final String? errorCode;
  const InviteResult({this.invitation, this.errorMessage, this.errorCode});
  bool get success => invitation != null;
}
