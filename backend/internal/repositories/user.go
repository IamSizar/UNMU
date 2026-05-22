package repositories

import (
	"database/sql"
	"errors"
	"fmt"
	"halalstocks/internal/models"
	"strings"
	"time"
)

type UserRepository struct {
	db *sql.DB
}

func NewUserRepository(db *sql.DB) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) Create(user *models.User) error {
	query := `
		INSERT INTO users (email, password_hash, name, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id
	`

	var name sql.NullString
	if user.Name.Valid {
		name = user.Name
	}

	err := r.db.QueryRow(query,
		user.Email, user.PasswordHash, name, time.Now(), time.Now(),
	).Scan(&user.ID)

	return err
}

func (r *UserRepository) GetByEmail(email string) (*models.User, error) {
	query := `
		SELECT id, email, password_hash, name, avatar_url,
		       COALESCE(role, 'USER'), expert_id,
		       COALESCE(subscription_tier, 'FREE'),
		       COALESCE(subscription_status, 'ACTIVE'),
		       subscription_end_date,
		       created_at, updated_at
		FROM users
		WHERE email = $1
	`

	user := &models.User{}
	err := r.db.QueryRow(query, email).Scan(
		&user.ID, &user.Email, &user.PasswordHash, &user.Name, &user.AvatarURL,
		&user.Role, &user.ExpertID,
		&user.SubscriptionTier, &user.SubscriptionStatus, &user.SubscriptionEndDate,
		&user.CreatedAt, &user.UpdatedAt,
	)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	return user, err
}

func (r *UserRepository) GetByID(id int64) (*models.User, error) {
	query := `
		SELECT id, email, password_hash, name, avatar_url,
		       COALESCE(role, 'USER'), expert_id,
		       COALESCE(subscription_tier, 'FREE'),
		       COALESCE(subscription_status, 'ACTIVE'),
		       subscription_end_date,
		       COALESCE(locale, 'en'),
		       created_at, updated_at
		FROM users
		WHERE id = $1
	`

	user := &models.User{}
	err := r.db.QueryRow(query, id).Scan(
		&user.ID, &user.Email, &user.PasswordHash, &user.Name, &user.AvatarURL,
		&user.Role, &user.ExpertID,
		&user.SubscriptionTier, &user.SubscriptionStatus, &user.SubscriptionEndDate,
		&user.Locale,
		&user.CreatedAt, &user.UpdatedAt,
	)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	return user, err
}

