package repositories

import (
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// ErrStorePurchaseOwnedByAnotherUser means the store purchase was first
// verified by a different account.
var ErrStorePurchaseOwnedByAnotherUser = errors.New("store purchase belongs to another account")

// GooglePlayPurchaseRepository persists verified Google Play subscription
// purchases (mig 0061).
type GooglePlayPurchaseRepository struct {
	db *sql.DB
}

func NewGooglePlayPurchaseRepository(db *sql.DB) *GooglePlayPurchaseRepository {
	return &GooglePlayPurchaseRepository{db: db}
}

// GooglePlayPurchase is one stored purchase token.
type GooglePlayPurchase struct {
	ID                  int64
	UserID              int64
	PurchaseToken       string
	LinkedPurchaseToken string
	OrderID             string
	ProductID           string
	SubscriptionState   string
	IsTest              bool
	PurchaseDate        time.Time
	ExpiresDate         *time.Time
	RawPayload          []byte
}

// Upsert stores p, or refreshes the row for its purchase token (renewals
// keep the token). It refuses when the token, or the token it is linked
// to, belongs to another account. The checks and write run under a
// per-chain advisory lock so two accounts cannot claim it at once.
func (r *GooglePlayPurchaseRepository) Upsert(p GooglePlayPurchase) (*GooglePlayPurchase, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, fmt.Errorf("google-play upsert: begin: %w", err)
	}
	defer tx.Rollback()

	chainKey := p.PurchaseToken
	if p.LinkedPurchaseToken != "" {
		chainKey = p.LinkedPurchaseToken
	}
	if _, err := tx.Exec(`SELECT pg_advisory_xact_lock(hashtext('google_play:' || $1))`, chainKey); err != nil {
		return nil, fmt.Errorf("google-play upsert: lock: %w", err)
	}
	for _, token := range []string{p.PurchaseToken, p.LinkedPurchaseToken} {
		if err := checkPlayTokenOwner(tx, token, p.UserID); err != nil {
			return nil, err
		}
	}

	var linked any
	if p.LinkedPurchaseToken != "" {
		linked = p.LinkedPurchaseToken
	}
	err = tx.QueryRow(`
		INSERT INTO google_play_purchases
		  (user_id, purchase_token, linked_purchase_token, order_id, product_id,
		   subscription_state, is_test, purchase_date, expires_date, raw_payload)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		ON CONFLICT (purchase_token) DO UPDATE SET
		  order_id           = EXCLUDED.order_id,
		  subscription_state = EXCLUDED.subscription_state,
		  expires_date       = EXCLUDED.expires_date,
		  raw_payload        = EXCLUDED.raw_payload,
		  updated_at         = NOW()
		RETURNING id`,
		p.UserID, p.PurchaseToken, linked, p.OrderID, p.ProductID,
		p.SubscriptionState, p.IsTest, p.PurchaseDate, p.ExpiresDate, p.RawPayload,
	).Scan(&p.ID)
	if err != nil {
		return nil, fmt.Errorf("google-play upsert: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("google-play upsert: commit: %w", err)
	}
	return &p, nil
}

func checkPlayTokenOwner(tx *sql.Tx, token string, userID int64) error {
	if token == "" {
		return nil
	}
	var owner int64
	err := tx.QueryRow(`SELECT user_id FROM google_play_purchases WHERE purchase_token = $1`,
		token).Scan(&owner)
	if err == sql.ErrNoRows {
		return nil
	}
	if err != nil {
		return fmt.Errorf("google-play upsert: owner lookup: %w", err)
	}
	if owner != userID {
		return ErrStorePurchaseOwnedByAnotherUser
	}
	return nil
}
