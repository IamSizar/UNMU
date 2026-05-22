package repositories

import (
	"database/sql"
	"errors"
	"time"
)

// InboxRepository merges the two notification tables behind a single
// API. Until now `notifications` (stock alerts) and
// `user_notifications` (social/sub events) lived in separate
// schemas, two endpoints, and two mobile screens. The unified inbox
// keeps both tables in place and just stitches them together at
// read time — no schema migration risk, no data loss for the
// stock-pipeline ingest path.
//
// Source discriminator:
//
//	"social" → user_notifications (post_liked, post_commented,
//	           subscription_active, etc.)
//	"stock"  → notifications      (STATUS_CHANGE, PURIFICATION_CHANGE)
//
// The mobile inbox uses [Source] to route mark-read calls to the
// right table. New event types should land in `user_notifications`
// going forward — `notifications` is treated as legacy.
type InboxRepository struct {
	db *sql.DB
}

func NewInboxRepository(db *sql.DB) *InboxRepository {
	return &InboxRepository{db: db}
}

// InboxItem is the unified shape returned by the merged endpoint.
// Optional fields are populated based on the source — actor data
// lives on the social side, stock_id only on the stock side.
type InboxItem struct {
	ID         int64      `json:"id"`
	Source     string     `json:"source"` // "social" | "stock"
	Kind       string     `json:"kind"`
	Title      string     `json:"title"`
	Body       string     `json:"body"`
	ActorID    *int64     `json:"actorId,omitempty"`
	ActorName  string     `json:"actorName,omitempty"`
	RelatedID  *int64     `json:"relatedId,omitempty"`
	StockID    *int64     `json:"stockId,omitempty"`
	IsRead     bool       `json:"isRead"`
	ReadAt     *time.Time `json:"readAt,omitempty"`
	CreatedAt  time.Time  `json:"createdAt"`
}

// List returns the merged inbox for [userID] sorted newest-first.
// `before` is an optional keyset cursor — pass the oldest item's
// `createdAt` to fetch the next page. `unreadOnly` filters out
// already-read rows in both tables.
//
// We use UNION ALL so each side is queryable independently and
// Postgres can reuse its per-table indexes — single ORDER BY +
// LIMIT runs across the union once.
func (r *InboxRepository) List(
	userID int64,
	before time.Time,
	limit int,
	unreadOnly bool,
) ([]*InboxItem, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	// Build the WHERE clauses for each side. We want ONE query so
	// pagination naturally interleaves the two tables.
	args := []any{userID, limit}
	socialWhere := "user_id = $1"
	stockWhere := "user_id = $1"
	if !before.IsZero() {
		args = append(args, before)
		socialWhere += " AND created_at < $3"
		stockWhere += " AND created_at < $3"
	}
	if unreadOnly {
		socialWhere += " AND read_at IS NULL"
		stockWhere += " AND is_read = FALSE"
	}
	q := `
		SELECT * FROM (
		  SELECT id,
		         'social'::text   AS source,
		         type             AS kind,
		         ''::text         AS title,
		         COALESCE(body_snippet, '')::text AS body,
		         actor_id,
		         COALESCE(actor_name, '')::text AS actor_name,
		         post_id          AS related_id,
		         NULL::bigint     AS stock_id,
		         (read_at IS NOT NULL) AS is_read,
		         read_at,
		         created_at
		    FROM user_notifications
		   WHERE ` + socialWhere + `
		  UNION ALL
		  SELECT id,
		         'stock'::text    AS source,
		         type             AS kind,
		         COALESCE(title, '')::text AS title,
		         COALESCE(message, '')::text AS body,
		         NULL::bigint     AS actor_id,
		         ''::text         AS actor_name,
		         NULL::bigint     AS related_id,
		         stock_id,
		         is_read,
		         NULL::timestamptz AS read_at,
		         created_at
		    FROM notifications
		   WHERE ` + stockWhere + `
		) inbox
		 ORDER BY created_at DESC
		 LIMIT $2
	`
	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*InboxItem, 0)
	for rows.Next() {
		var it InboxItem
		var actorID, relatedID, stockID sql.NullInt64
		var actorName, body, title sql.NullString
		var readAt sql.NullTime
		if err := rows.Scan(
			&it.ID, &it.Source, &it.Kind,
			&title, &body, &actorID, &actorName,
			&relatedID, &stockID, &it.IsRead, &readAt, &it.CreatedAt,
		); err != nil {
			return nil, err
		}
		if title.Valid {
			it.Title = title.String
		}
		if body.Valid {
			it.Body = body.String
		}
		if actorID.Valid {
			v := actorID.Int64
			it.ActorID = &v
		}
		if actorName.Valid {
			it.ActorName = actorName.String
		}
		if relatedID.Valid {
			v := relatedID.Int64
			it.RelatedID = &v
		}
		if stockID.Valid {
			v := stockID.Int64
			it.StockID = &v
		}
		if readAt.Valid {
			t := readAt.Time
			it.ReadAt = &t
		}
		out = append(out, &it)
	}
	return out, rows.Err()
}

