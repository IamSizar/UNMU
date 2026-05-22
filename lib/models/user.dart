/// Account type for an UNMU user.
///
///   - [user]    : default — joins communities, follows experts, posts in
///                 communities, browses content. No expert profile.
///   - [expert]  : verified analyst (cyan ✓ badge). Owns one expert profile
///                 (linked via [User.expertId]) where they post research.
///   - [admin]   : platform staff. Full powers across the dashboard.
///
/// SCHOLAR was retired in migration 0013 — all former scholars are now
/// EXPERTs. The fromWire() switch maps any legacy "SCHOLAR" string from
/// an older client / cached session back to [expert] so the app
/// continues working during the rollout.
enum UserRole { user, expert, admin }

extension UserRoleX on UserRole {
  String get wireValue {
    switch (this) {
      case UserRole.user:
        return 'USER';
      case UserRole.expert:
        return 'EXPERT';
      case UserRole.admin:
        return 'ADMIN';
    }
  }

  static UserRole fromWire(String? raw) {
    switch ((raw ?? 'USER').toUpperCase()) {
      case 'EXPERT':
        return UserRole.expert;
      // Legacy "SCHOLAR" strings (from older clients or cached sessions)
      // resolve to expert so the role-removal migration is forward-
      // compatible without forcing a logout for every existing user.
      case 'SCHOLAR':
        return UserRole.expert;
      case 'ADMIN':
        return UserRole.admin;
      default:
        return UserRole.user;
    }
  }
}

class User {
  final int id;
  final String email;
  final String? name;
  final String subscriptionTier;
  final String subscriptionStatus;

  /// Account type. Drives what UI / actions are available.
  final UserRole role;

  /// If the user is an expert, this links to the expert profile in
  /// the experts table (or in mock data, to MockSocialData.experts[i].id).
  /// Null for regular users.
  final String? expertId;

  /// Backend-persisted avatar URL (mig 0038). Populated by
  /// PATCH /me/profile. Null until the user uploads one — the UI
  /// falls back to a gradient + initials when missing.
  final String? avatarUrl;

  User({
    required this.id,
    required this.email,
    this.name,
    this.subscriptionTier = 'FREE',
    this.subscriptionStatus = 'ACTIVE',
    this.role = UserRole.user,
    this.expertId,
    this.avatarUrl,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    // Backend ships camelCase (subscriptionTier, expertId). Older locally
    // persisted sessions used snake_case — accept both so we don't lose the
    // session after upgrading.
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      name: json['name'] as String?,
      subscriptionTier: (json['subscriptionTier'] ??
              json['subscription_tier']) as String? ??
          'FREE',
      subscriptionStatus: (json['subscriptionStatus'] ??
              json['subscription_status']) as String? ??
          'ACTIVE',
      role: UserRoleX.fromWire(json['role'] as String?),
      expertId: (json['expertId'] ?? json['expert_id']) as String?,
      avatarUrl: (json['avatarUrl'] ?? json['avatar_url']) as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'subscription_tier': subscriptionTier,
      'subscription_status': subscriptionStatus,
      'role': role.wireValue,
      'expert_id': expertId,
      'avatar_url': avatarUrl,
    };
  }

  User copyWith({
    int? id,
    String? email,
    String? name,
    String? subscriptionTier,
    String? subscriptionStatus,
    UserRole? role,
    String? expertId,
    String? avatarUrl,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      subscriptionTier: subscriptionTier ?? this.subscriptionTier,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      role: role ?? this.role,
      expertId: expertId ?? this.expertId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  bool get isExpert => role == UserRole.expert;
}
