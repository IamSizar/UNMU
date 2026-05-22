import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import 'auth_service.dart';

/// "Experts in this community" row — mirrors the backend
/// `repositories.CommunityExpertSummary` shape. Used to render the
/// horizontal expert-cards strip on the community detail screen.
class CommunityExpert {
  final int userId;
  final String expertId;
  final String name;
  final String email;
  final String bio;
  final String expertise;
  final int subscriberCount;
  final bool isOwner;

  const CommunityExpert({
    required this.userId,
    required this.expertId,
    required this.name,
    required this.email,
    required this.bio,
    required this.expertise,
    required this.subscriberCount,
    required this.isOwner,
  });

  factory CommunityExpert.fromJson(Map<String, dynamic> json) {
    return CommunityExpert(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      expertId: json['expertId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      expertise: json['expertise'] as String? ?? '',
      subscriberCount: (json['subscriberCount'] as num?)?.toInt() ?? 0,
      isOwner: json['isOwner'] as bool? ?? false,
    );
  }
}

/// One row in the community members list — shape mirrors the
/// backend's AdminCommunityMemberRow struct (role + owner flag + join
/// timestamp). Used by the owner-only Remove / Transfer picker
/// sheets.
class CommunityMemberRow {
  final int userId;
  final String name;
  final String email;
  final String role;
  final bool isOwner;
  final DateTime joinedAt;

  const CommunityMemberRow({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.isOwner,
    required this.joinedAt,
  });

