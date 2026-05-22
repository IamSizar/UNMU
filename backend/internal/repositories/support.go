package repositories

import (
	"database/sql"
	"errors"
	"strings"
	"time"
)

// SupportRepository — CRUD over the `support_threads` + `support_messages`
// tables added by migration 0029. Powers the built-in user ↔ admin chat
// surfaced via the mobile Settings → Contact Admin entry and the admin
// dashboard's Support inbox.
//
// Design notes:
//   * One thread per user (UNIQUE constraint on user_id). `EnsureThread`
//     is the canonical lookup-or-create call.
//   * The thread row caches `last_message_at` + `unread_admin` +
//     `unread_user` via an AFTER INSERT trigger, so list / badge queries
//     never have to aggregate over messages.
//   * A separate pg_notify trigger fires on every message insert; see
//     `internal/realtime/listener.go` for the dispatcher.
type SupportRepository struct {
	db *sql.DB
}

func NewSupportRepository(db *sql.DB) *SupportRepository {
	return &SupportRepository{db: db}
}

// SupportThread mirrors the `support_threads` row plus a couple of
// joined-in display fields the admin inbox needs (`UserName`,
// `UserEmail`). Time pointers are nil-able where the column is.
type SupportThread struct {
	ID              int64     `json:"id"`
	UserID          int64     `json:"userId"`
	UserName        string    `json:"userName,omitempty"`
	UserEmail       string    `json:"userEmail,omitempty"`
	Status          string    `json:"status"`
	LastMessageAt   time.Time `json:"lastMessageAt"`
	LastMessageRole string    `json:"lastMessageRole,omitempty"`
	LastMessageBody string    `json:"lastMessageBody,omitempty"`
	UnreadAdmin     int       `json:"unreadAdmin"`
	UnreadUser      int       `json:"unreadUser"`
	CreatedAt       time.Time `json:"createdAt"`
	// Pinned message id from mig 0030. Nil when nothing is pinned.
	PinnedMessageID *int64 `json:"pinnedMessageId,omitempty"`
}

// SupportMessage — one row in `support_messages`. `SenderRole` is the
// authoritative chat-bubble alignment field (user vs admin); the
// SenderUserID is mostly for audit + display ("which admin replied").
//
// Mig 0030 added:
//   * EditedAt  — non-nil when the message has been edited at least once
//   * DeletedAt — non-nil when soft-deleted (UI shows "[message deleted]")
type SupportMessage struct {
	ID           int64      `json:"id"`
	ThreadID     int64      `json:"threadId"`
	SenderUserID int64      `json:"senderUserId"`
	SenderRole   string     `json:"senderRole"`
	SenderName   string     `json:"senderName,omitempty"`
	Body         string     `json:"body"`
	CreatedAt    time.Time  `json:"createdAt"`
	EditedAt     *time.Time `json:"editedAt,omitempty"`
	DeletedAt    *time.Time `json:"deletedAt,omitempty"`
}

// EnsureThread returns the existing thread for the given user, creating
// one if none exists yet. Idempotent — safe to call on every message
// send without an existence check at the caller.
func (r *SupportRepository) EnsureThread(userID int64) (*SupportThread, error) {
	// Try existing first (cheaper than always-INSERT-on-conflict round-trip).
	t, err := r.GetThreadByUserID(userID)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return nil, err
	}
	if t != nil {
		return t, nil
	}
	// Insert and re-fetch with the joined display fields.
	var id int64
	if err := r.db.QueryRow(
		`INSERT INTO support_threads (user_id) VALUES ($1)
		 ON CONFLICT (user_id) DO UPDATE SET updated_at = NOW()
		 RETURNING id`,
		userID,
	).Scan(&id); err != nil {
		return nil, err
	}
	return r.GetThreadByID(id)
}

// GetThreadByUserID — owner-side lookup. Returns sql.ErrNoRows when
// the user has never opened a thread.
func (r *SupportRepository) GetThreadByUserID(userID int64) (*SupportThread, error) {
	row := r.db.QueryRow(`
		SELECT t.id, t.user_id,
		       COALESCE(NULLIF(u.name, ''), '') AS user_name,
		       COALESCE(u.email, '')            AS user_email,
		       t.status, t.last_message_at,
		       COALESCE(t.last_message_role, ''),
		       COALESCE(t.last_message_body, ''),
		       t.unread_admin, t.unread_user, t.created_at,
		       t.pinned_message_id
		  FROM support_threads t
		  JOIN users u ON u.id = t.user_id
		 WHERE t.user_id = $1
	`, userID)
	return scanSupportThread(row)
}

// GetThreadByID — admin-side lookup by thread id. Returns sql.ErrNoRows
// when the id doesn't exist.
func (r *SupportRepository) GetThreadByID(id int64) (*SupportThread, error) {
	row := r.db.QueryRow(`
		SELECT t.id, t.user_id,
		       COALESCE(NULLIF(u.name, ''), '') AS user_name,
		       COALESCE(u.email, '')            AS user_email,
		       t.status, t.last_message_at,
		       COALESCE(t.last_message_role, ''),
		       COALESCE(t.last_message_body, ''),
		       t.unread_admin, t.unread_user, t.created_at,
		       t.pinned_message_id
		  FROM support_threads t
		  JOIN users u ON u.id = t.user_id
		 WHERE t.id = $1
	`, id)
	return scanSupportThread(row)
}

