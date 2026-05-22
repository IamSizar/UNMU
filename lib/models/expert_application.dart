/// Status of a user's application to become an expert.
///
///   - [none]     : the user has never applied (synthetic — server returns
///                  `{ "status": "none" }` instead of an application body).
///   - [pending]  : application submitted, awaiting admin review.
///   - [approved] : admin approved — user.role flipped to EXPERT.
///   - [rejected] : admin rejected with optional reason.
enum ApplicationStatus { none, pending, approved, rejected }

extension ApplicationStatusX on ApplicationStatus {
  String get wireValue {
    switch (this) {
      case ApplicationStatus.none:
        return 'none';
      case ApplicationStatus.pending:
        return 'pending';
      case ApplicationStatus.approved:
        return 'approved';
      case ApplicationStatus.rejected:
        return 'rejected';
    }
  }

  static ApplicationStatus fromWire(String? raw) {
    switch ((raw ?? 'none').toLowerCase()) {
      case 'pending':
        return ApplicationStatus.pending;
      case 'approved':
        return ApplicationStatus.approved;
      case 'rejected':
        return ApplicationStatus.rejected;
      default:
        return ApplicationStatus.none;
    }
  }
}

/// A pending or historical request to become an expert. Backed by row in
/// `expert_applications` (backend migration 0002 + 0023).
class ExpertApplication {
  final int id;
  final int userId;
  final String fullName;
  final String expertise;
  final String bio;
  final List<String> credentials;
  final String? country;
  final List<String> sampleLinks;
  final ApplicationStatus status;
  final String? rejectionReason;
  final DateTime submittedAt;
  final DateTime? reviewedAt;

  /// Resume / credentials PDF (backend mig 0023). Null when not uploaded.
  final String? resumeUrl;

  /// Profile-picture image (backend mig 0023). Null when not uploaded.
  final String? avatarUrl;

  const ExpertApplication({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.expertise,
    required this.bio,
    required this.credentials,
    required this.sampleLinks,
    required this.status,
    required this.submittedAt,
    this.country,
    this.rejectionReason,
    this.reviewedAt,
    this.resumeUrl,
    this.avatarUrl,
  });

  factory ExpertApplication.fromJson(Map<String, dynamic> json) {
    return ExpertApplication(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      fullName: json['fullName'] as String? ?? '',
      expertise: json['expertise'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      credentials: (json['credentials'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      country: json['country'] as String?,
      sampleLinks: (json['sampleLinks'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      status: ApplicationStatusX.fromWire(json['status'] as String?),
      rejectionReason: json['rejectionReason'] as String?,
      submittedAt: DateTime.tryParse(json['submittedAt'] as String? ?? '') ??
          DateTime.now(),
      reviewedAt: json['reviewedAt'] != null
          ? DateTime.tryParse(json['reviewedAt'] as String)
          : null,
      resumeUrl: json['resumeUrl'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}
