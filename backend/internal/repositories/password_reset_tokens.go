package repositories

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"time"
)

// PasswordResetTokenRepository persists one-time password-reset tokens.
// Raw tokens never hit the DB — we store SHA-256 of the token so a DB leak
// can't be replayed against /auth/password-reset/confirm. The token itself
// lives only in the URL we email out.
type PasswordResetTokenRepository struct {
	db *sql.DB
}

func NewPasswordResetTokenRepository(db *sql.DB) *PasswordResetTokenRepository {
	return &PasswordResetTokenRepository{db: db}
}

// GeneratePasswordResetToken returns a URL-safe random token (hex-encoded,
// 32 bytes ≈ 64 chars). Caller hands the raw token to the user (via email)
// and the hash to Create().
func GeneratePasswordResetToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// HashResetToken — exported so handlers can compute the lookup hash from
// a token they received in the request body.
func HashResetToken(token string) string {
	h := sha256.Sum256([]byte(token))
	return hex.EncodeToString(h[:])
}

// Create inserts a new reset record. ttl is typically 1 hour. Multiple
// active tokens per user are fine — Consume() picks the first match.
func (r *PasswordResetTokenRepository) Create(userID int64, rawToken string, ttl time.Duration) error {
	_, err := r.db.Exec(`
		INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
		VALUES ($1, $2, $3)
	`, userID, HashResetToken(rawToken), time.Now().Add(ttl))
	return err
}

// LastActiveAge returns how long ago the most recent un-consumed,
// un-expired token was issued. Used for rate-limiting reset requests so
// an attacker can't spam the user's inbox.
func (r *PasswordResetTokenRepository) LastActiveAge(userID int64) (time.Duration, bool, error) {
	var createdAt time.Time
	err := r.db.QueryRow(`
		SELECT created_at FROM password_reset_tokens
		WHERE user_id = $1
		  AND consumed_at IS NULL
		  AND expires_at > NOW()
		ORDER BY created_at DESC
		LIMIT 1
	`, userID).Scan(&createdAt)
	if err == sql.ErrNoRows {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, err
	}
	return time.Since(createdAt), true, nil
}

// Consume atomically marks a token as used and returns the owning user_id.
// Returns sql.ErrNoRows if the token is unknown, already consumed, or
// expired — the caller maps that to a generic 400 so we don't leak which
// of those conditions hit.
func (r *PasswordResetTokenRepository) Consume(rawToken string) (int64, error) {
	var userID int64
	err := r.db.QueryRow(`
		UPDATE password_reset_tokens
		SET consumed_at = NOW()
		WHERE token_hash = $1
		  AND consumed_at IS NULL
		  AND expires_at > NOW()
		RETURNING user_id
	`, HashResetToken(rawToken)).Scan(&userID)
	return userID, err
}

// DeleteExpired prunes stale rows so the table doesn't grow indefinitely.
// Called periodically by a janitor in main.go — see scheduled cleanups.
func (r *PasswordResetTokenRepository) DeleteExpired() (int64, error) {
	res, err := r.db.Exec(`
		DELETE FROM password_reset_tokens
		WHERE expires_at < NOW() - INTERVAL '7 days'
		   OR consumed_at < NOW() - INTERVAL '7 days'
	`)
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	return n, nil
}
