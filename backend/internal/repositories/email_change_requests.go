package repositories

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"strings"
	"time"
)

// EmailChangeRequestRepository persists pending email-change requests
// (mig 0039). Plain codes only travel via email; we store SHA-256(code)
// so a DB leak doesn't enable replay.
type EmailChangeRequestRepository struct {
	db *sql.DB
}

func NewEmailChangeRequestRepository(db *sql.DB) *EmailChangeRequestRepository {
	return &EmailChangeRequestRepository{db: db}
}

func hashEmailChangeCode(code string) string {
	h := sha256.Sum256([]byte(strings.TrimSpace(code)))
	return hex.EncodeToString(h[:])
}

// Create inserts a new pending request. Callers must already have
// generated the code (typically via repositories.GenerateCode — the
// same 6-digit format used by email verification).
func (r *EmailChangeRequestRepository) Create(
	userID int64,
	newEmail, code string,
	ttl time.Duration,
) error {
	_, err := r.db.Exec(`
		INSERT INTO email_change_requests (user_id, new_email, code_hash, expires_at)
		VALUES ($1, $2, $3, $4)
	`,
		userID,
		strings.ToLower(strings.TrimSpace(newEmail)),
		hashEmailChangeCode(code),
		time.Now().Add(ttl),
	)
	return err
}

// LastActiveAge returns how long ago the user's most recent unconsumed,
// unexpired request was issued. Used to rate-limit /request so attackers
// can't spam the inbox.
func (r *EmailChangeRequestRepository) LastActiveAge(userID int64) (time.Duration, bool, error) {
	var createdAt time.Time
	err := r.db.QueryRow(`
		SELECT created_at FROM email_change_requests
		WHERE user_id = $1
		  AND consumed_at IS NULL
		  AND expires_at > NOW()
		ORDER BY created_at DESC
		LIMIT 1
	`, userID).Scan(&createdAt)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, err
	}
	return time.Since(createdAt), true, nil
}

// Consume finds the latest matching request and marks it consumed. The
// caller wraps it with the actual users.email flip — keeping them in
// separate calls so the handler can run them in one transaction if it
// chooses.
//
// Returns the new email on success; sql.ErrNoRows when no matching
// request exists.
func (r *EmailChangeRequestRepository) Consume(userID int64, code string) (string, error) {
	var newEmail string
	err := r.db.QueryRow(`
		UPDATE email_change_requests
		SET consumed_at = NOW()
		WHERE id = (
		    SELECT id FROM email_change_requests
		    WHERE user_id = $1
		      AND code_hash = $2
		      AND consumed_at IS NULL
		      AND expires_at > NOW()
		    ORDER BY created_at DESC
		    LIMIT 1
		)
		RETURNING new_email
	`, userID, hashEmailChangeCode(code)).Scan(&newEmail)
	return newEmail, err
}
