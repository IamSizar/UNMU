/// One user who liked a post — surfaced on the post owner's
/// "Interactions" screen.
class Liker {
  final int userId;
  final String name;
  final String email;
  final String? expertId;
  final DateTime likedAt;

  const Liker({
    required this.userId,
    required this.name,
    required this.email,
    required this.likedAt,
    this.expertId,
  });

  /// Display label — falls back to the bit before "@" in the email if
  /// the user hasn't set a name.
  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (email.contains('@')) return email.split('@').first;
    return email;
  }

  bool get isExpert => (expertId ?? '').isNotEmpty;

  factory Liker.fromJson(Map<String, dynamic> json) => Liker(
        userId: (json['userId'] as num).toInt(),
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        expertId: () {
          final v = json['expertId'] as String?;
          return (v == null || v.isEmpty) ? null : v;
        }(),
        likedAt: DateTime.tryParse(json['likedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
