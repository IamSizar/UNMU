// store_access_grants.go — turns one verified store purchase of a tier
// product into access to one expert or community.
//
// A purchase is a non-renewing product (Apple) or a consumable (Google),
// so the same user can hold many at once. Each store transaction is
// recorded once in store_access_grants (UNIQUE store + transaction_ref);
// a replay is reported, never granted twice. Granting extends the active
// subscription by the plan's length (or opens a new one) and adds the
// paid price to price_cents, which payouts sum. Migration 0063.
package repositories

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"halalstocks/internal/models"
)

// Grant target types (store_access_grants.target_type).
const (
	GrantTargetExpert    = "expert"
	GrantTargetCommunity = "community"
)

// ErrGrantAlreadyApplied: this transaction already granted this user the
// same target. Safe to report success.
var ErrGrantAlreadyApplied = errors.New("store purchase already applied")

// ErrGrantUsedElsewhere: this transaction was already used by another
// user or for another target.
var ErrGrantUsedElsewhere = errors.New("store purchase already used")

// StoreGrant is one verified purchase to apply.
type StoreGrant struct {
	Store          string // "apple" | "google"
	TransactionRef string // Apple transaction_id / Google purchase token
	UserID         int64
	TargetType     string
	TargetID       string
	ProductID      string
	Plan           string // models.SubPlanMonthly | SubPlanYearly
	Days           int    // access days granted; 0 = the plan's full length
	PriceCents     int
	PaymentMethod  string // models.PaymentMethodAppleIAP | GoogleIAP
	PaymentRef     string // "apple_iap:<row id>" / "google_play:<row id>"
}

// subTable names the subscription table and target column per target
// type. Fixed strings only, never user input.
type subTable struct{ table, column string }

var grantTables = map[string]subTable{
	GrantTargetExpert:    {"expert_subscriptions", "expert_id"},
	GrantTargetCommunity: {"community_subscriptions", "community_id"},
}

// StoreAccessGrantRepository applies store purchases.
type StoreAccessGrantRepository struct{ db *sql.DB }

// NewStoreAccessGrantRepository builds the repository.
func NewStoreAccessGrantRepository(db *sql.DB) *StoreAccessGrantRepository {
	return &StoreAccessGrantRepository{db: db}
}