// AdminListThreads — newest activity first, optionally filtered by
// status ('open' | 'closed' | ''). Drives the admin inbox.
func (r *SupportRepository) AdminListThreads(status string, limit int) ([]*SupportThread, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	q := `
		SELECT t.id, t.user_id,
		       COALESCE(NULLIF(u.name, ''), '') AS user_name,
		       COALESCE(u.email, '')            AS user_email,
		       t.status, t.last_message_at,
		       COALESCE(t.last_message_role, ''),
		       COALESCE(t.last_message_body, ''),
		       t.unread_admin, t.unread_user, t.created_at,
		       t.pinned_message_id
		  FROM support_threads t
		  JOIN users u ON u.id = t.user_id
	`
	args := []any{}
	if status != "" {
		args = append(args, status)
		q += ` WHERE t.status = $1`
	}
	// Unread-first, then newest last_message_at — admins triage by what
	// hasn't been answered yet.
	q += ` ORDER BY (t.unread_admin > 0) DESC, t.last_message_at DESC LIMIT ` + itoa(limit)

	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*SupportThread, 0)
	for rows.Next() {
		t, err := scanSupportThread(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// AdminPendingCount — total unread admin messages across every thread.
// Drives the red dot + count badge in the admin sidebar.
func (r *SupportRepository) AdminPendingCount() (int, error) {
	var n int
	err := r.db.QueryRow(
		`SELECT COALESCE(SUM(unread_admin), 0) FROM support_threads`,
	).Scan(&n)
	return n, err
}

// Insert a message and return the new row. Body MUST be trimmed and
// validated by the handler before calling this — repo is the trust
// boundary for shape (FK + role) but not for content.
func (r *SupportRepository) InsertMessage(
	threadID, senderUserID int64,
	senderRole, body string,
) (*SupportMessage, error) {
	row := r.db.QueryRow(
		`INSERT INTO support_messages (thread_id, sender_user_id, sender_role, body)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id, thread_id, sender_user_id, sender_role, body, created_at,
		           edited_at, deleted_at`,
		threadID, senderUserID, senderRole, body,
	)
	return scanSupportMessageRow(row)
}

// GetMessageByID — used by the edit/delete/pin handlers to verify the
// caller actually has authority over this row (own-message edit for
// users, anything for admins). Returns sql.ErrNoRows when missing.
func (r *SupportRepository) GetMessageByID(id int64) (*SupportMessage, error) {
	row := r.db.QueryRow(
		`SELECT id, thread_id, sender_user_id, sender_role, body, created_at,
		        edited_at, deleted_at
		   FROM support_messages WHERE id = $1`,
		id,
	)
	return scanSupportMessageRow(row)
}

// UpdateMessageBody — edits a message body. Caller (handler) is
// responsible for authorization: users may edit only their own
// messages, admins may edit anything. Sets `edited_at = NOW()` so the
// UI can show "(edited)". Refuses to edit soft-deleted rows.
func (r *SupportRepository) UpdateMessageBody(id int64, body string) (*SupportMessage, error) {
	row := r.db.QueryRow(
		`UPDATE support_messages
		    SET body = $1,
		        edited_at = NOW()
		  WHERE id = $2 AND deleted_at IS NULL
		  RETURNING id, thread_id, sender_user_id, sender_role, body, created_at,
		            edited_at, deleted_at`,
		body, id,
	)
	return scanSupportMessageRow(row)
}

// SoftDeleteMessage — admin-only. Marks `deleted_at = NOW()`. The row
// stays so threads keep their bubble layout (and any pinned reference
// remains intact — the FK on support_threads.pinned_message_id is
// ON DELETE SET NULL, but we're not deleting the row, just hiding the
// body). UI renders "[message deleted]" for deleted rows.
func (r *SupportRepository) SoftDeleteMessage(id int64) error {
	res, err := r.db.Exec(
		`UPDATE support_messages
		    SET deleted_at = NOW()
		  WHERE id = $1 AND deleted_at IS NULL`,
		id,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// SetPinned — admin-only. Pins (or unpins, when messageID = 0) a
// message in the given thread. Single-pin per thread; passing a new
// id replaces the previous pin. The thread-update trigger emits the
// `pinned` / `unpinned` event so both clients refresh live.
func (r *SupportRepository) SetPinned(threadID, messageID int64) error {
	if messageID == 0 {
		_, err := r.db.Exec(
			`UPDATE support_threads SET pinned_message_id = NULL, updated_at = NOW()
			  WHERE id = $1`,
			threadID,
		)
		return err
	}
	// Verify the message belongs to this thread (defense in depth — the
	// handler should already guarantee this).
	var owns bool
	if err := r.db.QueryRow(
		`SELECT EXISTS (
		    SELECT 1 FROM support_messages
		     WHERE id = $1 AND thread_id = $2 AND deleted_at IS NULL
		 )`,
		messageID, threadID,
	).Scan(&owns); err != nil {
		return err
	}
	if !owns {
		return errors.New("message does not belong to this thread, or is deleted")
	}
	_, err := r.db.Exec(
		`UPDATE support_threads SET pinned_message_id = $1, updated_at = NOW()
		  WHERE id = $2`,
		messageID, threadID,
	)
	return err
}

// ListMessages — oldest → newest for a given thread. Drives both the
// mobile chat scroll and the admin thread detail page.
//
// Joined `users.name` provides the SenderName so the admin UI can show
// "Sarah Chen replied" without an extra round trip.
func (r *SupportRepository) ListMessages(threadID int64, limit int) ([]*SupportMessage, error) {
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	rows, err := r.db.Query(`
		SELECT m.id, m.thread_id, m.sender_user_id, m.sender_role,
		       COALESCE(NULLIF(u.name, ''), u.email) AS sender_name,
		       m.body, m.created_at, m.edited_at, m.deleted_at
		  FROM support_messages m
		  LEFT JOIN users u ON u.id = m.sender_user_id
		 WHERE m.thread_id = $1
		 ORDER BY m.created_at ASC, m.id ASC
		 LIMIT ` + itoa(limit),
		threadID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*SupportMessage, 0)
	for rows.Next() {
		var m SupportMessage
		var name sql.NullString
		var editedAt, deletedAt sql.NullTime
		if err := rows.Scan(
			&m.ID, &m.ThreadID, &m.SenderUserID, &m.SenderRole,
			&name, &m.Body, &m.CreatedAt, &editedAt, &deletedAt,
		); err != nil {
			return nil, err
		}
		if name.Valid {
			m.SenderName = name.String
		}
		if editedAt.Valid {
			v := editedAt.Time
			m.EditedAt = &v
		}
		if deletedAt.Valid {
			v := deletedAt.Time
			m.DeletedAt = &v
		}
		out = append(out, &m)
	}
	return out, rows.Err()
}

// scanSupportMessageRow — single-row scan helper used by InsertMessage,
// GetMessageByID, and UpdateMessageBody. Columns must match the
// canonical row order: id, thread_id, sender_user_id, sender_role,
// body, created_at, edited_at, deleted_at.
func scanSupportMessageRow(s interface{ Scan(...any) error }) (*SupportMessage, error) {
	var m SupportMessage
	var editedAt, deletedAt sql.NullTime
	if err := s.Scan(
		&m.ID, &m.ThreadID, &m.SenderUserID, &m.SenderRole,
		&m.Body, &m.CreatedAt, &editedAt, &deletedAt,
	); err != nil {
		return nil, err
	}
	if editedAt.Valid {
		v := editedAt.Time
		m.EditedAt = &v
	}
	if deletedAt.Valid {
		v := deletedAt.Time
		m.DeletedAt = &v
	}
	return &m, nil
}

// MarkUserRead — user opened their support screen; zero out the unread
// counter on their side so the bell stops blinking on their device.
// Admin-side `unread_admin` is untouched (only the admin can zero it).
func (r *SupportRepository) MarkUserRead(userID int64) error {
	_, err := r.db.Exec(
		`UPDATE support_threads SET unread_user = 0, updated_at = NOW()
		  WHERE user_id = $1`,
		userID,
	)
	return err
}

// MarkAdminRead — admin opened a thread; zero out the admin-side
// unread for THAT thread (not all threads, since admins triage one at
// a time). User-side `unread_user` is untouched.
func (r *SupportRepository) MarkAdminRead(threadID int64) error {
	_, err := r.db.Exec(
		`UPDATE support_threads SET unread_admin = 0, updated_at = NOW()
		  WHERE id = $1`,
		threadID,
	)
	return err
}

// SetStatus — admin closes / re-opens a thread. The user can re-open
// implicitly by sending another message (the message INSERT trigger
// flips status back to 'open' in that case).
func (r *SupportRepository) SetStatus(threadID int64, status string) error {
	if status != "open" && status != "closed" {
		return errors.New("invalid status")
	}
	res, err := r.db.Exec(
		`UPDATE support_threads SET status = $1, updated_at = NOW()
		  WHERE id = $2`,
		status, threadID,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// ─── internal helpers ───────────────────────────────────────────────

type supportThreadScanner interface {
	Scan(dest ...any) error
}

func scanSupportThread(s supportThreadScanner) (*SupportThread, error) {
	var t SupportThread
	var pinned sql.NullInt64
	if err := s.Scan(
		&t.ID, &t.UserID, &t.UserName, &t.UserEmail,
		&t.Status, &t.LastMessageAt,
		&t.LastMessageRole, &t.LastMessageBody,
		&t.UnreadAdmin, &t.UnreadUser, &t.CreatedAt,
		&pinned,
	); err != nil {
		return nil, err
	}
	if pinned.Valid {
		v := pinned.Int64
		t.PinnedMessageID = &v
	}
	// Defensive trim of the snippet so an admin doesn't see "\n\n  Hi  "
	// with whitespace in the inbox.
	t.LastMessageBody = strings.TrimSpace(t.LastMessageBody)
	return &t, nil
}
