/// One row in Sarah's bell inbox.
///
/// Type values seen today:
///   * `post_liked`        — actor liked one of my posts
///   * `post_commented`    — actor left a comment on one of my posts
class UserNotification {
  final int id;
  final int userId;
  final int? actorId;
  final String? actorName;
  final String type;
  final int? postId;
  final int? commentId;
  final String? bodySnippet;
  final DateTime? readAt;
  final DateTime createdAt;

  const UserNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.createdAt,
    this.actorId,
    this.actorName,
    this.postId,
    this.commentId,
    this.bodySnippet,
    this.readAt,
  });

  bool get unread => readAt == null;

  factory UserNotification.fromJson(Map<String, dynamic> json) =>
      UserNotification(
        id: (json['id'] as num).toInt(),
        userId: (json['userId'] as num).toInt(),
        actorId: (json['actorId'] as num?)?.toInt(),
        actorName: json['actorName'] as String?,
        type: json['type'] as String? ?? '',
        postId: (json['postId'] as num?)?.toInt(),
        commentId: (json['commentId'] as num?)?.toInt(),
        bodySnippet: json['bodySnippet'] as String?,
        readAt: DateTime.tryParse(json['readAt'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
