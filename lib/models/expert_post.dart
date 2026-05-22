import '../config/api_config.dart';

/// Resolve a media URL into an absolute URL the platform can fetch.
///
/// Handles three shapes:
///   * `null` / empty           → returns null.
///   * `http://localhost:8080/uploads/...` or `http://127.0.0.1:8080/...`
///                              → swaps the broken host for the current
///                                ApiConfig origin so legacy DB rows from
///                                an earlier dev IP still load on real
///                                devices.
///   * `/uploads/foo.mp4`       → prepends current ApiConfig origin.
///   * `https://example.com/x`  → returned unchanged.
String? resolveUrl(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // Drop the broken host part — anything that follows is treated as a
  // relative path and reattached to the current origin.
  String relative;
  if (trimmed.startsWith('http://localhost') ||
      trimmed.startsWith('http://127.0.0.1')) {
    final i = trimmed.indexOf('/', 'http://'.length);
    relative = i >= 0 ? trimmed.substring(i) : '/';
  } else if (trimmed.startsWith('/')) {
    relative = trimmed;
  } else {
    // Anything else (https external CDN, S3, etc.) — pass through.
    return trimmed;
  }

  final base = ApiConfig.baseUrl;
  final apiIdx = base.indexOf('/api');
  final origin = apiIdx > 0 ? base.substring(0, apiIdx) : base;
  return '$origin$relative';
}

/// Type of expert post — drives which composer fields are required and which
/// player UI is used to consume it.
enum PostType { article, video, reel }

extension PostTypeX on PostType {
  String get wireValue {
    switch (this) {
      case PostType.article:
        return 'article';
      case PostType.video:
        return 'video';
      case PostType.reel:
        return 'reel';
    }
  }

  String get displayName {
    switch (this) {
      case PostType.article:
        return 'Article';
      case PostType.video:
        return 'Video';
      case PostType.reel:
        return 'Reel';
    }
  }

  static PostType fromWire(String? raw) {
    switch ((raw ?? 'article').toLowerCase()) {
      case 'video':
        return PostType.video;
      case 'reel':
        return PostType.reel;
      default:
        return PostType.article;
    }
  }
}

/// Status of a post (mig 0020, item 4.15) — drafts and scheduled posts
/// are hidden from public lists; only `published` rows reach feeds.
enum PostStatus { draft, scheduled, published }

extension PostStatusX on PostStatus {
  String get wireValue {
    switch (this) {
      case PostStatus.draft:
        return 'draft';
      case PostStatus.scheduled:
        return 'scheduled';
      case PostStatus.published:
        return 'published';
    }
  }

  String get displayName {
    switch (this) {
      case PostStatus.draft:
        return 'Draft';
      case PostStatus.scheduled:
        return 'Scheduled';
      case PostStatus.published:
        return 'Published';
    }
  }

  static PostStatus fromWire(String? raw) {
    switch ((raw ?? 'published').toLowerCase()) {
      case 'draft':
        return PostStatus.draft;
      case 'scheduled':
        return PostStatus.scheduled;
      default:
        return PostStatus.published;
    }
  }
}

