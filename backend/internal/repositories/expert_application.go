package repositories

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"halalstocks/internal/models"
	"strings"
	"time"
)

// ExpertApplicationRepository persists rows in expert_applications.
//
// `s3` is optional — when wired, every read path rewrites the resume PDF
// and avatar URLs through the sign-on-read resolver so admin reviewers
// never hit a 403 on a stale signature.
type ExpertApplicationRepository struct {
	db *sql.DB
	s3 MediaURLResolver
}

func NewExpertApplicationRepository(db *sql.DB) *ExpertApplicationRepository {
	return &ExpertApplicationRepository{db: db}
}

// SetS3Storage wires the URL resolver; nil disables it.
func (r *ExpertApplicationRepository) SetS3Storage(s3 MediaURLResolver) {
	r.s3 = s3
}

// resolveAppURL refreshes resume + avatar URLs on a single application
// (pointer so the call site can pass &app for value-slice elements via
// `for i := range out { r.resolveAppURL(&out[i]) }`). No-op when r.s3
// is nil or the input is nil.
func (r *ExpertApplicationRepository) resolveAppURL(a *models.ExpertApplication) {
	if r.s3 == nil || a == nil {
		return
	}
	if a.ResumeURL != nil && *a.ResumeURL != "" {
		v := r.s3.MediaURL(*a.ResumeURL)
		a.ResumeURL = &v
	}
	if a.AvatarURL != nil && *a.AvatarURL != "" {
		v := r.s3.MediaURL(*a.AvatarURL)
		a.AvatarURL = &v
	}
}

// =============================================================================
// Sentinel errors — surfaced through the handler as typed HTTP statuses.
// =============================================================================

// ErrPendingApplicationExists is returned by Create when the user already has
// a pending application — the partial unique index in the DB enforces this.
var ErrPendingApplicationExists = errors.New("a pending application already exists for this user")

// ErrApplicationNotPending — admin tried to Approve/Reject a row that is
// already approved or rejected. Maps to HTTP 409.
var ErrApplicationNotPending = errors.New("application is not pending")

// ErrReapplyTooSoon — the user has a recent rejection inside the
// `reapplyCooldown` window. Maps to HTTP 429 with a `retryAfterSeconds`.
var ErrReapplyTooSoon = errors.New("must wait before re-applying after a rejection")

// reapplyCooldown — how long after a rejection the user must wait before
// submitting again. 7 days is generous enough that admins aren't flooded
// but doesn't punish someone with a one-line credential fix.
const reapplyCooldown = 7 * 24 * time.Hour

// =============================================================================
// Column lists — kept in one place so all the readers stay in lockstep with
// `ScanExpertApplication` in models/expert_application.go.
// =============================================================================

const baseSelect = `
	SELECT id, user_id, full_name, expertise, bio,
	       credentials, country, sample_links,
	       status, rejection_reason, submitted_at, reviewed_at, reviewed_by,
	       resume_url, avatar_url
	FROM expert_applications
`

// =============================================================================
// Mutators
// =============================================================================