  factory CommunityMemberRow.fromJson(Map<String, dynamic> json) {
    return CommunityMemberRow(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'USER',
      isOwner: json['isOwner'] as bool? ?? false,
      joinedAt: DateTime.tryParse(json['joinedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Live metadata snapshot returned by `/communities/:id` — the server-side
/// authoritative shape that includes the step-19 fields (description,
/// rules, cover_url, is_public, category, tags). Used by the edit sheet
/// + the discovery screen so the mobile UI doesn't have to rely on the
/// in-memory mock community for these fields.
class CommunityMeta {
  final String id;
  final String name;
  final String regionCode;
  final String tagline;
  final String description;
  final String rules;
  final String coverUrl;
  /// AvatarURL (mig 0028) — square logo distinct from the wide cover.
  /// Empty when the admin / owner hasn't set one yet; the UI then renders
  /// a region-tinted initials tile as a fallback.
  final String avatarUrl;
  final bool isPublic;
  final String category;
  final List<String> tags;
  final int memberCount;
  final int activeNow;
  /// Step-23 (mig 0022) — paid community pricing. Both 0 → free.
  final int joinPriceMonthlyCents;
  final int joinPriceYearlyCents;
  final String priceCurrency;
  /// Sprint-C step 7 — owner user id (nullable in DB). Lets the
  /// mobile hub render the gold-crown "owned" card variant when
  /// `ownerId == auth.user.id`.
  final int? ownerId;

  const CommunityMeta({
    required this.id,
    required this.name,
    required this.regionCode,
    required this.tagline,
    required this.description,
    required this.rules,
    required this.coverUrl,
    this.avatarUrl = '',
    required this.isPublic,
    required this.category,
    required this.tags,
    required this.memberCount,
    required this.activeNow,
    this.joinPriceMonthlyCents = 0,
    this.joinPriceYearlyCents = 0,
    this.priceCurrency = 'usd',
    this.ownerId,
  });

  /// True when at least one of the two prices is non-zero — the
  /// community charges to join. Drives the price chip + pricing
  /// card on the pre-join preview.
  bool get isPaid =>
      joinPriceMonthlyCents > 0 || joinPriceYearlyCents > 0;

  factory CommunityMeta.fromJson(Map<String, dynamic> json) {
    return CommunityMeta(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      regionCode: json['regionCode'] as String? ?? '',
      tagline: json['tagline'] as String? ?? '',
      description: json['description'] as String? ?? '',
      rules: json['rules'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      isPublic: json['isPublic'] as bool? ?? false,
      category: json['category'] as String? ?? '',
      tags: ((json['tags'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      activeNow: (json['activeNow'] as num?)?.toInt() ?? 0,
      joinPriceMonthlyCents:
          (json['joinPriceMonthlyCents'] as num?)?.toInt() ?? 0,
      joinPriceYearlyCents:
          (json['joinPriceYearlyCents'] as num?)?.toInt() ?? 0,
      priceCurrency: json['priceCurrency'] as String? ?? 'usd',
      ownerId: (json['ownerId'] as num?)?.toInt(),
    );
  }

  CommunityMeta copyWith({
    String? name,
    String? tagline,
    String? description,
    String? rules,
    String? coverUrl,
    String? avatarUrl,
    bool? isPublic,
    String? category,
    List<String>? tags,
    int? joinPriceMonthlyCents,
    int? joinPriceYearlyCents,
    String? priceCurrency,
  }) =>
      CommunityMeta(
        id: id,
        name: name ?? this.name,
        regionCode: regionCode,
        tagline: tagline ?? this.tagline,
        description: description ?? this.description,
        rules: rules ?? this.rules,
        coverUrl: coverUrl ?? this.coverUrl,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        isPublic: isPublic ?? this.isPublic,
        category: category ?? this.category,
        tags: tags ?? this.tags,
        memberCount: memberCount,
        activeNow: activeNow,
        joinPriceMonthlyCents:
            joinPriceMonthlyCents ?? this.joinPriceMonthlyCents,
        joinPriceYearlyCents:
            joinPriceYearlyCents ?? this.joinPriceYearlyCents,
        priceCurrency: priceCurrency ?? this.priceCurrency,
        ownerId: ownerId,
      );
}

/// Membership snapshot returned by `/communities/:id/membership` —
/// drives the Join/Leave button state on the community detail
/// screen. Owners see neither — they get the admin gear menu
/// instead. [memberCount] is the live aggregate (computed via
/// `SELECT COUNT(*) FROM community_members`) so the header reflects
/// reality even after recent joins/leaves.
class CommunityMembership {
  final bool member;
  final bool owner;
  final int memberCount;
  const CommunityMembership({
    required this.member,
    required this.owner,
    required this.memberCount,
  });
}

/// One expert row from `/api/experts`. Lightweight — just the fields the
/// hub leaderboard needs. The mobile mock-Expert class has many extra
/// (decorative) fields that come from `MockSocialData`; this class only
/// carries what the backend actually knows so the hub can render real
/// data without fabricating sparklines / pctChange / ticker info.
class RealExpertRow {
  final String id;
  final String name;
  final String expertise;
  final String bio;
  final String tier; // 'expert'
  final int subscriberCount;

  const RealExpertRow({
    required this.id,
    required this.name,
    required this.expertise,
    required this.bio,
    required this.tier,
    required this.subscriberCount,
  });

  factory RealExpertRow.fromJson(Map<String, dynamic> json) => RealExpertRow(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        expertise: json['expertise'] as String? ?? '',
        bio: json['bio'] as String? ?? '',
        tier: json['tier'] as String? ?? 'expert',
        subscriberCount:
            (json['subscriberCount'] as num?)?.toInt() ?? 0,
      );
}

/// REST surface for community membership + expert-list endpoints
/// added to support the in-app Join/Leave flow and the "Experts in
/// this community" panel.
///
/// All methods follow the same `({result, error})` record pattern
/// used by [CommunityMessagesService] so callers don't have to
/// catch — they pattern-match on the result.
class CommunityService {
  static String get _base => ApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/experts — every verified expert in the platform, sorted by
  /// subscriber count (newest popular first). Public; no auth required.
  /// Drives the Social Hub's "Top experts this week" leaderboard with
  /// real data instead of `MockSocialData.experts`.
  static Future<({List<RealExpertRow>? experts, String? error})>
      listAllExperts() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/experts'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (experts: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        return (
          experts: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Load failed (${res.statusCode}).',
        );
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final raw = (body['experts'] as List<dynamic>?) ?? const [];
      final rows = raw
          .map((e) => RealExpertRow.fromJson(e as Map<String, dynamic>))
          .toList();
      return (experts: rows, error: null);
    } catch (e) {
      return (experts: null, error: 'Connection error: $e');
    }
  }

  /// GET /api/communities — every community in the platform. Public.
  /// Used by the Social Hub's "Your communities + Discover" sections so
  /// the cards render against real DB rows (names, taglines, member
  /// counts, paid pricing) instead of `MockSocialData.communities`.
  static Future<({List<CommunityMeta>? communities, String? error})>
      listAllCommunities() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/communities'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (communities: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        return (
          communities: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Load failed (${res.statusCode}).',
        );
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final raw = (body['communities'] as List<dynamic>?) ?? const [];
      final rows = raw
          .map((e) => CommunityMeta.fromJson(e as Map<String, dynamic>))
          .toList();
      return (communities: rows, error: null);
    } catch (e) {
      return (communities: null, error: 'Connection error: $e');
    }
  }

  /// POST /api/communities/:id/join — idempotent on the server
  /// (ON CONFLICT DO NOTHING), so re-joining is safe.
  ///
  /// Step-23 follow-up: on a paid community, the server returns
  /// **402 Payment Required** with the price hint. We surface a
  /// `paymentRequired` flag so callers can route to the preview
  /// screen instead of dead-ending at an error toast.
  static Future<({
    bool ok,
    String? error,
    bool paymentRequired,
    int monthlyCents,
    int yearlyCents,
    String currency,
  })> join(String communityId) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/communities/$communityId/join'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (
          ok: false,
          error: 'Session expired.',
          paymentRequired: false,
          monthlyCents: 0,
          yearlyCents: 0,
          currency: 'usd',
        );
      }
      if (res.statusCode == 402) {
        final body = _safeDecode(res.body);
        return (
          ok: false,
          error: body['error']?.toString() ??
              'This community requires a paid subscription.',
          paymentRequired: true,
          monthlyCents:
              (body['joinPriceMonthlyCents'] as num?)?.toInt() ?? 0,
          yearlyCents:
              (body['joinPriceYearlyCents'] as num?)?.toInt() ?? 0,
          currency: body['priceCurrency'] as String? ?? 'usd',
        );
      }
      if (res.statusCode != 200) {
        final err = _safeDecode(res.body)['error']?.toString() ??
            'Failed (${res.statusCode}).';
        return (
          ok: false,
          error: err,
          paymentRequired: false,
          monthlyCents: 0,
          yearlyCents: 0,
          currency: 'usd',
        );
      }
      return (
        ok: true,
        error: null,
        paymentRequired: false,
        monthlyCents: 0,
        yearlyCents: 0,
        currency: 'usd',
      );
    } catch (e) {
      return (
        ok: false,
        error: 'Connection error: $e',
        paymentRequired: false,
        monthlyCents: 0,
        yearlyCents: 0,
        currency: 'usd',
      );
    }
  }

