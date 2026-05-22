/// One row in the comments thread of a post. Mirrors the Go
/// `models.PostComment` struct.
class PostComment {
  final int id;
  final int postId;
  final int authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;

  /// Non-null when the author has edited the body since posting (mig 0037).
  /// Render "(edited)" next to the timestamp in the UI to be transparent
  /// about modifications.
  final DateTime? editedAt;

  const PostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
    this.editedAt,
  });

  bool get wasEdited => editedAt != null;

  factory PostComment.fromJson(Map<String, dynamic> json) => PostComment(
        id: (json['id'] as num).toInt(),
        postId: (json['postId'] as num?)?.toInt() ?? 0,
        authorId: (json['authorId'] as num?)?.toInt() ?? 0,
        authorName: json['authorName'] as String? ?? '',
        body: json['body'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        editedAt: json['editedAt'] != null
            ? DateTime.tryParse(json['editedAt'] as String)
            : null,
      );
}
