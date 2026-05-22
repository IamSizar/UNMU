/// Status returned by the backend for a community proposal.
///
/// Maps 1:1 to the `status` column on `community_proposals`. Anything we
/// don't recognise falls back to [unknown] so the UI can still render a
/// neutral chip without crashing.
enum ProposalStatus { pending, approved, rejected, unknown }

extension ProposalStatusX on ProposalStatus {
  String get wire => switch (this) {
        ProposalStatus.pending => 'pending',
        ProposalStatus.approved => 'approved',
        ProposalStatus.rejected => 'rejected',
        ProposalStatus.unknown => 'unknown',
      };

  String get label => switch (this) {
        ProposalStatus.pending => 'PENDING REVIEW',
        ProposalStatus.approved => 'APPROVED',
        ProposalStatus.rejected => 'REJECTED',
        ProposalStatus.unknown => 'UNKNOWN',
      };

  static ProposalStatus fromWire(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'pending':
        return ProposalStatus.pending;
      case 'approved':
        return ProposalStatus.approved;
      case 'rejected':
        return ProposalStatus.rejected;
      default:
        return ProposalStatus.unknown;
    }
  }
}

/// A row from `/api/me/community-proposals` (and the admin variants).
///
/// Mirrors the backend `CommunityProposal` struct in
/// `backend/internal/repositories/community_proposals.go`. Only the fields
/// the mobile UI actually reads are kept here — admin-only fields like
/// `reviewedBy` are left as their raw int so we don't have to ship a
/// separate "admin proposal" model.
class CommunityProposal {
  final int id;
  final int userId;
  final String name;
  final String regionCode;
  final String description;
  final ProposalStatus status;

  /// Filled by the backend when status == rejected. Empty for pending /
  /// approved rows.
  final String rejectionReason;

  final DateTime submittedAt;
  final DateTime? reviewedAt;

  /// Filled when status == approved — the new community's id, so the UI
  /// can deep-link straight into the community detail screen.
  final String approvedCommunityId;

  const CommunityProposal({
    required this.id,
    required this.userId,
    required this.name,
    required this.regionCode,
    required this.description,
    required this.status,
    required this.rejectionReason,
    required this.submittedAt,
    required this.reviewedAt,
    required this.approvedCommunityId,
  });

  factory CommunityProposal.fromJson(Map<String, dynamic> j) {
    return CommunityProposal(
      id: (j['id'] as num).toInt(),
      userId: (j['userId'] as num?)?.toInt() ?? 0,
      name: (j['name'] as String?) ?? '',
      regionCode: (j['regionCode'] as String?) ?? '',
      description: (j['description'] as String?) ?? '',
      status: ProposalStatusX.fromWire(j['status'] as String?),
      rejectionReason: (j['rejectionReason'] as String?) ?? '',
      submittedAt: DateTime.tryParse(j['submittedAt'] as String? ?? '') ??
          DateTime.now(),
      reviewedAt: j['reviewedAt'] == null
          ? null
          : DateTime.tryParse(j['reviewedAt'] as String),
      approvedCommunityId: (j['approvedCommunityId'] as String?) ?? '',
    );
  }
}