/// One inline image attached to an article (mig 0020, item 4.18).
/// Embedded into the article body via the markdown renderer's image
/// resolver — the body itself doesn't carry image markdown, the
/// composer appends a horizontal gallery underneath.
class PostAttachment {
  final int id;
  final String url; // absolute, resolved via resolveUrl()
  final int sortOrder;
  const PostAttachment({
    required this.id,
    required this.url,
    required this.sortOrder,
  });
  factory PostAttachment.fromJson(Map<String, dynamic> json) =>
      PostAttachment(
        id: (json['id'] as num?)?.toInt() ?? 0,
        url: resolveUrl(json['url'] as String?) ?? '',
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

/// Visibility of a post — `public` is a teaser anyone can read, `subscribers`
/// is gated and only paid subscribers (or the owner) see the body.
enum PostVisibility { public, subscribersOnly }

extension PostVisibilityX on PostVisibility {
  String get wireValue {
    switch (this) {
      case PostVisibility.public:
        return 'public';
      case PostVisibility.subscribersOnly:
        return 'subscribers_only';
    }
  }

  String get displayName {
    switch (this) {
      case PostVisibility.public:
        return 'Public';
      case PostVisibility.subscribersOnly:
        return 'Subscribers only';
    }
  }

  static PostVisibility fromWire(String? raw) {
    switch ((raw ?? 'subscribers_only').toLowerCase()) {
      case 'public':
        return PostVisibility.public;
      default:
        return PostVisibility.subscribersOnly;
    }
  }
}

/// One post on an expert's profile. Mirrors the Go `models.Post` struct for
/// expert-targeted rows.
///
/// When [isLocked] is true, the server has already stripped [body],
/// [mediaUrl], and [tickers] for non-subscribers — only [title], [coverUrl],
/// metadata + counts come through, and the UI should show a paywall card.
class ExpertPost {
  final int id;
  final String expertId;
  final int authorId;
  final String authorName;
  final PostType postType;
  /// Source-attribution fields, denormalized from the backend so a
  /// "from ..." badge can render without a follow-up call. Exactly
  /// one pair is populated:
  ///
  ///   targetType == 'community' → communityId, communityName,
  ///                                communityRegionCode set
  ///   targetType == 'expert'    → expertName set (display name of
  ///                                the expert profile that owns
  ///                                the post; usually equal to
  ///                                authorName but kept distinct
  ///                                for cross-post safety)
  ///
  /// All five default to empty when the backend doesn't surface
  /// them — older mock-only paths still work.
  final String targetType;
  final String? communityId;
  final String communityName;
  final String communityRegionCode;
  final String expertName;
  final String? title;
  final String body;
  final String? mediaUrl;
  final String? coverUrl;
  final int? durationSeconds;
  final List<String> tickers;
  final PostVisibility visibility;
  final int upvotes;
  final int likes;
  final int comments;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isLocked;
  final bool isHidden;
  /// Whether the current viewer has liked this post — driven by the
  /// backend's `liked` field, filled per-request from post_likes. Used as
  /// the initial state for the heart button; LikeButton owns mutable
  /// "is liked right now" via local State.
  final bool liked;
  /// Whether the current viewer has bookmarked this post. Same pattern
  /// as [liked] — filled by the backend, used as initial state for the
  /// SaveButton; SavedController is the live source of truth across
  /// screens after the user toggles.
  final bool saved;

  /// Step-20 (mig 0020, item 4.15) — drafts + scheduling.
  ///   * status: draft / scheduled / published
  ///   * publishAt: future timestamp when status == scheduled,
  ///                otherwise null.
  final PostStatus status;
  final DateTime? publishAt;

  /// Step-20 (mig 0020, item 4.18) — inline image attachments. Always
  /// non-null; empty when there are none.
  final List<PostAttachment> attachments;

  /// True when this post was created on an expert's personal
  /// profile (target=expert). False = community-sourced.
  bool get isFromExpertProfile =>
      targetType == 'expert' || (targetType.isEmpty && expertId.isNotEmpty);

  /// True when this post was created inside a community
  /// (target=community). Used by the source-badge UI.
  bool get isFromCommunity =>
      targetType == 'community' ||
      (communityId != null && communityId!.isNotEmpty);

  const ExpertPost({
    required this.id,
    required this.expertId,
    required this.authorId,
    required this.authorName,
    required this.postType,
    required this.body,
    required this.tickers,
    required this.visibility,
    required this.upvotes,
    required this.likes,
    required this.comments,
    required this.createdAt,
    required this.isLocked,
    this.isHidden = false,
    this.liked = false,
    this.saved = false,
    this.updatedAt,
    this.title,
    this.mediaUrl,
    this.coverUrl,
    this.durationSeconds,
    this.targetType = '',
    this.communityId,
    this.communityName = '',
    this.communityRegionCode = '',
    this.expertName = '',
    this.status = PostStatus.published,
    this.publishAt,
    this.attachments = const [],
  });

  factory ExpertPost.fromJson(Map<String, dynamic> json) {
    return ExpertPost(
      id: (json['id'] as num).toInt(),
      expertId: json['expertId'] as String? ?? '',
      authorId: (json['authorId'] as num?)?.toInt() ?? 0,
      authorName: json['authorName'] as String? ?? '',
      postType: PostTypeX.fromWire(json['postType'] as String?),
      title: json['title'] as String?,
      body: json['body'] as String? ?? '',
      // Media URLs may arrive as: (a) absolute https:// (external CDN), (b)
      // relative `/uploads/...` (our backend, portable across IP changes),
      // (c) legacy `http://localhost:8080/...` from old uploads. resolveUrl
      // normalises all three to an absolute URL using the current
      // ApiConfig.baseUrl origin.
      mediaUrl: resolveUrl(json['mediaUrl'] as String?),
      coverUrl: resolveUrl(json['coverUrl'] as String?),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      tickers: (json['tickers'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      visibility: PostVisibilityX.fromWire(json['visibility'] as String?),
      upvotes: (json['upvotes'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      comments: (json['comments'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      isLocked: json['isLocked'] as bool? ?? false,
      isHidden: json['isHidden'] as bool? ?? false,
      liked: json['liked'] as bool? ?? false,
      saved: json['saved'] as bool? ?? false,
      targetType: json['targetType'] as String? ?? '',
      communityId: json['communityId'] as String?,
      communityName: json['communityName'] as String? ?? '',
      communityRegionCode: json['communityRegionCode'] as String? ?? '',
      expertName: json['expertName'] as String? ?? '',
      status: PostStatusX.fromWire(json['status'] as String?),
      publishAt: json['publishAt'] == null
          ? null
          : DateTime.tryParse(json['publishAt'] as String),
      attachments: ((json['attachments'] as List<dynamic>?) ?? const [])
          .map((e) => PostAttachment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// True iff this post has been edited at least once after creation.
  /// Drives the "Edited Xm ago" pill on the detail screen — the pill
  /// links to the post-history sheet (mig 0020, item 4.16).
  bool get wasEdited =>
      updatedAt != null &&
      updatedAt!.difference(createdAt).inSeconds > 1;
}

/// One snapshot row from `post_versions` (mig 0020, item 4.16).
/// Returned by `/posts/:id/history` — owner + admin only.
class PostVersion {
  final int id;
  final int postId;
  final int? editorId;
  final String title;
  final String body;
  final List<String> tickers;
  final DateTime editedAt;
  const PostVersion({
    required this.id,
    required this.postId,
    required this.editorId,
    required this.title,
    required this.body,
    required this.tickers,
    required this.editedAt,
  });
  factory PostVersion.fromJson(Map<String, dynamic> json) => PostVersion(
        id: (json['id'] as num).toInt(),
        postId: (json['postId'] as num).toInt(),
        editorId: (json['editorId'] as num?)?.toInt(),
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        tickers: ((json['tickers'] as List<dynamic>?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        editedAt: DateTime.tryParse(json['editedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
