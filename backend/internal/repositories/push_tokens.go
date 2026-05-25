package repositories

import (
	"database/sql"
	"fmt"
	"strings"
)

// PushTokenRepository persists per-device push notification tokens.
//
// Tokens are globally unique (Apple/Google guarantee). We upsert on
// the token, not on (user, platform) — that way a device that signs
// out and signs in as a different user moves cleanly to the new
// user_id without leaving a stale row tied to the old user.
type PushTokenRepository struct {
	db *sql.DB
}

func NewPushTokenRepository(db *sql.DB) *PushTokenRepository {
	return &PushTokenRepository{db: db}
}

// Upsert inserts (or refreshes) a single token row. platform must be
// one of "ios" / "android" / "web". last_seen is bumped on every call
// so we can prune dead devices later.
//
// Returns the row id. Callers usually don't need it, but it makes
// integration tests easier.
func (r *PushTokenRepository) Upsert(userID int64, token, platform string) (int64, error) {
	platform = strings.ToLower(strings.TrimSpace(platform))
	if platform != "ios" && platform != "android" && platform != "web" {
		return 0, fmt.Errorf("push: invalid platform %q", platform)
	}
	if strings.TrimSpace(token) == "" {
		return 0, fmt.Errorf("push: empty token")
	}

	var id int64
	err := r.db.QueryRow(
		`INSERT INTO user_push_tokens (user_id, token, platform, last_seen)
		 VALUES ($1, $2, $3, NOW())
		 ON CONFLICT (token) DO UPDATE
		     SET user_id   = EXCLUDED.user_id,
		         platform  = EXCLUDED.platform,
		         last_seen = NOW()
		 RETURNING id`,
		userID, token, platform,
	).Scan(&id)
	if err != nil {
		return 0, fmt.Errorf("push: upsert: %w", err)
	}
	return id, nil
}

// ListAllTokens returns every active token, optionally filtered by
// platform. Used by the admin "send to all" broadcast.
//
// Honors the per-user push_enabled toggle (mig 0041): users who turned
// off push notifications in settings are excluded from broadcasts. We
// LEFT JOIN so users who never opened the settings screen (no
// preferences row yet) are still included — push defaults to ON.
//
// For very large user bases this should be chunked at the call site
// — FCM accepts max 500 tokens per send batch.
func (r *PushTokenRepository) ListAllTokens(platform string) ([]string, error) {
	const baseSelect = `
		SELECT t.token
		FROM user_push_tokens t
		LEFT JOIN user_notification_prefs p ON p.user_id = t.user_id
		WHERE COALESCE(p.push_enabled, TRUE) = TRUE
	`
	var rows *sql.Rows
	var err error
	if platform == "" {
		rows, err = r.db.Query(baseSelect + ` ORDER BY t.last_seen DESC`)
	} else {
		rows, err = r.db.Query(
			baseSelect+` AND t.platform = $1 ORDER BY t.last_seen DESC`,
			strings.ToLower(platform),
		)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]string, 0, 128)
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// ListForUser returns every device token belonging to one user. Used
// by per-user notifications (e.g. "you have a new follower").
func (r *PushTokenRepository) ListForUser(userID int64) ([]string, error) {
	rows, err := r.db.Query(
		`SELECT token FROM user_push_tokens
		 WHERE user_id = $1
		 ORDER BY last_seen DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]string, 0, 4)
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// ListForRole returns active tokens for every user with the given role
// ("USER" / "EXPERT" / "ADMIN"). Used by the admin broadcast when the
// operator targets an audience segment by role.
//
// Mirrors ListAllTokens' opt-out handling: the LEFT JOIN on
// user_notification_prefs honors the per-user push_enabled toggle
// (defaulting to ON for users who never opened settings), and
// soft-deleted users (deleted_at set, mig 0040) are excluded.
func (r *PushTokenRepository) ListForRole(role string) ([]string, error) {
	rows, err := r.db.Query(`
		SELECT t.token
		FROM user_push_tokens t
		JOIN users u ON u.id = t.user_id
		LEFT JOIN user_notification_prefs p ON p.user_id = t.user_id
		WHERE COALESCE(p.push_enabled, TRUE) = TRUE
		  AND u.deleted_at IS NULL
		  AND u.role = $1
		ORDER BY t.last_seen DESC
	`, role)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]string, 0, 64)
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// ListForCommunity returns active tokens for every member of a
// community. Used by the admin broadcast when the operator targets a
// single community. Same opt-out + soft-delete filtering as ListForRole.
func (r *PushTokenRepository) ListForCommunity(communityID string) ([]string, error) {
	rows, err := r.db.Query(`
		SELECT t.token
		FROM user_push_tokens t
		JOIN community_members m ON m.user_id = t.user_id
		JOIN users u ON u.id = t.user_id
		LEFT JOIN user_notification_prefs p ON p.user_id = t.user_id
		WHERE COALESCE(p.push_enabled, TRUE) = TRUE
		  AND u.deleted_at IS NULL
		  AND m.community_id = $1
		ORDER BY t.last_seen DESC
	`, communityID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]string, 0, 64)
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// DeleteToken removes a single token. Called when FCM tells us a token
// is invalid (typical response codes: NOT_FOUND, INVALID_ARGUMENT). We
// drop the row so the next admin broadcast doesn't waste a quota slot
// on it.
func (r *PushTokenRepository) DeleteToken(token string) error {
	_, err := r.db.Exec(
		`DELETE FROM user_push_tokens WHERE token = $1`, token,
	)
	return err
}

// ResolveTokens returns the device tokens for a broadcast target spec.
// Shared by the immediate admin send (handlers.PushHandler.AdminSend) and
// the background scheduled-push sender so both honor the exact same
// targeting (all | ios | android | web | user | role | community). Assumes
// the spec was already validated by the caller (the HTTP layer).
func (r *PushTokenRepository) ResolveTokens(
	target string, userID int64, role, communityID string,
) ([]string, error) {
	switch strings.ToLower(strings.TrimSpace(target)) {
	case "", "all":
		return r.ListAllTokens("")
	case "ios", "android", "web":
		return r.ListAllTokens(strings.ToLower(strings.TrimSpace(target)))
	case "user":
		return r.ListForUser(userID)
	case "role":
		return r.ListForRole(strings.ToUpper(strings.TrimSpace(role)))
	case "community":
		return r.ListForCommunity(strings.TrimSpace(communityID))
	default:
		return nil, fmt.Errorf("unknown target %q", target)
	}
}
