class User {
  final int id;
  final String email;
  final String? name;
  final String subscriptionTier;
  final String subscriptionStatus;

  User({
    required this.id,
    required this.email,
    this.name,
    this.subscriptionTier = 'FREE',
    this.subscriptionStatus = 'ACTIVE',
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      name: json['name'] as String?,
      subscriptionTier: json['subscription_tier'] as String? ?? 'FREE',
      subscriptionStatus: json['subscription_status'] as String? ?? 'ACTIVE',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'subscription_tier': subscriptionTier,
      'subscription_status': subscriptionStatus,
    };
  }
}
