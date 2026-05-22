package repositories

import (
	"database/sql"
	"encoding/json"
	"time"

	"github.com/lib/pq"
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

// Upsert inserts a new transaction row, or returns the existing one
// when transaction_id already exists (replay → idempotent). Returns the
// resulting row and whether it was newly inserted.
func (r *AppleIAPTransactionRepository) Upsert(
	userID int64,
	transactionID, originalTransactionID, productID, environment string,
	purchaseDate time.Time,
	expiresDate *time.Time,
	rawPayload []byte,
) (*AppleIAPTransaction, bool, error) {
	// Try insert first — on the unique conflict, fetch the existing.
	row := r.db.QueryRow(`
		INSERT INTO apple_iap_transactions (
			user_id, transaction_id, original_transaction_id, product_id,
			environment, purchase_date, expires_date, raw_payload
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (transaction_id) DO NOTHING
		RETURNING id, user_id, transaction_id, original_transaction_id,
		          product_id, environment, purchase_date, expires_date,
		          raw_payload, created_at
	`, userID, transactionID, originalTransactionID, productID,
		environment, purchaseDate, expiresDate, rawPayload)

	var t AppleIAPTransaction
	var rawJSON []byte
	err := row.Scan(
		&t.ID, &t.UserID, &t.TransactionID, &t.OriginalTransactionID,
		&t.ProductID, &t.Environment, &t.PurchaseDate, &t.ExpiresDate,
		&rawJSON, &t.CreatedAt,
	)
	if err == nil {
		t.RawPayload = rawJSON
		return &t, true, nil
	}
	if err != sql.ErrNoRows {
		// Unique-constraint conflicts come back as 23505 — anything else
		// is a real DB problem.
		if pgErr, ok := err.(*pq.Error); !ok || pgErr.Code != "23505" {
			return nil, false, err
		}
	}

	// Conflict path: pull the existing row.
	existing, err := r.GetByTransactionID(transactionID)
	if err != nil {
		return nil, false, err
	}
	return existing, false, nil
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
