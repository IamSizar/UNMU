/// One row in the unified notification inbox.
///
/// Mirrors the backend `repositories.InboxItem` shape — both the
/// `notifications` (stock) and `user_notifications` (social/sub)
/// tables fan into this single shape so the mobile inbox renders
/// without branching by table.
///
/// `source` tells the client which backend table the row originated
/// from. When marking-as-read the client posts back the same source
/// + id so the server routes the UPDATE correctly:
///
///   POST /api/me/inbox/`<source>`/`<id>`/read
class InboxItem {
  final int id;
  /// "social" | "stock". Drives the mark-read route + minor UX
  /// affordances (e.g. social rows have an actor name).
  final String source;
  /// Type taxonomy — drives the color + icon picked by the inbox
  /// screen. See `InboxKind` and `InboxKindStyle` below.
  final String kind;
  /// Title — only populated by stock-source rows. Social rows
  /// usually leave this empty and rely on actorName + body.
  final String title;
  /// Free-form body / snippet shown as the second line. Truncated
  /// server-side when very long.
  final String body;
  final int? actorId;
  /// Display name of whoever triggered the notification. Empty for
  /// stock-source rows (they have no actor).
  final String actorName;
  /// When the notification points at a specific post — drives the
  /// "tap to open" navigation in the inbox.
  final int? relatedId;
  /// When the notification points at a specific stock — drives
  /// "tap to open" navigation for stock-source rows.
  final int? stockId;
  final bool isRead;
  /// When the row was read. Null for unread rows; set the moment
  /// the user marks it read.
  final DateTime? readAt;
  final DateTime createdAt;

  const InboxItem({
    required this.id,
    required this.source,
    required this.kind,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.actorId,
    this.actorName = '',
    this.relatedId,
    this.stockId,
    this.readAt,
  });

  factory InboxItem.fromJson(Map<String, dynamic> json) {
    return InboxItem(
      id: (json['id'] as num).toInt(),
      source: json['source'] as String? ?? 'social',
      kind: json['kind'] as String? ?? 'unknown',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      actorId: (json['actorId'] as num?)?.toInt(),
      actorName: json['actorName'] as String? ?? '',
      relatedId: (json['relatedId'] as num?)?.toInt(),
      stockId: (json['stockId'] as num?)?.toInt(),
      isRead: json['isRead'] as bool? ?? false,
      readAt: json['readAt'] == null
          ? null
          : DateTime.tryParse(json['readAt'] as String),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Returns a copy with `isRead` flipped — used for the optimistic
  /// patch when the user taps a row.
  InboxItem copyMarkedRead() {
    return InboxItem(
      id: id,
      source: source,
      kind: kind,
      title: title,
      body: body,
      actorId: actorId,
      actorName: actorName,
      relatedId: relatedId,
      stockId: stockId,
      isRead: true,
      readAt: readAt ?? DateTime.now(),
      createdAt: createdAt,
    );
  }
}
