package repositories

import (
	"database/sql"
	"fmt"
	"time"
)

// PushSendLogRepository records admin "send now" pushes (mig 0060) so the
// dashboard can show real send history.
type PushSendLogRepository struct {
	db *sql.DB
}

func NewPushSendLogRepository(db *sql.DB) *PushSendLogRepository {
	return &PushSendLogRepository{db: db}
}

// PushSend is one recorded send. JSON tags match the admin dashboard.
type PushSend struct {
	ID           int64     `json:"id"`
	Title        string    `json:"title"`
	Body         string    `json:"body"`
	Target       string    `json:"target"`
	Recipients   int       `json:"recipients"`
	SuccessCount int       `json:"successCount"`
	FailureCount int       `json:"failureCount"`
	SendError    *string   `json:"sendError,omitempty"`
	SentBy       *int64    `json:"sentBy,omitempty"`
	CreatedAt    time.Time `json:"createdAt"`
}

// maxPushHistory caps one history page; the dashboard shows recent sends.
const maxPushHistory = 100

// Record stores one send. SendError and SentBy may be nil.
func (r *PushSendLogRepository) Record(s PushSend) error {
	_, err := r.db.Exec(`
		INSERT INTO push_send_log
		  (title, body, target, recipients, success_count, failure_count, send_error, sent_by)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		s.Title, s.Body, s.Target, s.Recipients, s.SuccessCount, s.FailureCount, s.SendError, s.SentBy)
	if err != nil {
		return fmt.Errorf("record push send: %w", err)
	}
	return nil
}

// Recent returns the newest sends first, at most limit (capped).
func (r *PushSendLogRepository) Recent(limit int) ([]PushSend, error) {
	if limit <= 0 || limit > maxPushHistory {
		limit = maxPushHistory
	}
	rows, err := r.db.Query(`
		SELECT id, title, body, target, recipients, success_count, failure_count,
		       send_error, sent_by, created_at
		FROM push_send_log
		ORDER BY created_at DESC, id DESC
		LIMIT $1`, limit)
	if err != nil {
		return nil, fmt.Errorf("list push sends: %w", err)
	}
	defer rows.Close()
	out := []PushSend{}
	for rows.Next() {
		var s PushSend
		if err := rows.Scan(&s.ID, &s.Title, &s.Body, &s.Target, &s.Recipients,
			&s.SuccessCount, &s.FailureCount, &s.SendError, &s.SentBy, &s.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan push send: %w", err)
		}
		out = append(out, s)
	}
	return out, rows.Err()
}
