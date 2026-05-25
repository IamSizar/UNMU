package repositories

import (
	"database/sql"
	"encoding/json"
	"time"

	"github.com/lib/pq"
)

// ScheduledPushRepository persists admin "schedule / countdown" push
// notifications (mig 0048). A background sender claims due rows and fires
// them via FCM. repositories → services stays one-way (this file imports
// nothing from services), so the sender can depend on this repo cleanly.
type ScheduledPushRepository struct {
	db *sql.DB
}

func NewScheduledPushRepository(db *sql.DB) *ScheduledPushRepository {
	return &ScheduledPushRepository{db: db}
}

// ScheduledPush is one queued notification. JSON tags match what the admin
// dashboard sends/reads.
type ScheduledPush struct {
	ID           int64             `json:"id"`
	Title        string            `json:"title"`
	Body         string            `json:"body"`
	Data         map[string]string `json:"data,omitempty"`
	Target       string            `json:"target"`
	UserID       *int64            `json:"userId,omitempty"`
	Role         *string           `json:"role,omitempty"`
	CommunityID  *string           `json:"communityId,omitempty"`
	SendAt       time.Time         `json:"sendAt"`
	Status       string            `json:"status"`
	SuccessCount int               `json:"successCount"`
	FailureCount int               `json:"failureCount"`
	Recipients   int               `json:"recipients"`
	Error        *string           `json:"error,omitempty"`
	CreatedBy    *int64            `json:"createdBy,omitempty"`
	CreatedAt    time.Time         `json:"createdAt"`
	SentAt       *time.Time        `json:"sentAt,omitempty"`

	// Recurrence (mig 0049). RepeatKind 'none' = one-shot. RepeatDays holds
	// weekdays (0=Sun … 6=Sat) for 'weekly'. RepeatCount = times fired.
	RepeatKind  string  `json:"repeatKind,omitempty"`
	RepeatDays  []int64 `json:"repeatDays,omitempty"`
	RepeatCount int     `json:"repeatCount"`
}

const scheduledPushCols = `
	id, title, body, data, target, user_id, role, community_id, send_at,
	status, success_count, failure_count, recipients, error, created_by,
	created_at, sent_at, repeat_kind, repeat_days, repeat_count`

// (rowScanner is already declared in this package — reuse it.)

func scanScheduledPush(s rowScanner) (*ScheduledPush, error) {
	var p ScheduledPush
	var (
		dataRaw     []byte
		userID      sql.NullInt64
		role        sql.NullString
		communityID sql.NullString
		errMsg      sql.NullString
		createdBy   sql.NullInt64
		sentAt      sql.NullTime
	)
	if err := s.Scan(
		&p.ID, &p.Title, &p.Body, &dataRaw, &p.Target, &userID, &role,
		&communityID, &p.SendAt, &p.Status, &p.SuccessCount, &p.FailureCount,
		&p.Recipients, &errMsg, &createdBy, &p.CreatedAt, &sentAt,
		&p.RepeatKind, pq.Array(&p.RepeatDays), &p.RepeatCount,
	); err != nil {
		return nil, err
	}
	if len(dataRaw) > 0 {
		_ = json.Unmarshal(dataRaw, &p.Data)
	}
	if userID.Valid {
		p.UserID = &userID.Int64
	}
	if role.Valid {
		p.Role = &role.String
	}
	if communityID.Valid {
		p.CommunityID = &communityID.String
	}
	if errMsg.Valid {
		p.Error = &errMsg.String
	}
	if createdBy.Valid {
		p.CreatedBy = &createdBy.Int64
	}
	if sentAt.Valid {
		t := sentAt.Time
		p.SentAt = &t
	}
	return &p, nil
}