// AllUserIDs returns the ids of all non-deleted users. Used by the
// temporary notification smoke-test endpoint.
func (r *UserRepository) AllUserIDs() ([]int64, error) {
	rows, err := r.db.Query(`SELECT id FROM users WHERE deleted_at IS NULL`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]int64, 0, 64)
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// GetByExpertID returns the user account that owns the given expert
// profile (users.expert_id → experts.id). Returns (nil, nil) when no
// user is linked. Used to notify an expert of a new subscriber.
func (r *UserRepository) GetByExpertID(expertID string) (*models.User, error) {
	query := `
		SELECT id, email, password_hash, name, avatar_url,
		       COALESCE(role, 'USER'), expert_id,
		       COALESCE(subscription_tier, 'FREE'),
		       COALESCE(subscription_status, 'ACTIVE'),
		       subscription_end_date,
		       COALESCE(locale, 'en'),
		       created_at, updated_at
		FROM users
		WHERE expert_id = $1 AND deleted_at IS NULL
		LIMIT 1
	`
	user := &models.User{}
	err := r.db.QueryRow(query, expertID).Scan(
		&user.ID, &user.Email, &user.PasswordHash, &user.Name, &user.AvatarURL,
		&user.Role, &user.ExpertID,
		&user.SubscriptionTier, &user.SubscriptionStatus, &user.SubscriptionEndDate,
		&user.Locale,
		&user.CreatedAt, &user.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return user, err
}

// ─────────────────────────────────────────────────────────────────────────────
// Firebase OAuth integration (migration 0031).
// ─────────────────────────────────────────────────────────────────────────────

// GetByFirebaseUID returns the user previously linked to a Firebase identity,
// or (nil, nil) when no row matches — typical case is a brand-new OAuth user
// the caller will need to auto-create.
func (r *UserRepository) GetByFirebaseUID(uid string) (*models.User, error) {
	query := `
		SELECT id, email, password_hash, name, avatar_url,
		       COALESCE(role, 'USER'), expert_id,
		       COALESCE(subscription_tier, 'FREE'),
		       COALESCE(subscription_status, 'ACTIVE'),
		       subscription_end_date,
		       created_at, updated_at
		FROM users
		WHERE firebase_uid = $1
	`
	user := &models.User{}
	err := r.db.QueryRow(query, uid).Scan(
		&user.ID, &user.Email, &user.PasswordHash, &user.Name, &user.AvatarURL,
		&user.Role, &user.ExpertID,
		&user.SubscriptionTier, &user.SubscriptionStatus, &user.SubscriptionEndDate,
		&user.CreatedAt, &user.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return user, err
}

// LinkFirebaseUID stamps a Firebase UID onto an existing user row. Called
// the first time an email/password user signs in with Google or Apple using
// the same email — we adopt them into Firebase without forcing a new account.
//
// The UNIQUE index from migration 0031 makes this safely idempotent: a UID
// can only be linked to one row, and the same row can have its UID re-
// written to the same value without error.
//
// If the existing row's name is empty AND we received one from the OAuth
// provider, fill it in too — quality-of-life win for users who signed up
// with email/password and never bothered to set a display name.
func (r *UserRepository) LinkFirebaseUID(userID int64, uid, name string) error {
	if strings.TrimSpace(name) == "" {
		_, err := r.db.Exec(
			`UPDATE users SET firebase_uid = $1, updated_at = $2 WHERE id = $3`,
			uid, time.Now(), userID,
		)
		return err
	}
	// COALESCE: only overwrite name when the existing value is NULL or
	// an empty string. We never trample a name the user has explicitly
	// set, even if Google now reports something different.
	_, err := r.db.Exec(
		`UPDATE users
		   SET firebase_uid = $1,
		       name = COALESCE(NULLIF(name,''), $2),
		       updated_at = $3
		 WHERE id = $4`,
		uid, name, time.Now(), userID,
	)
	return err
}

// OAuthOnlyPasswordSentinel is the placeholder stored in password_hash
// for users who authenticate exclusively via Firebase OAuth (Google /
// Apple) and have never set a local password. The column is NOT NULL,
// and this value is longer than any real bcrypt hash so bcrypt.Compare
// always fails against it. Every place that must decide "does this user
// have a real password?" compares against this exact constant — keep it
// in one spot so the check can't drift (it previously did: profile.go
// checked a different literal and OAuth users couldn't delete their
// account).
const OAuthOnlyPasswordSentinel = "OAUTH-ONLY-NO-PASSWORD"

// CreateFromFirebase inserts a new user row for a first-time Firebase
// signup. There is no password yet (see [OAuthOnlyPasswordSentinel]) —
// the user can set one later via the onboarding / forgot-password flow.
func (r *UserRepository) CreateFromFirebase(email, name, firebaseUID string) (*models.User, error) {
	user := &models.User{
		Email:        email,
		PasswordHash: OAuthOnlyPasswordSentinel,
		Name:         sql.NullString{String: name, Valid: name != ""},
	}
	// email_verified_at is stamped at creation: Google / Apple already
	// verified the address, and the product has no separate verification
	// step. Without this, email/password login would 403 these users.
	err := r.db.QueryRow(
		`INSERT INTO users (email, password_hash, name, firebase_uid, email_verified_at, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $5, $5)
		 RETURNING id, COALESCE(role,'USER'), COALESCE(subscription_tier,'FREE'),
		           COALESCE(subscription_status,'ACTIVE'), created_at, updated_at`,
		email, OAuthOnlyPasswordSentinel, user.Name, firebaseUID, time.Now(),
	).Scan(
		&user.ID, &user.Role, &user.SubscriptionTier,
		&user.SubscriptionStatus, &user.CreatedAt, &user.UpdatedAt,
	)
	return user, err
}

func (r *UserRepository) UpdateSubscription(userID int64, tier, status string, endDate *time.Time) error {
	query := `
		UPDATE users
		SET subscription_tier = $1, subscription_status = $2, subscription_end_date = $3, updated_at = $4
		WHERE id = $5
	`
	_, err := r.db.Exec(query, tier, status, endDate, time.Now(), userID)
	return err
}

// UpdatePassword replaces the bcrypt hash for a user. Used by both
// password-reset confirm (forgot-password flow) and change-password
// (settings flow). Caller is expected to have already validated the
// current password / reset token.
func (r *UserRepository) UpdatePassword(userID int64, newHash string) error {
	_, err := r.db.Exec(
		`UPDATE users SET password_hash = $1, updated_at = $2 WHERE id = $3`,
		newHash, time.Now(), userID,
	)
	return err
}

// ErrEmailTaken — UPDATE users SET email=... hit the email UNIQUE
// index. Caller maps to 409 in the change-email confirm path.
var ErrEmailTaken = errors.New("user: email already in use")

// ProfileMutation — partial-update shape for /me/profile. Same
// pointer-pattern as the Ads/Promos repos: nil pointer = leave column
// alone; non-nil with empty string = clear to NULL.
type ProfileMutation struct {
	Name      *string
	AvatarURL *string
}

// UpdateEmail flips the canonical email and marks it verified (since
// the caller has just confirmed it via a code sent to that inbox). The
// old email becomes available for re-registration.
func (r *UserRepository) UpdateEmail(userID int64, newEmail string) error {
	newEmail = strings.ToLower(strings.TrimSpace(newEmail))
	_, err := r.db.Exec(`
		UPDATE users
		SET email = $1,
		    email_verified_at = NOW(),
		    updated_at = NOW()
		WHERE id = $2
	`, newEmail, userID)
	if err != nil && strings.Contains(err.Error(), "duplicate key") {
		return ErrEmailTaken
	}
	return err
}

// SoftDelete anonymizes a user row in-place (mig 0040). The original
// email is freed for re-registration; authored posts / comments keep
// their FK link and the UI renders "Deleted User" for the author. The
// caller has already verified the user's password.
//
// We do NOT cascade-delete content here. Hard delete would orphan every
// downstream FK and lose audit history; soft delete + anonymization is
// the standard pattern for GDPR / App Store account-deletion compliance.
func (r *UserRepository) SoftDelete(userID int64) error {
	_, err := r.db.Exec(`
		UPDATE users
		SET deleted_at    = NOW(),
		    email         = 'deleted_' || $1::text || '@deleted.local',
		    password_hash = 'DELETED',
		    name          = NULL,
		    avatar_url    = NULL,
		    firebase_uid  = NULL,
		    updated_at    = NOW()
		WHERE id = $1
		  AND deleted_at IS NULL
	`, userID)
	return err
}

// IsDeleted returns true when the user row has a non-null deleted_at.
// Cheap one-column read used by the Login + Register handlers to refuse
// already-tombstoned accounts (and by the auth middleware to invalidate
// any lingering JWTs after deletion).
func (r *UserRepository) IsDeleted(userID int64) (bool, error) {
	var deletedAt sql.NullTime
	err := r.db.QueryRow(
		`SELECT deleted_at FROM users WHERE id = $1`, userID,
	).Scan(&deletedAt)
	if err != nil {
		return false, err
	}
	return deletedAt.Valid, nil
}

// UpdateProfile applies a partial profile mutation and returns the
// refreshed user row. Empty trimmed strings clear the column.
func (r *UserRepository) UpdateProfile(userID int64, m ProfileMutation) (*models.User, error) {
	// $N::boolean = "field present" flag; NULLIF($N+1, '') turns empty
	// strings into NULL so the admin can clear a field by sending "".
	_, err := r.db.Exec(`
		UPDATE users SET
		    name       = CASE WHEN $1::boolean THEN NULLIF($2, '') ELSE name END,
		    avatar_url = CASE WHEN $3::boolean THEN NULLIF($4, '') ELSE avatar_url END,
		    updated_at = NOW()
		WHERE id = $5
	`,
		m.Name != nil, derefStringOrEmpty(m.Name),
		m.AvatarURL != nil, derefStringOrEmpty(m.AvatarURL),
		userID,
	)
	if err != nil {
		return nil, err
	}
	return r.GetByID(userID)
}

// UpdateLocale sets the user's UI language ('en' / 'ar'), synced from
// the app's language toggle. Caller validates the value.
func (r *UserRepository) UpdateLocale(userID int64, locale string) error {
	_, err := r.db.Exec(`
		UPDATE users
		SET locale = $1, updated_at = NOW()
		WHERE id = $2
	`, locale, userID)
	return err
}

func derefStringOrEmpty(p *string) string {
	if p == nil {
		return ""
	}
	return strings.TrimSpace(*p)
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin-only helpers — used by the admin dashboard's Users page.
// ─────────────────────────────────────────────────────────────────────────────

// AdminUserRow is the shape returned to the admin dashboard. Includes a few
// fields beyond the regular User struct that the admin UI cares about
// (joined application count, last activity, etc. could go here later).
type AdminUserRow struct {
	ID                 int64      `json:"id"`
	Email              string     `json:"email"`
	Name               *string    `json:"name,omitempty"`
	Role               string     `json:"role"`
	ExpertID           *string    `json:"expertId,omitempty"`
	SubscriptionTier   string     `json:"subscriptionTier"`
	SubscriptionStatus string     `json:"subscriptionStatus"`
	CreatedAt          time.Time  `json:"createdAt"`
	UpdatedAt          time.Time  `json:"updatedAt"`
}

// ListAdminUsers returns rows newest-first, optionally filtered by a partial
// email/name match (`q`) and a role. Pagination via cursor on id.
func (r *UserRepository) ListAdminUsers(
	q, role string, cursor int64, limit int,
) ([]AdminUserRow, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}

	query := `
		SELECT id, email, name,
		       COALESCE(role, 'USER'),
		       expert_id,
		       COALESCE(subscription_tier, 'FREE'),
		       COALESCE(subscription_status, 'ACTIVE'),
		       created_at, updated_at
		FROM users
		WHERE 1=1
	`
	args := []any{}
	if q != "" {
		args = append(args, "%"+q+"%")
		query += ` AND (email ILIKE $1 OR COALESCE(name,'') ILIKE $1)`
	}
	if role != "" {
		args = append(args, role)
		query += ` AND role = $` + itoa(len(args))
	}
	if cursor > 0 {
		args = append(args, cursor)
		query += ` AND id < $` + itoa(len(args))
	}
	args = append(args, limit)
	query += ` ORDER BY id DESC LIMIT $` + itoa(len(args))

	rows, err := r.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []AdminUserRow
	for rows.Next() {
		var (
			row      AdminUserRow
			name     sql.NullString
			expertID sql.NullString
		)
		if err := rows.Scan(
			&row.ID, &row.Email, &name, &row.Role, &expertID,
			&row.SubscriptionTier, &row.SubscriptionStatus,
			&row.CreatedAt, &row.UpdatedAt,
		); err != nil {
			return nil, err
		}
		if name.Valid {
			row.Name = &name.String
		}
		if expertID.Valid {
			row.ExpertID = &expertID.String
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

// UpdateRole flips a user's role. When promoting USER → EXPERT and
// the user has no expert profile yet, a stub experts row is created so the
// rest of the system keeps its FK invariants. Demotion just flips the role
// (we keep the expert_id link so re-promotion is one click).
//
// Always runs in a transaction. Audit logging happens via the DB trigger
// from migration 0005.
func (r *UserRepository) UpdateRole(userID int64, newRole string) error {
	switch newRole {
	case "USER", "EXPERT", "ADMIN":
	default:
		return fmt.Errorf("invalid role: %s", newRole)
	}

	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Read current state (including expert_id) inside the tx.
	var (
		currentRole sql.NullString
		expertID    sql.NullString
		fullName    sql.NullString
		email       string
	)
	if err := tx.QueryRow(`
		SELECT COALESCE(role,'USER'), expert_id, name, email
		FROM users WHERE id = $1 FOR UPDATE
	`, userID).Scan(&currentRole, &expertID, &fullName, &email); err != nil {
		return err
	}

	// Promotion path: ensure an experts row exists for EXPERT.
	if newRole == "EXPERT" && !expertID.Valid {
		newExpertID := fmt.Sprintf("ex_admin_%d", userID)
		displayName := email
		if fullName.Valid {
			displayName = fullName.String
		}
		if _, err := tx.Exec(`
			INSERT INTO experts (id, name, expertise, bio, tier, subscriber_count)
			VALUES ($1, $2, 'General', '', 'expert', 0)
			ON CONFLICT (id) DO NOTHING
		`, newExpertID, displayName); err != nil {
			return fmt.Errorf("create experts row: %w", err)
		}
		if _, err := tx.Exec(`
			UPDATE users SET role = $1, expert_id = $2, updated_at = NOW()
			WHERE id = $3
		`, newRole, newExpertID, userID); err != nil {
			return fmt.Errorf("promote user: %w", err)
		}
		return tx.Commit()
	}

	// Plain role flip (no expert profile creation needed).
	if _, err := tx.Exec(`
		UPDATE users SET role = $1, updated_at = NOW() WHERE id = $2
	`, newRole, userID); err != nil {
		return fmt.Errorf("update role: %w", err)
	}
	return tx.Commit()
}
