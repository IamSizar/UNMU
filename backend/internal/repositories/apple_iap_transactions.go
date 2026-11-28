package repositories

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

// AppleIAPTransactionRepository persists verified Apple IAP transactions
// (mig 0035). Idempotency guard is on transaction_id — if the client
// re-submits a receipt we've already validated, we return the existing
// row instead of erroring.
type AppleIAPTransactionRepository struct {
	db *sql.DB
}

func NewAppleIAPTransactionRepository(db *sql.DB) *AppleIAPTransactionRepository {
	return &AppleIAPTransactionRepository{db: db}
}

type AppleIAPTransaction struct {
	ID                    int64           `json:"id"`
	UserID                int64           `json:"userId"`
	TransactionID         string          `json:"transactionId"`
	OriginalTransactionID string          `json:"originalTransactionId"`
	ProductID             string          `json:"productId"`
	Environment           string          `json:"environment"`
	PurchaseDate          time.Time       `json:"purchaseDate"`
	ExpiresDate           *time.Time      `json:"expiresDate,omitempty"`
	RawPayload            json.RawMessage `json:"rawPayload,omitempty"`
	CreatedAt             time.Time       `json:"createdAt"`
}

// ErrAppleSubOwnedByAnotherUser means the Apple subscription (its
// original_transaction_id) was first verified by a different account.
var ErrAppleSubOwnedByAnotherUser = errors.New("apple-iap: subscription belongs to another account")

// Upsert inserts a new transaction row, or returns the existing one
// when transaction_id already exists (replay → idempotent). Returns the
// resulting row and whether it was newly inserted.
//
// A subscription belongs to the first account that verified it. Every
// renewal has a new transaction_id but the same original_transaction_id,
// so ownership is checked on original_transaction_id; otherwise another
// account could claim a renewal of someone else's subscription. The check
// and insert run under a per-subscription advisory lock so two accounts
// cannot both claim it at the same moment.
func (r *AppleIAPTransactionRepository) Upsert(
	userID int64,
	transactionID, originalTransactionID, productID, environment string,
	purchaseDate time.Time,
	expiresDate *time.Time,
	rawPayload []byte,
) (*AppleIAPTransaction, bool, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, false, fmt.Errorf("apple-iap upsert: begin: %w", err)
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`SELECT pg_advisory_xact_lock(hashtext('apple_iap:' || $1))`,
		originalTransactionID); err != nil {
		return nil, false, fmt.Errorf("apple-iap upsert: lock: %w", err)
	}
	if err := checkSubOwner(tx, originalTransactionID, userID); err != nil {
		return nil, false, err
	}

	row := tx.QueryRow(`
		INSERT INTO apple_iap_transactions (
			user_id, transaction_id, original_transaction_id, product_id,
			environment, purchase_date, expires_date, raw_payload
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (transaction_id) DO NOTHING
		RETURNING `+appleTxColumns, userID, transactionID, originalTransactionID, productID,
		environment, purchaseDate, expiresDate, rawPayload)
	t, err := scanAppleTx(row)
	inserted := err == nil
	if err == sql.ErrNoRows {
		// transaction_id already stored: return that row (idempotent replay).
		t, err = scanAppleTx(tx.QueryRow(`SELECT `+appleTxColumns+`
			FROM apple_iap_transactions WHERE transaction_id = $1`, transactionID))
	}
	if err != nil {
		return nil, false, fmt.Errorf("apple-iap upsert: %w", err)
	}
	if t.UserID != userID {
		return nil, false, ErrAppleSubOwnedByAnotherUser
	}
	if err := tx.Commit(); err != nil {
		return nil, false, fmt.Errorf("apple-iap upsert: commit: %w", err)
	}
	return t, inserted, nil
}

// checkSubOwner fails when the subscription was first verified by another
// account. Older data may already hold several owners; the earliest wins.
func checkSubOwner(tx *sql.Tx, originalTransactionID string, userID int64) error {
	var owner int64
	err := tx.QueryRow(`
		SELECT user_id FROM apple_iap_transactions
		WHERE original_transaction_id = $1
		ORDER BY created_at, id LIMIT 1`, originalTransactionID).Scan(&owner)
	if err == sql.ErrNoRows {
		return nil
	}
	if err != nil {
		return fmt.Errorf("apple-iap upsert: owner lookup: %w", err)
	}
	if owner != userID {
		return ErrAppleSubOwnedByAnotherUser
	}
	return nil
}

const appleTxColumns = `id, user_id, transaction_id, original_transaction_id,
		          product_id, environment, purchase_date, expires_date,
		          raw_payload, created_at`

func scanAppleTx(row *sql.Row) (*AppleIAPTransaction, error) {
	var t AppleIAPTransaction
	var rawJSON []byte
	if err := row.Scan(
		&t.ID, &t.UserID, &t.TransactionID, &t.OriginalTransactionID,
		&t.ProductID, &t.Environment, &t.PurchaseDate, &t.ExpiresDate,
		&rawJSON, &t.CreatedAt,
	); err != nil {
		return nil, err
	}
	t.RawPayload = rawJSON
	return &t, nil
}

func (r *AppleIAPTransactionRepository) GetByTransactionID(transactionID string) (*AppleIAPTransaction, error) {
	var t AppleIAPTransaction
	var rawJSON []byte
	err := r.db.QueryRow(`
		SELECT id, user_id, transaction_id, original_transaction_id,
		       product_id, environment, purchase_date, expires_date,
		       raw_payload, created_at
		FROM apple_iap_transactions
		WHERE transaction_id = $1
	`, transactionID).Scan(
		&t.ID, &t.UserID, &t.TransactionID, &t.OriginalTransactionID,
		&t.ProductID, &t.Environment, &t.PurchaseDate, &t.ExpiresDate,
		&rawJSON, &t.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	t.RawPayload = rawJSON
	return &t, nil
}

// LatestForUser returns the most-recent purchase per product_id for a
// user. Useful for the "restore purchases" flow — the client doesn't need
// to know which transactions exist; we tell them.
func (r *AppleIAPTransactionRepository) LatestForUser(userID int64) ([]AppleIAPTransaction, error) {
	rows, err := r.db.Query(`
		SELECT DISTINCT ON (product_id)
		       id, user_id, transaction_id, original_transaction_id,
		       product_id, environment, purchase_date, expires_date,
		       raw_payload, created_at
		FROM apple_iap_transactions
		WHERE user_id = $1
		ORDER BY product_id, purchase_date DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []AppleIAPTransaction
	for rows.Next() {
		var t AppleIAPTransaction
		var rawJSON []byte
		if err := rows.Scan(
			&t.ID, &t.UserID, &t.TransactionID, &t.OriginalTransactionID,
			&t.ProductID, &t.Environment, &t.PurchaseDate, &t.ExpiresDate,
			&rawJSON, &t.CreatedAt,
		); err != nil {
			return nil, err
		}
		t.RawPayload = rawJSON
		out = append(out, t)
	}
	return out, rows.Err()
}
