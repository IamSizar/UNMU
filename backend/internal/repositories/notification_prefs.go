package repositories

import (
	"database/sql"
	"errors"
	"time"
)

// NotificationPrefsRepository — per-user notification toggles (mig 0041).
//
// The table is read often (every push fan-out can check push_enabled
// before queuing) but written rarely (only when a user opens the
// settings screen and toggles a switch). Indexed on user_id by virtue
// of being the PRIMARY KEY — no extra index needed.
type NotificationPrefsRepository struct {
	db *sql.DB
}

func NewNotificationPrefsRepository(db *sql.DB) *NotificationPrefsRepository {
	return &NotificationPrefsRepository{db: db}
}

// NotificationPrefs mirrors the table row. JSON tags use camelCase for
// the Flutter client.
type NotificationPrefs struct {
	UserID               int64     `json:"userId"`
	PushEnabled          bool      `json:"pushEnabled"`
	EmailEnabled         bool      `json:"emailEnabled"`
	LikesEnabled         bool      `json:"likesEnabled"`
	CommentsEnabled      bool      `json:"commentsEnabled"`
	SubscriptionsEnabled bool      `json:"subscriptionsEnabled"`
	CommunitiesEnabled   bool      `json:"communitiesEnabled"`
	MarketingEnabled     bool      `json:"marketingEnabled"`
	UpdatedAt            time.Time `json:"updatedAt"`
}

const prefsCols = `user_id, push_enabled, email_enabled,
	likes_enabled, comments_enabled, subscriptions_enabled,
	communities_enabled, marketing_enabled, updated_at`

func scanPrefs(row interface{ Scan(dest ...any) error }) (*NotificationPrefs, error) {
	p := &NotificationPrefs{}
	if err := row.Scan(
		&p.UserID,
		&p.PushEnabled, &p.EmailEnabled,
		&p.LikesEnabled, &p.CommentsEnabled, &p.SubscriptionsEnabled,
		&p.CommunitiesEnabled, &p.MarketingEnabled,
		&p.UpdatedAt,
	); err != nil {
		return nil, err
	}
	return p, nil
}

// GetOrDefault returns the user's stored row, or a defaults row if
// they haven't touched the settings screen yet. The defaults are
// inserted server-side (idempotent INSERT … ON CONFLICT DO NOTHING)
// so subsequent reads return a real row.
func (r *NotificationPrefsRepository) GetOrDefault(userID int64) (*NotificationPrefs, error) {
	row := r.db.QueryRow(`SELECT `+prefsCols+` FROM user_notification_prefs WHERE user_id = $1`, userID)
	p, err := scanPrefs(row)
	if err == nil {
		return p, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return nil, err
	}
	// Create defaults — same constants the DDL uses.
	if _, err := r.db.Exec(`
		INSERT INTO user_notification_prefs (user_id) VALUES ($1)
		ON CONFLICT (user_id) DO NOTHING
	`, userID); err != nil {
		return nil, err
	}
	row = r.db.QueryRow(`SELECT `+prefsCols+` FROM user_notification_prefs WHERE user_id = $1`, userID)
	return scanPrefs(row)
}

// PrefsMutation — partial-update shape. nil pointer = leave column
// alone; non-nil = set.
type PrefsMutation struct {
	PushEnabled          *bool
	EmailEnabled         *bool
	LikesEnabled         *bool
	CommentsEnabled      *bool
	SubscriptionsEnabled *bool
	CommunitiesEnabled   *bool
	MarketingEnabled     *bool
}

// Update applies the mutation and returns the refreshed row. Creates
// the defaults row first if it's missing (so PATCH-before-GET works).
func (r *NotificationPrefsRepository) Update(userID int64, m PrefsMutation) (*NotificationPrefs, error) {
	if _, err := r.GetOrDefault(userID); err != nil {
		return nil, err
	}
	_, err := r.db.Exec(`
		UPDATE user_notification_prefs SET
		    push_enabled          = COALESCE($1, push_enabled),
		    email_enabled         = COALESCE($2, email_enabled),
		    likes_enabled         = COALESCE($3, likes_enabled),
		    comments_enabled      = COALESCE($4, comments_enabled),
		    subscriptions_enabled = COALESCE($5, subscriptions_enabled),
		    communities_enabled   = COALESCE($6, communities_enabled),
		    marketing_enabled     = COALESCE($7, marketing_enabled),
		    updated_at            = NOW()
		WHERE user_id = $8
	`,
		m.PushEnabled, m.EmailEnabled,
		m.LikesEnabled, m.CommentsEnabled, m.SubscriptionsEnabled,
		m.CommunitiesEnabled, m.MarketingEnabled,
		userID,
	)
	if err != nil {
		return nil, err
	}
	return r.GetOrDefault(userID)
}
