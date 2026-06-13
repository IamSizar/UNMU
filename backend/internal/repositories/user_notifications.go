package repositories

import (
	"database/sql"
	"halalstocks/internal/models"
)

// UserNotificationsRepository — Sarah's bell inbox.
type UserNotificationsRepository struct {
	db *sql.DB
}

func NewUserNotificationsRepository(db *sql.DB) *UserNotificationsRepository {
	return &UserNotificationsRepository{db: db}
}

const notificationCols = `
	id, user_id, actor_id, actor_name, type,
	post_id, comment_id, body_snippet, read_at, created_at
`

// List returns the user's notifications newest-first.
func (r *UserNotificationsRepository) List(userID int64, limit int) ([]*models.UserNotification, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := r.db.Query(
		`SELECT `+notificationCols+`
		 FROM user_notifications
		 WHERE user_id = $1
		 ORDER BY created_at DESC
		 LIMIT $2`,
		userID, limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*models.UserNotification
	for rows.Next() {
		n, err := scanNotification(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, n)
	}
	return out, rows.Err()
}

// Get — load a single notification by id (used by the push fan-out to
// build the FCM title/body). Returns (nil, nil) when not found.
func (r *UserNotificationsRepository) Get(id int64) (*models.UserNotification, error) {
	row := r.db.QueryRow(
		`SELECT `+notificationCols+` FROM user_notifications WHERE id = $1`,
		id,
	)
	n, err := scanNotification(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return n, err
}

// UnreadCount — int returned to drive the bell red dot + badge.
func (r *UserNotificationsRepository) UnreadCount(userID int64) (int, error) {
	var c int
	err := r.db.QueryRow(
		`SELECT COUNT(*) FROM user_notifications
		 WHERE user_id = $1 AND read_at IS NULL`,
		userID,
	).Scan(&c)
	return c, err
}

// MarkRead — single notification, owned by the caller. Idempotent.
func (r *UserNotificationsRepository) MarkRead(id, userID int64) error {
	_, err := r.db.Exec(
		`UPDATE user_notifications
		   SET read_at = NOW()
		 WHERE id = $1 AND user_id = $2 AND read_at IS NULL`,
		id, userID,
	)
	return err
}

// MarkAllRead — flips every unread row for the user.
func (r *UserNotificationsRepository) MarkAllRead(userID int64) error {
	_, err := r.db.Exec(
		`UPDATE user_notifications
		   SET read_at = NOW()
		 WHERE user_id = $1 AND read_at IS NULL`,
		userID,
	)
	return err
}

// Insert persists an arbitrary notification for [userID]. Used by
// the subscription handler to lay down `subscription_active` /
// `subscription_rejected` / `subscription_expired` rows that the
// unified inbox reads back as part of history.
//
// Optional fields can be left empty / nil — the column types are
// nullable. The like / comment triggers from migration 0010 use a
// SQL-level INSERT directly; this helper exists for go-side call
// sites.
func (r *UserNotificationsRepository) Insert(
	userID int64,
	kind string,
	actorID *int64,
	actorName, bodySnippet string,
	postID *int64,
) error {
	var actorIDArg, postIDArg any
	if actorID != nil {
		actorIDArg = *actorID
	}
	if postID != nil {
		postIDArg = *postID
	}
	var nameArg, snippetArg any
	if actorName != "" {
		nameArg = actorName
	}
	if bodySnippet != "" {
		snippetArg = bodySnippet
	}
	_, err := r.db.Exec(
		`INSERT INTO user_notifications (
		     user_id, actor_id, actor_name, type, post_id, body_snippet
		 ) VALUES ($1, $2, $3, $4, $5, $6)`,
		userID, actorIDArg, nameArg, kind, postIDArg, snippetArg,
	)
	return err
}

type rowScanner interface {
	Scan(...any) error
}

func scanNotification(s rowScanner) (*models.UserNotification, error) {
	var n models.UserNotification
	var (
		actorID     sql.NullInt64
		actorName   sql.NullString
		postID      sql.NullInt64
		commentID   sql.NullInt64
		bodySnippet sql.NullString
		readAt      sql.NullTime
	)
	if err := s.Scan(
		&n.ID, &n.UserID, &actorID, &actorName, &n.Type,
		&postID, &commentID, &bodySnippet, &readAt, &n.CreatedAt,
	); err != nil {
		return nil, err
	}
	if actorID.Valid {
		v := actorID.Int64
		n.ActorID = &v
	}
	if actorName.Valid {
		v := actorName.String
		n.ActorName = &v
	}
	if postID.Valid {
		v := postID.Int64
		n.PostID = &v
	}
	if commentID.Valid {
		v := commentID.Int64
		n.CommentID = &v
	}
	if bodySnippet.Valid {
		v := bodySnippet.String
		n.BodySnippet = &v
	}
	if readAt.Valid {
		v := readAt.Time
		n.ReadAt = &v
	}
	return &n, nil
}