// Create inserts a pending scheduled push and returns the stored row.
func (r *ScheduledPushRepository) Create(p ScheduledPush) (*ScheduledPush, error) {
	var dataArg any
	if len(p.Data) > 0 {
		b, _ := json.Marshal(p.Data)
		dataArg = string(b) // text → jsonb coercion on insert
	}
	kind := p.RepeatKind
	if kind == "" {
		kind = "none"
	}
	var daysArg any
	if len(p.RepeatDays) > 0 {
		daysArg = pq.Array(p.RepeatDays)
	} // else NULL
	row := r.db.QueryRow(
		`INSERT INTO scheduled_pushes
		   (title, body, data, target, user_id, role, community_id, send_at,
		    created_by, repeat_kind, repeat_days)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
		 RETURNING `+scheduledPushCols,
		p.Title, p.Body, dataArg, p.Target, p.UserID, p.Role, p.CommunityID,
		p.SendAt, p.CreatedBy, kind, daysArg,
	)
	return scanScheduledPush(row)
}

// RearmRecurring records a recurring push's latest send and moves send_at to
// the next occurrence, leaving status='pending' so it fires again. Used
// instead of MarkSent for rows whose repeat_kind != 'none'.
func (r *ScheduledPushRepository) RearmRecurring(id int64, success, failure, recipients int, next time.Time) error {
	_, err := r.db.Exec(
		`UPDATE scheduled_pushes
		 SET status='pending', send_at=$2, success_count=$3, failure_count=$4,
		     recipients=$5, error=NULL, sent_at=NOW(), repeat_count=repeat_count+1
		 WHERE id=$1`, id, next, success, failure, recipients)
	return err
}

// List returns the most recent scheduled pushes (upcoming + past), newest
// send-time first — the dashboard renders live countdowns for the pending
// ones.
func (r *ScheduledPushRepository) List(limit int) ([]ScheduledPush, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	rows, err := r.db.Query(
		`SELECT `+scheduledPushCols+` FROM scheduled_pushes
		 ORDER BY send_at DESC LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ScheduledPush{}
	for rows.Next() {
		p, err := scanScheduledPush(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *p)
	}
	return out, rows.Err()
}

// ClaimDue atomically flips up to N due pending rows to 'sending' and
// returns them. FOR UPDATE SKIP LOCKED makes it safe across instances.
func (r *ScheduledPushRepository) ClaimDue() ([]ScheduledPush, error) {
	rows, err := r.db.Query(
		`UPDATE scheduled_pushes SET status='sending'
		 WHERE id IN (
		   SELECT id FROM scheduled_pushes
		   WHERE status='pending' AND send_at <= NOW()
		   ORDER BY send_at ASC LIMIT 20
		   FOR UPDATE SKIP LOCKED
		 )
		 RETURNING ` + scheduledPushCols)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ScheduledPush{}
	for rows.Next() {
		p, err := scanScheduledPush(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *p)
	}
	return out, rows.Err()
}

func (r *ScheduledPushRepository) MarkSent(id int64, success, failure, recipients int) error {
	_, err := r.db.Exec(
		`UPDATE scheduled_pushes
		 SET status='sent', success_count=$2, failure_count=$3, recipients=$4,
		     error=NULL, sent_at=NOW()
		 WHERE id=$1`, id, success, failure, recipients)
	return err
}

func (r *ScheduledPushRepository) MarkFailed(id int64, errMsg string) error {
	_, err := r.db.Exec(
		`UPDATE scheduled_pushes SET status='failed', error=$2, sent_at=NOW()
		 WHERE id=$1`, id, errMsg)
	return err
}

// RequeueStuck resets rows left in 'sending' by a crashed/restarted sender
// back to 'pending' so they fire on the next tick. Called once at startup.
func (r *ScheduledPushRepository) RequeueStuck() error {
	_, err := r.db.Exec(
		`UPDATE scheduled_pushes SET status='pending' WHERE status='sending'`)
	return err
}

// Cancel marks a still-pending push cancelled. Returns false if it wasn't
// pending anymore (already sending/sent/cancelled).
func (r *ScheduledPushRepository) Cancel(id int64) (bool, error) {
	res, err := r.db.Exec(
		`UPDATE scheduled_pushes SET status='cancelled'
		 WHERE id=$1 AND status='pending'`, id)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}
