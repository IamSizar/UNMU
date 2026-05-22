package models

import (
	"database/sql"
	"time"
)

// =============================================================================
// ExpertSubscription — one row per (user, expert, attempt). Backed by
// expert_subscriptions (migration 0007).
//
// Lifecycle:
//   pending → active → expired
//          ↘ rejected
//          ↘ cancelled
// =============================================================================

const (
	SubPlanMonthly = "monthly"
	SubPlanYearly  = "yearly"

	SubStatusPending   = "pending"
	SubStatusActive    = "active"
	SubStatusRejected  = "rejected"
	SubStatusCancelled = "cancelled"
	SubStatusExpired   = "expired"

	PaymentMethodCash      = "cash"
	PaymentMethodFIB       = "fib"
	PaymentMethodAppleIAP  = "apple_iap"  // Apple StoreKit2 verified receipt
	PaymentMethodGoogleIAP = "google_iap" // Google Play Billing (future)
)

// Aliases — historical handlers reference these without the Sub prefix.
// Kept so the IAP handler reads cleanly: PlanMonthly / PlanYearly.
const (
	PlanMonthly = SubPlanMonthly
	PlanYearly  = SubPlanYearly
)

// Default prices (USD cents). Plans are server-decided so a user can't ask
// to subscribe at a discount they invented.
const (
	PriceMonthlyCents = 1000 // $10
	PriceYearlyCents  = 9600 // $96 (20% off vs monthly × 12)
)

// PriceForPlan returns the canonical USD-cent price for a plan, or 0 if
// the plan is invalid. Use this in handlers — never trust client prices.
func PriceForPlan(plan string) int {
	switch plan {
	case SubPlanMonthly:
		return PriceMonthlyCents
	case SubPlanYearly:
		return PriceYearlyCents
	}
	return 0
}

// DurationForPlan returns the active-period length for a plan.
func DurationForPlan(plan string) time.Duration {
	switch plan {
	case SubPlanMonthly:
		return 30 * 24 * time.Hour
	case SubPlanYearly:
		return 365 * 24 * time.Hour
	}
	return 0
}

type ExpertSubscription struct {
	ID              int64      `json:"id"`
	UserID          int64      `json:"userId"`
	ExpertID        string     `json:"expertId"`
	Plan            string     `json:"plan"`
	Status          string     `json:"status"`
	PriceCents      int        `json:"priceCents"`
	Currency        string     `json:"currency"`
	PaymentMethod   string     `json:"paymentMethod"`
	PaymentRef      *string    `json:"paymentRef,omitempty"`
	// Cash-receipt image (mig 0024). Optional URL to /uploads/images/...
	// uploaded by the subscriber so the admin can verify the payment.
	ReceiptURL      *string    `json:"receiptUrl,omitempty"`
	UserNote        *string    `json:"userNote,omitempty"`
	RejectionReason *string    `json:"rejectionReason,omitempty"`
	CreatedAt       time.Time  `json:"createdAt"`
	AcceptedAt      *time.Time `json:"acceptedAt,omitempty"`
	AcceptedBy      *int64     `json:"acceptedBy,omitempty"`
	RejectedAt      *time.Time `json:"rejectedAt,omitempty"`
	CancelledAt     *time.Time `json:"cancelledAt,omitempty"`
	ExpiresAt       *time.Time `json:"expiresAt,omitempty"`

	// Joined fields populated when listing for admin dashboard.
	UserEmail     string `json:"userEmail,omitempty"`
	UserName      string `json:"userName,omitempty"`
	ExpertName    string `json:"expertName,omitempty"`
	ReviewerEmail string `json:"reviewerEmail,omitempty"`
}

// IsActiveNow returns true if the subscription is in 'active' state and not
// past its expiry. The DB doesn't auto-flip to 'expired' so callers must
// also do this check at read time.
func (s *ExpertSubscription) IsActiveNow() bool {
	if s == nil || s.Status != SubStatusActive {
		return false
	}
	if s.ExpiresAt == nil {
		return false
	}
	return s.ExpiresAt.After(time.Now())
}

type subRowScanner interface {
	Scan(dest ...any) error
}

// ScanSubscription scans columns in this exact order:
//
//	id, user_id, expert_id, plan, status, price_cents, currency,
//	payment_method, payment_ref, user_note, rejection_reason,
//	created_at, accepted_at, accepted_by, rejected_at, cancelled_at, expires_at,
//	receipt_url
func ScanSubscription(s subRowScanner) (*ExpertSubscription, error) {
	var sub ExpertSubscription
	var (
		paymentRef      sql.NullString
		userNote        sql.NullString
		rejectionReason sql.NullString
		acceptedAt      sql.NullTime
		acceptedBy      sql.NullInt64
		rejectedAt      sql.NullTime
		cancelledAt     sql.NullTime
		expiresAt       sql.NullTime
		receiptURL      sql.NullString
	)
	if err := s.Scan(
		&sub.ID, &sub.UserID, &sub.ExpertID, &sub.Plan, &sub.Status,
		&sub.PriceCents, &sub.Currency,
		&sub.PaymentMethod, &paymentRef, &userNote, &rejectionReason,
		&sub.CreatedAt, &acceptedAt, &acceptedBy, &rejectedAt, &cancelledAt, &expiresAt,
		&receiptURL,
	); err != nil {
		return nil, err
	}
	if paymentRef.Valid {
		sub.PaymentRef = &paymentRef.String
	}
	if userNote.Valid {
		sub.UserNote = &userNote.String
	}
	if rejectionReason.Valid {
		sub.RejectionReason = &rejectionReason.String
	}
	if acceptedAt.Valid {
		sub.AcceptedAt = &acceptedAt.Time
	}
	if acceptedBy.Valid {
		sub.AcceptedBy = &acceptedBy.Int64
	}
	if rejectedAt.Valid {
		sub.RejectedAt = &rejectedAt.Time
	}
	if cancelledAt.Valid {
		sub.CancelledAt = &cancelledAt.Time
	}
	if expiresAt.Valid {
		sub.ExpiresAt = &expiresAt.Time
	}
	if receiptURL.Valid {
		sub.ReceiptURL = &receiptURL.String
	}
	return &sub, nil
}
