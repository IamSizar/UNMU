// =============================================================================
// community_directory.dart — real community lookups for UI that only has an id.
//
// Several widgets (source badge, message banner, post composer) used to find
// a community by searching the hard-coded sample list in mock_social_data.
// Any community not in that list (every one an admin creates) was treated as
// "unavailable": the badge refused to open it, the banner showed a generic
// name, and experts could not post to it. They now ask the backend.
// =============================================================================
import 'package:flutter/foundation.dart';

import '../../services/community_service.dart';
import 'mock_social_data.dart';

/// Adapts a backend community row to the UI's [Community] model. Decorative
/// fields the backend has no data for (tickers, chat, posts, reels, videos)
/// stay empty; the screens render them conditionally.
Community communityFromMeta(CommunityMeta m) => Community(
  id: m.id,
  name: m.name,
  tagline: m.tagline,
  regionCode: m.regionCode,
  memberCount: m.memberCount,
  activeNow: 0, // not shown from the backend yet; matches the hub

  liveTickers: const [],
  chatMessages: const [],
  posts: const [],
  reels: const [],
  videos: const [],
  ownerId: m.ownerId,
  coverUrl: m.coverUrl,
  avatarUrl: m.avatarUrl,
);

/// Looks communities up by id through `GET /api/communities/:id`, caching
/// hits for the app session. A miss (hidden, removed, or a network error)
/// is not cached, so a later lookup can succeed.
class CommunityDirectory {
  CommunityDirectory._();

  static final Map<String, Community> _cache = {};

  /// Replaceable in tests; defaults to the real backend call.
  @visibleForTesting
  static Future<CommunityMeta?> Function(String id) fetch = _fetchFromApi;

  static Future<CommunityMeta?> _fetchFromApi(String id) async =>
      (await CommunityService.getMeta(id)).meta;

  /// The community with [id], or null when it does not exist (or could not
  /// be loaded right now).
  static Future<Community?> find(String id) async {
    if (id.isEmpty) return null;
    final cached = _cache[id];
    if (cached != null) return cached;
    final meta = await fetch(id);
    if (meta == null) return null;
    return _cache[id] = communityFromMeta(meta);
  }

  /// Forgets cached communities (e.g. after an admin edits one).
  static void clear() => _cache.clear();
}