// Create inserts a new application.
//
// Rejects (with ErrPendingApplicationExists) if the user already has a
// pending row — partial unique index enforces it. Also rejects (with
// ErrReapplyTooSoon + retryAfter duration) if the user was rejected
// recently and is inside the cool-down window.
func (r *ExpertApplicationRepository) Create(app *models.ExpertApplication) (retryAfter time.Duration, err error) {
	// Cool-down check (A10) — read latest rejected row, if it's within
	// the window, refuse and return how long to wait.
	var lastRejectedAt sql.NullTime
	if err := r.db.QueryRow(`
		SELECT reviewed_at
		  FROM expert_applications
		 WHERE user_id = $1 AND status = 'rejected'
		 ORDER BY submitted_at DESC
		 LIMIT 1
	`, app.UserID).Scan(&lastRejectedAt); err != nil && !errors.Is(err, sql.ErrNoRows) {
		return 0, err
	}
	if lastRejectedAt.Valid {
		elapsed := time.Since(lastRejectedAt.Time)
		if elapsed < reapplyCooldown {
			return reapplyCooldown - elapsed, ErrReapplyTooSoon
		}
	}

	credsJSON, _ := json.Marshal(app.Credentials)
	linksJSON, _ := json.Marshal(app.SampleLinks)

	var country sql.NullString
	if app.Country != nil {
		country = sql.NullString{String: *app.Country, Valid: true}
	}
	var resumeURL sql.NullString
	if app.ResumeURL != nil && *app.ResumeURL != "" {
		resumeURL = sql.NullString{String: *app.ResumeURL, Valid: true}
	}
	var avatarURL sql.NullString
	if app.AvatarURL != nil && *app.AvatarURL != "" {
		avatarURL = sql.NullString{String: *app.AvatarURL, Valid: true}
	}

	query := `
		INSERT INTO expert_applications
			(user_id, full_name, expertise, bio, credentials,
			 country, sample_links, resume_url, avatar_url)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING id, status, submitted_at
	`
	if err := r.db.QueryRow(query,
		app.UserID, app.FullName, app.Expertise, app.Bio,
		credsJSON, country, linksJSON, resumeURL, avatarURL,
	).Scan(&app.ID, &app.Status, &app.SubmittedAt); err != nil {
		if strings.Contains(err.Error(), "expert_applications_one_pending_per_user") {
			return 0, ErrPendingApplicationExists
		}
		return 0, err
	}
	return 0, nil
}

