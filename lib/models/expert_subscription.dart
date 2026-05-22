/// Plan choice — fixed by the server. Monthly = $10, Yearly = $96.
enum SubPlan { monthly, yearly }

extension SubPlanX on SubPlan {
  String get wireValue {
    switch (this) {
      case SubPlan.monthly: return 'monthly';
      case SubPlan.yearly:  return 'yearly';
    }
  }

  String get label {
    switch (this) {
      case SubPlan.monthly: return 'Monthly';
      case SubPlan.yearly:  return 'Yearly';
    }
  }

  /// Canonical price in USD cents. Mirrors backend `models.PriceForPlan`.
  int get priceCents {
    switch (this) {
      case SubPlan.monthly: return 1000;
      case SubPlan.yearly:  return 9600;
    }
  }

  /// "$10" / "$96"
  String get priceLabel => '\$${(priceCents / 100).toStringAsFixed(0)}';

  /// Days the subscription stays active after acceptance.
  int get durationDays {
    switch (this) {
      case SubPlan.monthly: return 30;
      case SubPlan.yearly:  return 365;
    }
  }

  static SubPlan fromWire(String? raw) {
    switch ((raw ?? 'monthly').toLowerCase()) {
      case 'yearly': return SubPlan.yearly;
      default:       return SubPlan.monthly;
    }
  }
}

/// Lifecycle of a subscription request.
enum SubStatus { pending, active, rejected, cancelled, expired }

extension SubStatusX on SubStatus {
  String get wireValue {
    switch (this) {
      case SubStatus.pending:   return 'pending';
      case SubStatus.active:    return 'active';
      case SubStatus.rejected:  return 'rejected';
      case SubStatus.cancelled: return 'cancelled';
      case SubStatus.expired:   return 'expired';
    }
  }

  static SubStatus fromWire(String? raw) {
    switch ((raw ?? 'pending').toLowerCase()) {
      case 'active':    return SubStatus.active;
      case 'rejected':  return SubStatus.rejected;
      case 'cancelled': return SubStatus.cancelled;
      case 'expired':   return SubStatus.expired;
      default:          return SubStatus.pending;
    }
  }
}

/// Payment method picked by the user when submitting a subscription.
///   * cash       — pay admin in person
///   * fib        — First Iraqi Bank transfer (paymentRef = transaction id)
///   * appleIap   — Apple StoreKit (auto-verified via /me/iap/apple/verify)
///   * googleIap  — Google Play Billing (Phase 2.4+, not yet wired here)
enum PaymentMethod { cash, fib, appleIap, googleIap }

extension PaymentMethodX on PaymentMethod {
  String get wireValue {
    switch (this) {
      case PaymentMethod.cash:      return 'cash';
      case PaymentMethod.fib:       return 'fib';
      case PaymentMethod.appleIap:  return 'apple_iap';
      case PaymentMethod.googleIap: return 'google_iap';
    }
  }

  String get label {
    switch (this) {
      case PaymentMethod.cash:      return 'Cash';
      case PaymentMethod.fib:       return 'FIB';
      case PaymentMethod.appleIap:  return 'Apple Pay';
      case PaymentMethod.googleIap: return 'Google Play';
    }
  }

  static PaymentMethod fromWire(String? raw) {
    switch ((raw ?? 'cash').toLowerCase()) {
      case 'fib':        return PaymentMethod.fib;
      case 'apple_iap':  return PaymentMethod.appleIap;
      case 'google_iap': return PaymentMethod.googleIap;
      default:           return PaymentMethod.cash;
    }
  }
}

/// One row from `expert_subscriptions`.
class ExpertSubscription {
  final int id;
  final int userId;
  final String expertId;
  final SubPlan plan;
  final SubStatus status;
  final int priceCents;
  final String currency;
  final PaymentMethod paymentMethod;
  final String? paymentRef;
  /// Cash-receipt image URL (mig 0024). Null when not uploaded.
  final String? receiptUrl;
  final String? userNote;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final int? acceptedBy;
  final DateTime? rejectedAt;
  final DateTime? cancelledAt;
  final DateTime? expiresAt;

  // Optional joined fields surfaced by the admin list endpoint.
  final String? userEmail;
  final String? userName;
  final String? expertName;

  const ExpertSubscription({
    required this.id,
    required this.userId,
    required this.expertId,
    required this.plan,
    required this.status,
    required this.priceCents,
    required this.currency,
    required this.paymentMethod,
    required this.createdAt,
    this.paymentRef,
    this.receiptUrl,
    this.userNote,
    this.rejectionReason,
    this.acceptedAt,
    this.acceptedBy,
    this.rejectedAt,
    this.cancelledAt,
    this.expiresAt,
    this.userEmail,
    this.userName,
    this.expertName,
  });

  /// True when this subscription is currently active (status + not expired).
  bool get isActiveNow {
    if (status != SubStatus.active) return false;
    final exp = expiresAt;
    if (exp == null) return false;
    return exp.isAfter(DateTime.now());
  }

  /// Days remaining until expiry — null when not active.
  int? get daysRemaining {
    if (!isActiveNow) return null;
    return expiresAt!.difference(DateTime.now()).inDays;
  }

  /// "$10.00" — formatted from priceCents.
  String get priceLabel {
    final dollars = priceCents / 100;
    return '\$${dollars.toStringAsFixed(dollars.truncateToDouble() == dollars ? 0 : 2)}';
  }

  factory ExpertSubscription.fromJson(Map<String, dynamic> json) =>
      ExpertSubscription(
        id: (json['id'] as num).toInt(),
        userId: (json['userId'] as num).toInt(),
        expertId: json['expertId'] as String? ?? '',
        plan: SubPlanX.fromWire(json['plan'] as String?),
        status: SubStatusX.fromWire(json['status'] as String?),
        priceCents: (json['priceCents'] as num?)?.toInt() ?? 0,
        currency: json['currency'] as String? ?? 'USD',
        paymentMethod: PaymentMethodX.fromWire(json['paymentMethod'] as String?),
        paymentRef: json['paymentRef'] as String?,
        receiptUrl: json['receiptUrl'] as String?,
        userNote: json['userNote'] as String?,
        rejectionReason: json['rejectionReason'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        acceptedAt: _parseDate(json['acceptedAt']),
        acceptedBy: (json['acceptedBy'] as num?)?.toInt(),
        rejectedAt: _parseDate(json['rejectedAt']),
        cancelledAt: _parseDate(json['cancelledAt']),
        expiresAt: _parseDate(json['expiresAt']),
        userEmail: json['userEmail'] as String?,
        userName: json['userName'] as String?,
        expertName: json['expertName'] as String?,
      );

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String && v.isEmpty) return null;
    return DateTime.tryParse(v.toString());
  }
}