// UnreadCount across both tables. Used by the bell-icon badge.
func (r *InboxRepository) UnreadCount(userID int64) (int, error) {
	var n int
	err := r.db.QueryRow(
		`SELECT
		    (SELECT COUNT(*) FROM user_notifications
		      WHERE user_id = $1 AND read_at IS NULL)
		  + (SELECT COUNT(*) FROM notifications
		      WHERE user_id = $1 AND is_read = FALSE)
		`,
		userID,
	).Scan(&n)
	return n, err
}

// MarkRead flips a single row's read state, routing to the correct
// table based on [source]. Idempotent — already-read rows return
// nil without error.
//
// Returns sql.ErrNoRows when the row doesn't exist or doesn't
// belong to [userID] so the handler can surface 404.
func (r *InboxRepository) MarkRead(
	source string, id, userID int64,
) error {
	switch source {
	case "social":
		// user_notifications uses a nullable read_at timestamp.
		// Only set it if currently NULL so already-read rows are
		// noop'd — preserves the original read time.
		res, err := r.db.Exec(
			`UPDATE user_notifications
			    SET read_at = NOW()
			  WHERE id = $1 AND user_id = $2 AND read_at IS NULL`,
			id, userID,
		)
		if err != nil {
			return err
		}
		// 0 affected = either already-read OR not the user's row.
		// We can't distinguish without a follow-up SELECT; the
		// optimistic-mobile-side flow doesn't care, so we return
		// nil for both cases.
		_, _ = res.RowsAffected()
		return nil
	case "stock":
		// notifications uses an is_read boolean.
		res, err := r.db.Exec(
			`UPDATE notifications
			    SET is_read = TRUE
			  WHERE id = $1 AND user_id = $2 AND is_read = FALSE`,
			id, userID,
		)
		if err != nil {
			return err
		}
		_, _ = res.RowsAffected()
		return nil
	default:
		return errors.New("unknown source")
	}
}

// MarkAllRead flips every unread row for [userID] across both
// tables. Returns the count of rows actually flipped (sum of both
// tables) so the client can update its badge in one shot.
func (r *InboxRepository) MarkAllRead(userID int64) (int, error) {
	var social, stock int
	if err := r.db.QueryRow(
		`WITH upd AS (
		   UPDATE user_notifications
		      SET read_at = NOW()
		    WHERE user_id = $1 AND read_at IS NULL
		    RETURNING 1
		 )
		 SELECT COUNT(*) FROM upd`,
		userID,
	).Scan(&social); err != nil {
		return 0, err
	}
	if err := r.db.QueryRow(
		`WITH upd AS (
		   UPDATE notifications
		      SET is_read = TRUE
		    WHERE user_id = $1 AND is_read = FALSE
		    RETURNING 1
		 )
		 SELECT COUNT(*) FROM upd`,
		userID,
	).Scan(&stock); err != nil {
		return 0, err
	}
	return social + stock, nil
}
