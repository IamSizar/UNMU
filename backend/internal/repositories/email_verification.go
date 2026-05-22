package repositories

import (
	"crypto/rand"
	"database/sql"
	"fmt"
	"math/big"
	"time"
)

// EmailVerificationRepository wraps the email_verification_codes table
// added in migration 0026. Codes are short-lived 6-digit strings that
// the user types in after registering; in dev mode we also return the
// code in the API response so testers don't need a real SMTP server.
type EmailVerificationRepository struct {
	db *sql.DB
}

func NewEmailVerificationRepository(db *sql.DB) *EmailVerificationRepository {
	return &EmailVerificationRepository{db: db}
}

// GenerateCode returns a fresh 6-digit numeric code as a zero-padded string.
// Uses crypto/rand so codes aren't predictable.
func GenerateCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

// Create wipes any prior un-consumed codes for the user (so "Resend" replaces
// the previous code instead of leaving multiple valid ones around) and
// inserts a new one with the default 15-minute expiry.
func (r *EmailVerificationRepository) Create(userID int64, code string) error {
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Mark any existing active codes as consumed so they can't be replayed.
	if _, err := tx.Exec(`
		UPDATE email_verification_codes
		SET consumed_at = NOW()
		WHERE user_id = $1 AND consumed_at IS NULL
	`, userID); err != nil {
		return err
	}

	if _, err := tx.Exec(`
		INSERT INTO email_verification_codes (user_id, code)
		VALUES ($1, $2)
	`, userID, code); err != nil {
		return err
	}

	return tx.Commit()
}

// Consume validates that (userID, code) matches an active row that hasn't
// expired or been consumed yet, marks it consumed, and returns nil on
// success. Returns sql.ErrNoRows when no matching active code exists —
// caller maps that to "invalid or expired code".
func (r *EmailVerificationRepository) Consume(userID int64, code string) error {
	res, err := r.db.Exec(`
		UPDATE email_verification_codes
		SET consumed_at = NOW()
		WHERE user_id = $1
		  AND code = $2
		  AND consumed_at IS NULL
		  AND expires_at > NOW()
	`, userID, code)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// MarkUserVerified flips users.email_verified_at to NOW() (idempotent —
// re-verifying is a no-op).
func (r *EmailVerificationRepository) MarkUserVerified(userID int64) error {
	_, err := r.db.Exec(`
		UPDATE users
		SET email_verified_at = COALESCE(email_verified_at, NOW()),
		    updated_at = NOW()
		WHERE id = $1
	`, userID)
	return err
}

// IsVerified is a cheap one-shot lookup used by Login.
func (r *EmailVerificationRepository) IsVerified(userID int64) (bool, error) {
	var verifiedAt sql.NullTime
	err := r.db.QueryRow(`
		SELECT email_verified_at FROM users WHERE id = $1
	`, userID).Scan(&verifiedAt)
	if err != nil {
		return false, err
	}
	return verifiedAt.Valid, nil
}

// LastActiveAge returns how long ago the most-recent active code for the
// user was created, computed by the DB clock (so we don't have to worry
// about timezone skew between the API host and Postgres). Returns
// `false` when there is no active code.
func (r *EmailVerificationRepository) LastActiveAge(userID int64) (time.Duration, bool, error) {
	var ageSeconds sql.NullFloat64
	err := r.db.QueryRow(`
		SELECT EXTRACT(EPOCH FROM (NOW() - created_at))
		FROM email_verification_codes
		WHERE user_id = $1 AND consumed_at IS NULL AND expires_at > NOW()
		ORDER BY created_at DESC
		LIMIT 1
	`, userID).Scan(&ageSeconds)
	if err == sql.ErrNoRows {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, err
	}
	if !ageSeconds.Valid {
		return 0, false, nil
	}
	// Guard against tiny negative drift (clock skew) — clamp to 0.
	secs := ageSeconds.Float64
	if secs < 0 {
		secs = 0
	}
	return time.Duration(secs * float64(time.Second)), true, nil
}