// Grant records the purchase and extends access, in one transaction.
// Returns the new expiry.
func (r *StoreAccessGrantRepository) Grant(ctx context.Context, g StoreGrant) (time.Time, error) {
	t, ok := grantTables[g.TargetType]
	days := g.Days
	if days <= 0 {
		days = int(models.DurationForPlan(g.Plan) / (24 * time.Hour))
	}
	if !ok || days == 0 {
		return time.Time{}, fmt.Errorf("grant: unknown target %q or plan %q", g.TargetType, g.Plan)
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return time.Time{}, fmt.Errorf("grant: begin: %w", err)
	}
	defer tx.Rollback()
	// Serialise grants for one user + target: two first purchases at once
	// would otherwise both INSERT and hit the one-active-per-pair index.
	if err := lockPair(ctx, tx, g.TargetType, g.UserID, g.TargetID); err != nil {
		return time.Time{}, err
	}
	if err := claimTransaction(ctx, tx, g); err != nil {
		return time.Time{}, err
	}
	subID, expires, err := extendOrOpen(ctx, tx, t, g, days)
	if err != nil {
		return time.Time{}, err
	}
	// Record exactly what this grant added, for refunds (mig 0064).
	if _, err := tx.ExecContext(ctx, `UPDATE store_access_grants
		SET subscription_id = $3, period_start = $4::timestamptz - make_interval(days => $5), period_end = $4
		WHERE store = $1 AND transaction_ref = $2`,
		g.Store, g.TransactionRef, subID, expires, days); err != nil {
		return time.Time{}, fmt.Errorf("grant: record period: %w", err)
	}
	if g.TargetType == GrantTargetCommunity {
		if _, err := tx.ExecContext(ctx, `INSERT INTO community_members (user_id, community_id)
			VALUES ($1, $2) ON CONFLICT DO NOTHING`, g.UserID, g.TargetID); err != nil {
			return time.Time{}, fmt.Errorf("grant: add member: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return time.Time{}, fmt.Errorf("grant: commit: %w", err)
	}
	return expires, nil
}

// claimTransaction inserts the grant row; a replay returns one of the two
// sentinel errors.
func claimTransaction(ctx context.Context, tx *sql.Tx, g StoreGrant) error {
	res, err := tx.ExecContext(ctx, `
		INSERT INTO store_access_grants
		    (store, transaction_ref, user_id, target_type, target_id, product_id, price_cents)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (store, transaction_ref) DO NOTHING`,
		g.Store, g.TransactionRef, g.UserID, g.TargetType, g.TargetID, g.ProductID, g.PriceCents)
	if err != nil {
		return fmt.Errorf("grant: record purchase: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 1 {
		return nil
	}
	var userID int64
	var targetType, targetID string
	err = tx.QueryRowContext(ctx, `SELECT user_id, target_type, target_id FROM store_access_grants
		WHERE store = $1 AND transaction_ref = $2`, g.Store, g.TransactionRef).
		Scan(&userID, &targetType, &targetID)
	if err != nil {
		return fmt.Errorf("grant: read earlier grant: %w", err)
	}
	if userID == g.UserID && targetType == g.TargetType && targetID == g.TargetID {
		return ErrGrantAlreadyApplied
	}
	return ErrGrantUsedElsewhere
}

// extendOrOpen adds the plan's days to the active subscription (from its
// expiry, or from now if that has passed) or opens a new active one.
// Returns the row id and its new expiry.
func extendOrOpen(ctx context.Context, tx *sql.Tx, t subTable, g StoreGrant, days int) (int64, time.Time, error) {
	var id int64
	var expires time.Time
	err := tx.QueryRowContext(ctx, `
		UPDATE `+t.table+`
		SET expires_at = GREATEST(COALESCE(expires_at, NOW()), NOW()) + make_interval(days => $3),
		    price_cents = price_cents + $4,
		    payment_method = $5, payment_ref = $6
		WHERE user_id = $1 AND `+t.column+` = $2 AND status = 'active'
		RETURNING id, expires_at`,
		g.UserID, g.TargetID, days, g.PriceCents, g.PaymentMethod, g.PaymentRef).Scan(&id, &expires)
	if err == nil {
		return id, expires, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return 0, time.Time{}, fmt.Errorf("grant: extend %s: %w", t.table, err)
	}
	err = tx.QueryRowContext(ctx, `
		INSERT INTO `+t.table+`
		    (user_id, `+t.column+`, plan, status, price_cents, currency,
		     payment_method, payment_ref, accepted_at, expires_at)
		VALUES ($1, $2, $3, 'active', $4, 'usd', $5, $6, NOW(), NOW() + make_interval(days => $7))
		RETURNING id, expires_at`,
		g.UserID, g.TargetID, g.Plan, g.PriceCents, g.PaymentMethod, g.PaymentRef, days).Scan(&id, &expires)
	if err != nil {
		return 0, time.Time{}, fmt.Errorf("grant: open %s: %w", t.table, err)
	}
	return id, expires, nil
}

// TargetPriceTier returns the stored id and price tier of an expert or
// community. An empty tier means the community is free. sql.ErrNoRows
// when the target does not exist.
func (r *StoreAccessGrantRepository) TargetPriceTier(ctx context.Context, targetType, targetID string) (id, tier string, err error) {
	var q string
	switch targetType {
	case GrantTargetExpert:
		q = `SELECT id, price_tier FROM experts WHERE id = $1`
	case GrantTargetCommunity:
		q = `SELECT id, COALESCE(price_tier, '') FROM communities WHERE id = $1`
	default:
		return "", "", fmt.Errorf("unknown target type %q", targetType)
	}
	err = r.db.QueryRowContext(ctx, q, targetID).Scan(&id, &tier)
	return id, tier, err
}

// lockPair serialises grants and refunds for one user + target until the
// transaction ends.
func lockPair(ctx context.Context, tx *sql.Tx, targetType string, userID int64, targetID string) error {
	if _, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`,
		fmt.Sprintf("store_grant:%s:%d:%s", targetType, userID, targetID)); err != nil {
		return fmt.Errorf("store grant lock: %w", err)
	}
	return nil
}