// Withdraw — DELETE for the applicant's own pending row (A9).
//
// Returns sql.ErrNoRows if the application doesn't exist, isn't owned by
// the caller, or isn't pending. The caller maps that to 404/403/409.
func (r *ExpertApplicationRepository) Withdraw(appID, userID int64) error {
	res, err := r.db.Exec(`
		DELETE FROM expert_applications
		 WHERE id = $1 AND user_id = $2 AND status = 'pending'
	`, appID, userID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// =============================================================================
// Readers
// =============================================================================

// LatestForUser returns the most recent application for a user (any status),
// or nil if they've never applied.
func (r *ExpertApplicationRepository) LatestForUser(userID int64) (*models.ExpertApplication, error) {
	row := r.db.QueryRow(baseSelect+`
		WHERE user_id = $1
		ORDER BY submitted_at DESC
		LIMIT 1
	`, userID)
	app, err := models.ScanExpertApplication(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return app, err
}

// GetByID fetches a single application.
func (r *ExpertApplicationRepository) GetByID(id int64) (*models.ExpertApplication, error) {
	row := r.db.QueryRow(baseSelect+` WHERE id = $1`, id)
	app, err := models.ScanExpertApplication(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return app, err
}

// AdminListFilter — search / pagination knobs for the admin Applications page.
//
// Status filter is exact-match. Query searches user email + full name (ILIKE).
// Cursor is the last id from the previous page; rows older than that id are
// returned. Limit is clamped to [1, 100].
type AdminListFilter struct {
	Status string
	Query  string
	Cursor int64
	Limit  int
}

// ListByStatus — admin list with optional status filter, search box, and
// keyset pagination by id-desc.
func (r *ExpertApplicationRepository) ListByStatus(filter AdminListFilter) ([]models.ExpertApplication, error) {
	limit := filter.Limit
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	q := `
		SELECT a.id, a.user_id, a.full_name, a.expertise, a.bio,
		       a.credentials, a.country, a.sample_links,
		       a.status, a.rejection_reason, a.submitted_at, a.reviewed_at, a.reviewed_by,
		       a.resume_url, a.avatar_url,
		       u.email, COALESCE(u.avatar_url, ''),
		       COALESCE(reviewer.email, '')
		FROM expert_applications a
		JOIN users u ON u.id = a.user_id
		LEFT JOIN users reviewer ON reviewer.id = a.reviewed_by
	`
	args := []any{}
	conds := []string{}
	if filter.Status != "" {
		args = append(args, filter.Status)
		conds = append(conds, fmt.Sprintf("a.status = $%d", len(args)))
	}
	if s := strings.TrimSpace(filter.Query); s != "" {
		args = append(args, "%"+s+"%")
		conds = append(conds, fmt.Sprintf(
			"(u.email ILIKE $%d OR a.full_name ILIKE $%d)",
			len(args), len(args),
		))
	}
	if filter.Cursor > 0 {
		args = append(args, filter.Cursor)
		conds = append(conds, fmt.Sprintf("a.id < $%d", len(args)))
	}
	if len(conds) > 0 {
		q += " WHERE " + strings.Join(conds, " AND ")
	}
	args = append(args, limit)
	q += fmt.Sprintf(" ORDER BY a.id DESC LIMIT $%d", len(args))

	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.ExpertApplication
	for rows.Next() {
		var (
			a               models.ExpertApplication
			country         sql.NullString
			credentialsRaw  []byte
			sampleLinksRaw  []byte
			rejectionReason sql.NullString
			reviewedAt      sql.NullTime
			reviewedBy      sql.NullInt64
			resumeURL       sql.NullString
			avatarURL       sql.NullString
		)
		if err := rows.Scan(
			&a.ID, &a.UserID, &a.FullName, &a.Expertise, &a.Bio,
			&credentialsRaw, &country, &sampleLinksRaw,
			&a.Status, &rejectionReason, &a.SubmittedAt, &reviewedAt, &reviewedBy,
			&resumeURL, &avatarURL,
			&a.UserEmail, &a.UserAvatar,
			&a.ReviewerEmail,
		); err != nil {
			return nil, err
		}
		if country.Valid {
			a.Country = &country.String
		}
		if rejectionReason.Valid {
			a.RejectionReason = &rejectionReason.String
		}
		if reviewedAt.Valid {
			a.ReviewedAt = &reviewedAt.Time
		}
		if reviewedBy.Valid {
			a.ReviewedBy = &reviewedBy.Int64
		}
		if resumeURL.Valid {
			a.ResumeURL = &resumeURL.String
		}
		if avatarURL.Valid {
			a.AvatarURL = &avatarURL.String
		}
		_ = json.Unmarshal(credentialsRaw, &a.Credentials)
		_ = json.Unmarshal(sampleLinksRaw, &a.SampleLinks)
		if a.Credentials == nil {
			a.Credentials = []string{}
		}
		if a.SampleLinks == nil {
			a.SampleLinks = []string{}
		}
		out = append(out, a)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for i := range out {
		r.resolveAppURL(&out[i])
	}
	return out, nil
}

// PendingCount — fast COUNT(*) for the sidebar badge (A12).
func (r *ExpertApplicationRepository) PendingCount() (int, error) {
	var n int
	err := r.db.QueryRow(
		`SELECT COUNT(*) FROM expert_applications WHERE status = 'pending'`,
	).Scan(&n)
	return n, err
}

// =============================================================================
// State transitions — Approve / Reject / Demote
// =============================================================================

// Approve promotes the applicant to EXPERT in a single transaction:
//
//  1. Insert a new row in `experts` (id derived from app.id), seeded with
//     the application data (name, expertise, bio).
//  2. Set users.role='EXPERT', users.expert_id=<new id>, copy missing
//     fields onto the user row (name, country, bio).
//  3. Update the application row (status, reviewed_at, reviewed_by).
//
// Returns ErrApplicationNotPending so the handler can map to 409.
func (r *ExpertApplicationRepository) Approve(appID, reviewerID int64) (*models.ExpertApplication, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// Lock the row and read it.
	var app models.ExpertApplication
	var (
		country         sql.NullString
		credentialsRaw  []byte
		sampleLinksRaw  []byte
		rejectionReason sql.NullString
		reviewedAt      sql.NullTime
		reviewedBy      sql.NullInt64
		resumeURL       sql.NullString
		avatarURL       sql.NullString
	)
	err = tx.QueryRow(baseSelect+` WHERE id = $1 FOR UPDATE`, appID).Scan(
		&app.ID, &app.UserID, &app.FullName, &app.Expertise, &app.Bio,
		&credentialsRaw, &country, &sampleLinksRaw,
		&app.Status, &rejectionReason, &app.SubmittedAt, &reviewedAt, &reviewedBy,
		&resumeURL, &avatarURL,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if app.Status != models.ApplicationStatusPending {
		return nil, ErrApplicationNotPending
	}
	if country.Valid {
		app.Country = &country.String
	}
	if resumeURL.Valid {
		app.ResumeURL = &resumeURL.String
	}
	if avatarURL.Valid {
		app.AvatarURL = &avatarURL.String
	}
	r.resolveAppURL(&app)
	_ = json.Unmarshal(credentialsRaw, &app.Credentials)
	_ = json.Unmarshal(sampleLinksRaw, &app.SampleLinks)
	if app.Credentials == nil {
		app.Credentials = []string{}
	}
	if app.SampleLinks == nil {
		app.SampleLinks = []string{}
	}

	// Generate an expert id like "ex_42" based on the application id.
	expertID := fmt.Sprintf("ex_%d", app.ID)

	// 1. Create the experts row.
	if _, err := tx.Exec(`
		INSERT INTO experts (id, name, expertise, bio, tier, subscriber_count)
		VALUES ($1, $2, $3, $4, 'expert', 0)
		ON CONFLICT (id) DO NOTHING
	`, expertID, app.FullName, app.Expertise, app.Bio); err != nil {
		return nil, fmt.Errorf("create expert row: %w", err)
	}

	// 2. Promote the user. Copy fullName onto users.name (only if empty),
	//    country onto users.country (if column exists in your schema —
	//    we use COALESCE so it's a no-op when it doesn't), bio over.
	//    Avatar is copied from the application's avatar_url onto
	//    users.avatar_url (only if user has none yet).
	var avatarArg sql.NullString
	if avatarURL.Valid {
		avatarArg = avatarURL
	}
	if _, err := tx.Exec(`
		UPDATE users
		   SET role       = 'EXPERT',
		       expert_id  = $1,
		       name       = COALESCE(NULLIF(name, ''), $2),
		       bio        = COALESCE(NULLIF(bio,  ''), $3),
		       avatar_url = COALESCE(NULLIF(avatar_url, ''), $4),
		       updated_at = NOW()
		 WHERE id = $5
	`, expertID, app.FullName, app.Bio, avatarArg, app.UserID); err != nil {
		return nil, fmt.Errorf("promote user: %w", err)
	}

	// 3. Mark the application approved.
	now := time.Now()
	if _, err := tx.Exec(`
		UPDATE expert_applications
		   SET status      = 'approved',
		       reviewed_at = $1,
		       reviewed_by = $2
		 WHERE id = $3
	`, now, reviewerID, app.ID); err != nil {
		return nil, fmt.Errorf("update application: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	app.Status = models.ApplicationStatusApproved
	app.ReviewedAt = &now
	app.ReviewedBy = &reviewerID
	return &app, nil
}

// Reject marks an application rejected with an optional reason. Returns
// ErrApplicationNotPending if the row exists but isn't pending; nil
// (no row) means the row doesn't exist.
func (r *ExpertApplicationRepository) Reject(appID, reviewerID int64, reason string) (*models.ExpertApplication, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// Lock + status check, mirrors Approve so two admins can't race.
	var status string
	if err := tx.QueryRow(
		`SELECT status FROM expert_applications WHERE id = $1 FOR UPDATE`,
		appID,
	).Scan(&status); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	if status != models.ApplicationStatusPending {
		return nil, ErrApplicationNotPending
	}

	now := time.Now()
	var reasonArg sql.NullString
	if reason != "" {
		reasonArg = sql.NullString{String: reason, Valid: true}
	}
	if _, err := tx.Exec(`
		UPDATE expert_applications
		   SET status           = 'rejected',
		       rejection_reason = $1,
		       reviewed_at      = $2,
		       reviewed_by      = $3
		 WHERE id = $4
	`, reasonArg, now, reviewerID, appID); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return r.GetByID(appID)
}

// DemoteExpert — admin override that flips an EXPERT user back to USER and
// nullifies their `expert_id`. Used for typo recovery on Approve. Soft —
// the `experts` row stays in place so historical posts/subs don't FK-fail.
//
// Returns sql.ErrNoRows if the user doesn't exist or isn't an expert.
func (r *ExpertApplicationRepository) DemoteExpert(userID int64) error {
	res, err := r.db.Exec(`
		UPDATE users
		   SET role       = 'USER',
		       expert_id  = NULL,
		       updated_at = NOW()
		 WHERE id = $1 AND role = 'EXPERT'
	`, userID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}