  /// POST /api/communities/:id/leave —
  ///   * 200 = removed,
  ///   * 404 = wasn't a member to begin with,
  ///   * 409 = caller is the community owner (must use admin
  ///     dashboard transfer/delete flow).
  static Future<({bool ok, String? error})> leave(String communityId) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/communities/$communityId/leave'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (ok: false, error: 'Session expired.');
      }
      if (res.statusCode == 200) return (ok: true, error: null);
      final err = _safeDecode(res.body)['error']?.toString() ??
          'Failed (${res.statusCode}).';
      return (ok: false, error: err);
    } catch (e) {
      return (ok: false, error: 'Connection error: $e');
    }
  }

  /// GET /api/communities/:id/membership — `{member, owner}`. Used
  /// once on screen mount to flip the CTA. We don't poll because
  /// the WS connection re-broadcasts member changes (future).
  static Future<({CommunityMembership? membership, String? error})>
      getMembership(String communityId) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/communities/$communityId/membership'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (membership: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        final err = _safeDecode(res.body)['error']?.toString() ??
            'Failed (${res.statusCode}).';
        return (membership: null, error: err);
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      return (
        membership: CommunityMembership(
          member: body['member'] as bool? ?? false,
          owner: body['owner'] as bool? ?? false,
          memberCount: (body['memberCount'] as num?)?.toInt() ?? 0,
        ),
        error: null,
      );
    } catch (e) {
      return (membership: null, error: 'Connection error: $e');
    }
  }

  /// GET /api/communities/:id/members — auth-required member list.
  /// Drives the owner-only Remove / Transfer picker sheets on the
  /// community detail screen. Server returns members owner-first.
  static Future<({List<CommunityMemberRow>? members, String? error})>
      listMembers(String communityId) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/communities/$communityId/members'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (members: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        final err = _safeDecode(res.body)['error']?.toString() ??
            'Failed (${res.statusCode}).';
        return (members: null, error: err);
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = (body['members'] as List<dynamic>? ?? [])
          .map((e) => CommunityMemberRow.fromJson(e as Map<String, dynamic>))
          .toList();
      return (members: list, error: null);
    } catch (e) {
      return (members: null, error: 'Connection error: $e');
    }
  }

  /// DELETE /api/communities/:id/members/:userId — owner-only kick.
  ///   * 200 = removed,
  ///   * 403 = caller isn't the community owner,
  ///   * 404 = target user wasn't a member,
  ///   * 409 = caller tried to remove themselves (the owner).
  static Future<({bool ok, String? error})> removeMember(
    String communityId,
    int userId,
  ) async {
    try {
      final res = await http.delete(
        Uri.parse('$_base/communities/$communityId/members/$userId'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (ok: false, error: 'Session expired.');
      }
      if (res.statusCode == 200) return (ok: true, error: null);
      final err = _safeDecode(res.body)['error']?.toString() ??
          'Failed (${res.statusCode}).';
      return (ok: false, error: err);
    } catch (e) {
      return (ok: false, error: 'Connection error: $e');
    }
  }

  /// POST /api/communities/:id/transfer-ownership — owner-only.
  /// New owner must already be a member.
  static Future<({bool ok, String? error})> transferOwnership(
    String communityId,
    int newOwnerId,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/communities/$communityId/transfer-ownership'),
        headers: await _authHeaders(),
        body: json.encode({'newOwnerId': newOwnerId}),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (ok: false, error: 'Session expired.');
      }
      if (res.statusCode == 200) return (ok: true, error: null);
      final err = _safeDecode(res.body)['error']?.toString() ??
          'Failed (${res.statusCode}).';
      return (ok: false, error: err);
    } catch (e) {
      return (ok: false, error: 'Connection error: $e');
    }
  }

  /// GET /api/me/communities — auth-required. Returns the set of
  /// community ids the caller is a member of. Drives the "Joined"
  /// filter toggle on the social hub.
  static Future<({Set<String>? ids, String? error})> myCommunityIds() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/me/communities'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (ids: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        final err = _safeDecode(res.body)['error']?.toString() ??
            'Failed (${res.statusCode}).';
        return (ids: null, error: err);
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = (body['communityIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toSet();
      return (ids: list, error: null);
    } catch (e) {
      return (ids: null, error: 'Connection error: $e');
    }
  }

  /// GET /api/communities/:id/posts — the community's post feed, newest
  /// first. Returns raw JSON rows; the caller maps them to its post model.
  /// (The community-list adapter ships communities with an empty `posts`
  /// list, so the detail screen must fetch this itself.)
  static Future<({List<Map<String, dynamic>>? rows, String? error})> listPosts(
    String communityId,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/communities/$communityId/posts'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (rows: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        final err = _safeDecode(res.body)['error']?.toString() ??
            'Failed (${res.statusCode}).';
        return (rows: null, error: err);
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = (body['posts'] as List<dynamic>? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      return (rows: list, error: null);
    } catch (e) {
      return (rows: null, error: 'Connection error: $e');
    }
  }

  // ──────────────────────────────────────────────────────────
  // Community-post moderation — author OR owner/co-owner OR admin.
  // Mirrors the `({result, error})` record pattern used elsewhere.
  // ──────────────────────────────────────────────────────────

  /// PATCH /api/communities/:id/posts/:postId — partial edit. Pass only
  /// the fields you want to change; everything else is left untouched.
  /// Returns the updated post row (raw JSON) on success.
  static Future<({Map<String, dynamic>? post, String? error})> updatePost(
    String communityId,
    int postId, {
    String? title,
    String? body,
    String? visibility,
    List<String>? tickers,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (title != null) payload['title'] = title;
      if (body != null) payload['body'] = body;
      if (visibility != null) payload['visibility'] = visibility;
      if (tickers != null) payload['tickers'] = tickers;
      final res = await http.patch(
        Uri.parse('$_base/communities/$communityId/posts/$postId'),
        headers: await _authHeaders(),
        body: json.encode(payload),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (post: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        final err = _safeDecode(res.body)['error']?.toString() ??
            'Failed (${res.statusCode}).';
        return (post: null, error: err);
      }
      return (
        post: json.decode(res.body) as Map<String, dynamic>,
        error: null,
      );
    } catch (e) {
      return (post: null, error: 'Connection error: $e');
    }
  }

  /// PATCH /api/communities/:id/posts/:postId/hide — soft-moderation
  /// toggle. `hidden:true` hides the post from members; `false` restores.
  static Future<({bool ok, String? error})> setPostHidden(
    String communityId,
    int postId,
    bool hidden,
  ) async {
    try {
      final res = await http.patch(
        Uri.parse('$_base/communities/$communityId/posts/$postId/hide'),
        headers: await _authHeaders(),
        body: json.encode({'hidden': hidden}),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (ok: false, error: 'Session expired.');
      }
      if (res.statusCode == 200) return (ok: true, error: null);
      final err = _safeDecode(res.body)['error']?.toString() ??
          'Failed (${res.statusCode}).';
      return (ok: false, error: err);
    } catch (e) {
      return (ok: false, error: 'Connection error: $e');
    }
  }

  /// DELETE /api/communities/:id/posts/:postId — permanent removal.
  static Future<({bool ok, String? error})> deletePost(
    String communityId,
    int postId,
  ) async {
    try {
      final res = await http.delete(
        Uri.parse('$_base/communities/$communityId/posts/$postId'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (ok: false, error: 'Session expired.');
      }
      if (res.statusCode == 200) return (ok: true, error: null);
      final err = _safeDecode(res.body)['error']?.toString() ??
          'Failed (${res.statusCode}).';
      return (ok: false, error: err);
    } catch (e) {
      return (ok: false, error: 'Connection error: $e');
    }
  }

  /// GET /api/experts/:id/communities — public. Drives the
  /// "Communities" strip on the expert profile screen.
  ///
  /// Returns a List<({id, name, regionCode, tagline, memberCount})>
  /// instead of a typed Community model — these rows feed an
  /// existing community-card widget that already accepts loose JSON.
  static Future<({List<Map<String, dynamic>>? rows, String? error})>
      listCommunitiesForExpert(String expertId) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/experts/$expertId/communities'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) {
        final err = _safeDecode(res.body)['error']?.toString() ??
            'Failed (${res.statusCode}).';
        return (rows: null, error: err);
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = (body['communities'] as List<dynamic>? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      return (rows: list, error: null);
    } catch (e) {
      return (rows: null, error: 'Connection error: $e');
    }
  }

  /// GET /api/communities/:id/experts — public, no auth needed.
  /// Returns experts owner-first, then by subscriber count.
  static Future<({List<CommunityExpert>? experts, String? error})>
      listExperts(String communityId) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/communities/$communityId/experts'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) {
        final err = _safeDecode(res.body)['error']?.toString() ??
            'Failed (${res.statusCode}).';
        return (experts: null, error: err);
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = (body['experts'] as List<dynamic>? ?? [])
          .map((e) => CommunityExpert.fromJson(e as Map<String, dynamic>))
          .toList();
      return (experts: list, error: null);
    } catch (e) {
      return (experts: null, error: 'Connection error: $e');
    }
  }

  // ──────────────────────────────────────────────────────────
  // Step-19 (mig 0019, items 2.13–2.18) — community metadata
  // ──────────────────────────────────────────────────────────

  /// GET /api/communities/:id — fresh server-authoritative metadata.
  /// Used by the edit sheet to pre-fill fields and by the discovery
  /// screen → detail navigation to fetch the cover/category/tags.
  static Future<({CommunityMeta? meta, String? error})> getMeta(
    String communityId,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/communities/$communityId'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (meta: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        final err = _safeDecode(res.body)['error']?.toString() ??
            'Failed (${res.statusCode}).';
        return (meta: null, error: err);
      }
      return (
        meta: CommunityMeta.fromJson(
          json.decode(res.body) as Map<String, dynamic>,
        ),
        error: null
      );
    } catch (e) {
      return (meta: null, error: 'Connection error: $e');
    }
  }

  /// PATCH /api/communities/:id — owner-or-admin metadata update.
  /// Pass only the fields you want to change. `tags` is full-replace
  /// (pass `[]` to clear, omit to leave alone). Server returns the
  /// updated community shape.
  static Future<({CommunityMeta? meta, String? error})> update(
    String communityId, {
    String? name,
    String? tagline,
    String? description,
    String? rules,
    String? coverUrl,
    // Mig 0028 — square avatar URL. Same semantics as `coverUrl`: pass
    // null to leave untouched, "" to clear, "<url>" to set.
    String? avatarUrl,
    bool? isPublic,
    String? category,
    List<String>? tags,
    // Step-23 — paid community pricing.
    int? joinPriceMonthlyCents,
    int? joinPriceYearlyCents,
    String? priceCurrency,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (tagline != null) body['tagline'] = tagline;
      if (description != null) body['description'] = description;
      if (rules != null) body['rules'] = rules;
      if (coverUrl != null) body['coverUrl'] = coverUrl;
      if (avatarUrl != null) body['avatarUrl'] = avatarUrl;
      if (isPublic != null) body['isPublic'] = isPublic;
      if (category != null) body['category'] = category;
      if (tags != null) body['tags'] = tags;
      if (joinPriceMonthlyCents != null) {
        body['joinPriceMonthlyCents'] = joinPriceMonthlyCents;
      }
      if (joinPriceYearlyCents != null) {
        body['joinPriceYearlyCents'] = joinPriceYearlyCents;
      }
      if (priceCurrency != null) {
        body['priceCurrency'] = priceCurrency;
      }
      final res = await http.patch(
        Uri.parse('$_base/communities/$communityId'),
        headers: await _authHeaders(),
        body: json.encode(body),
      );
      if (res.statusCode == 401) {
        await Get.find<AuthController>().handleAuthFailure();
        return (meta: null, error: 'Session expired.');
      }
      if (res.statusCode != 200) {
        final err = _safeDecode(res.body)['error']?.toString() ??
            'Failed (${res.statusCode}).';
        return (meta: null, error: err);
      }
      return (
        meta: CommunityMeta.fromJson(
          json.decode(res.body) as Map<String, dynamic>,
        ),
        error: null,
      );
    } catch (e) {
      return (meta: null, error: 'Connection error: $e');
    }
  }

  /// GET /api/communities/search — discovery. Returns CommunityMeta
  /// rows so the cover / category / lock icon can render without a
  /// follow-up call.
  ///
  ///   * [query]    — free-text against name + tagline + description
  ///   * [category] — exact category match (predefined taxonomy)
  ///   * [tag]      — exact tag match
  ///   * [limit]    — server cap 100, default 20
  static Future<({List<CommunityMeta>? rows, String? error})> search({
    String? query,
    String? category,
    String? tag,
    int limit = 20,
  }) async {
    try {
      final params = <String, String>{'limit': '$limit'};
      if (query != null && query.trim().isNotEmpty) {
        params['q'] = query.trim();
      }
      if (category != null && category.isNotEmpty) {
        params['category'] = category;
      }
      if (tag != null && tag.isNotEmpty) {
        params['tag'] = tag;
      }
      final qs = Uri(queryParameters: params).query;
      final url = qs.isEmpty
          ? '$_base/communities/search'
          : '$_base/communities/search?$qs';
      final res = await http.get(
        Uri.parse(url),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) {
        final err = _safeDecode(res.body)['error']?.toString() ??
            'Failed (${res.statusCode}).';
        return (rows: null, error: err);
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = (body['communities'] as List<dynamic>? ?? [])
          .map((e) => CommunityMeta.fromJson(e as Map<String, dynamic>))
          .toList();
      return (rows: list, error: null);
    } catch (e) {
      return (rows: null, error: 'Connection error: $e');
    }
  }

  /// GET /api/communities/:id/preview — bundles community metadata,
  /// experts strip and a few sample public posts so the pre-join
  /// preview screen renders in one network call (step-23).
  ///
  /// Returns the raw decoded JSON; the screen unpacks the three keys
  /// (`community`, `experts`, `samplePosts`) itself. Keeping the
  /// service shape loose lets the screen evolve without bumping
  /// every typed model.
  static Future<({Map<String, dynamic>? data, String? error})>
      preview(String communityId) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/communities/$communityId/preview'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) {
        return (
          data: null,
          error: _safeDecode(res.body)['error']?.toString() ??
              'Preview failed (${res.statusCode}).',
        );
      }
      return (
        data: json.decode(res.body) as Map<String, dynamic>,
        error: null,
      );
    } catch (e) {
      return (data: null, error: 'Connection error: $e');
    }
  }

  /// GET /api/communities/categories — predefined taxonomy. Cheap
  /// static call (no DB hit) so we re-fetch on each discovery-screen
  /// mount rather than caching in memory.
  static Future<({List<String>? categories, String? error})>
      listCategories() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/communities/categories'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) {
        final err = _safeDecode(res.body)['error']?.toString() ??
            'Failed (${res.statusCode}).';
        return (categories: null, error: err);
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = (body['categories'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      return (categories: list, error: null);
    } catch (e) {
      return (categories: null, error: 'Connection error: $e');
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
