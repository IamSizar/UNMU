// store_access_refunds.go — takes back what a refunded tier purchase
// granted. Called by the Apple refund webhook and the Google
// voided-purchases job. See docs/payments/REFUNDS_PLAN.md.
//
// Each grant recorded the subscription row it extended and the span it
// added (mig 0064). A refund removes only the part of that span not yet
// used, from that row only, and moves later purchases on the same row
// earlier by the same amount so their own refunds stay exact. The price
// always comes off the row (payouts sum price_cents).
package repositories

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// RevokeResult says what a refund changed.
type RevokeResult string

const (
	// RevokeUnknown: no grant for this transaction. Nothing changed.
	RevokeUnknown RevokeResult = "unknown"
	// RevokeAlreadyDone: already refunded. Nothing changed.
	RevokeAlreadyDone RevokeResult = "already_refunded"
	// RevokeShortened: the unused days were removed; access continues.
	RevokeShortened RevokeResult = "shortened"
	// RevokeEnded: no time was left, so the subscription was expired.
	RevokeEnded RevokeResult = "ended"
	// RevokeNoActive: marked refunded and the price removed; the paid span
	// was already used or its subscription had ended, so no days to remove.
	RevokeNoActive RevokeResult = "no_active_subscription"
)

// refundedGrant is the grant row being revoked.
type refundedGrant struct {
	id                   int64
	userID               int64
	targetType, targetID string
	priceCents           int
	subscriptionID       sql.NullInt64
	periodStart          sql.NullTime
	periodEnd            sql.NullTime
}

// unused is the part of the grant's span still ahead of now.
func (g *refundedGrant) unused(now time.Time) time.Duration {
	if !g.periodStart.Valid || !g.periodEnd.Valid {
		return 0
	}
	from := g.periodStart.Time
	if now.After(from) {
		from = now
	}
	return max(0, g.periodEnd.Time.Sub(from))
}

// Revoke applies a store refund of (store, transactionRef). Safe to call
// again for the same refund.
func (r *StoreAccessGrantRepository) Revoke(ctx context.Context, store, transactionRef string) (RevokeResult, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return "", fmt.Errorf("revoke: begin: %w", err)
	}
	defer tx.Rollback()
	g, result, err := markRefunded(ctx, tx, store, transactionRef)
	if err != nil || g == nil {
		return result, err
	}
	result, err = takeBack(ctx, tx, g)
	if err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", fmt.Errorf("revoke: commit: %w", err)
	}
	return result, nil
}

// markRefunded locks the grant (and its user + target pair, like Grant)
// and sets refunded_at. A nil grant means nothing more to do.
func markRefunded(ctx context.Context, tx *sql.Tx, store, ref string) (*refundedGrant, RevokeResult, error) {
	var g refundedGrant
	var refundedAt sql.NullTime
	err := tx.QueryRowContext(ctx, `
		SELECT id, user_id, target_type, target_id, price_cents,
		       subscription_id, period_start, period_end, refunded_at
		  FROM store_access_grants
		 WHERE store = $1 AND transaction_ref = $2
		 FOR UPDATE`, store, ref).
		Scan(&g.id, &g.userID, &g.targetType, &g.targetID, &g.priceCents,
			&g.subscriptionID, &g.periodStart, &g.periodEnd, &refundedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, RevokeUnknown, nil
	}
	if err != nil {
		return nil, "", fmt.Errorf("revoke: read grant: %w", err)
	}
	if refundedAt.Valid {
		return nil, RevokeAlreadyDone, nil
	}
	if _, ok := grantTables[g.targetType]; !ok {
		return nil, "", fmt.Errorf("revoke: unknown target type %q", g.targetType)
	}
	if err := lockPair(ctx, tx, g.targetType, g.userID, g.targetID); err != nil {
		return nil, "", err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE store_access_grants SET refunded_at = NOW() WHERE id = $1`, g.id); err != nil {
		return nil, "", fmt.Errorf("revoke: mark grant: %w", err)
	}
	return &g, "", nil
}

// takeBack removes the price and the unused span from the grant's own
// subscription row, expiring it (and the community member) when no time
// is left.
func takeBack(ctx context.Context, tx *sql.Tx, g *refundedGrant) (RevokeResult, error) {
	if !g.subscriptionID.Valid {
		return RevokeNoActive, nil
	}
	t := grantTables[g.targetType]
	var status string
	var expires sql.NullTime
	var dbNow time.Time // the transaction's NOW(), so "no time left" is exact
	err := tx.QueryRowContext(ctx, `SELECT status, expires_at, NOW() FROM `+t.table+` WHERE id = $1 FOR UPDATE`,
		g.subscriptionID.Int64).Scan(&status, &expires, &dbNow)
	if errors.Is(err, sql.ErrNoRows) {
		return RevokeNoActive, nil
	}
	if err != nil {
		return "", fmt.Errorf("revoke: read %s: %w", t.table, err)
	}
	secs := 0.0
	if unused := g.unused(dbNow); status == "active" && expires.Valid && unused > 0 {
		secs = unused.Seconds()
	}
	err = tx.QueryRowContext(ctx, `
		UPDATE `+t.table+`
		   SET price_cents = GREATEST(price_cents - $2, 0),
		       expires_at  = expires_at - make_interval(secs => $3),
		       status      = CASE WHEN $3 > 0 AND expires_at - make_interval(secs => $3) <= NOW()
		                          THEN 'expired' ELSE status END
		 WHERE id = $1
		RETURNING status`, g.subscriptionID.Int64, g.priceCents, secs).Scan(&status)
	if err != nil {
		return "", fmt.Errorf("revoke: shorten %s: %w", t.table, err)
	}
	if secs == 0 {
		return RevokeNoActive, nil
	}
	if err := shiftLaterGrants(ctx, tx, g, secs); err != nil {
		return "", err
	}
	if status != "expired" {
		return RevokeShortened, nil
	}
	return RevokeEnded, removeCommunityMember(ctx, tx, g)
}

// removeCommunityMember drops the membership of an ended community
// subscription, as the normal expiry does.
func removeCommunityMember(ctx context.Context, tx *sql.Tx, g *refundedGrant) error {
	if g.targetType != GrantTargetCommunity {
		return nil
	}
	_, err := tx.ExecContext(ctx, `DELETE FROM community_members
		WHERE user_id = $1 AND community_id = $2`, g.userID, g.targetID)
	if err != nil {
		return fmt.Errorf("revoke: remove member: %w", err)
	}
	return nil
}

// shiftLaterGrants moves the spans of purchases stacked after the refunded
// one on the same row earlier by the removed time.
func shiftLaterGrants(ctx context.Context, tx *sql.Tx, g *refundedGrant, secs float64) error {
	_, err := tx.ExecContext(ctx, `
		UPDATE store_access_grants
		   SET period_start = period_start - make_interval(secs => $4),
		       period_end   = period_end   - make_interval(secs => $4)
		 WHERE target_type = $1 AND subscription_id = $2 AND id <> $3
		   AND refunded_at IS NULL AND period_start >= $5`,
		g.targetType, g.subscriptionID.Int64, g.id, secs, g.periodEnd.Time)
	if err != nil {
		return fmt.Errorf("revoke: shift later grants: %w", err)
	}
	return nil
}
