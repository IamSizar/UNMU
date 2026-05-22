package repositories

import (
	"database/sql"
	"errors"
	"strings"
	"time"
)

// CommunityProposalsRepository — CRUD over `community_proposals`
// (migration 0011). Handles three audiences:
//
//   * The expert who proposes a community (Submit + ListMine)
//   * Admin reviewing pending proposals (List + Approve + Reject)
//   * Backend code that needs to look up a single row (GetByID)
//
// On approval the repo also creates the new `communities` row and
// adds the proposer as the owner + first member, all in one
// transaction so a half-failed approve never leaves a dangling
// community_id reference behind.
type CommunityProposalsRepository struct {
	db *sql.DB
}

func NewCommunityProposalsRepository(db *sql.DB) *CommunityProposalsRepository {
	return &CommunityProposalsRepository{db: db}
}

// CommunityProposal mirrors the table row 1:1. Time fields are
// pointers when nullable so the JSON serialisation reads `null` rather
// than the Go zero-time `0001-01-01T00:00:00Z`.
type CommunityProposal struct {
	ID                  int64      `json:"id"`
	UserID              int64      `json:"userId"`
	UserName            string     `json:"userName,omitempty"`
	UserEmail           string     `json:"userEmail,omitempty"`
	Name                string     `json:"name"`
	RegionCode          string     `json:"regionCode,omitempty"`
	Description         string     `json:"description"`
	Status              string     `json:"status"`
	RejectionReason     string     `json:"rejectionReason,omitempty"`
	SubmittedAt         time.Time  `json:"submittedAt"`
	ReviewedAt          *time.Time `json:"reviewedAt,omitempty"`
	ReviewedBy          *int64     `json:"reviewedBy,omitempty"`
	ApprovedCommunityID string     `json:"approvedCommunityId,omitempty"`
}

// ErrPendingExists — submit failed because the user already has a
// pending proposal (the partial unique index in the migration enforces
// this at the DB layer; this is the corresponding Go-level error).
var ErrPendingExists = errors.New("a pending proposal already exists for this user")

// Submit inserts a new proposal in the `pending` state. Returns
// ErrPendingExists if the user already has a pending row.
func (r *CommunityProposalsRepository) Submit(
	userID int64, name, regionCode, description string,
) (*CommunityProposal, error) {
	row := r.db.QueryRow(
		`INSERT INTO community_proposals (user_id, name, region_code, description)
		 VALUES ($1, $2, NULLIF($3, ''), $4)
		 RETURNING id, user_id, name, COALESCE(region_code, ''), description,
		           status, submitted_at`,
		userID, name, regionCode, description,
	)
	var p CommunityProposal
	if err := row.Scan(
		&p.ID, &p.UserID, &p.Name, &p.RegionCode, &p.Description,
		&p.Status, &p.SubmittedAt,
	); err != nil {
		// pq returns 23505 unique_violation — surface as our typed error.
		if strings.Contains(err.Error(), "community_proposals_one_pending_per_user") {
			return nil, ErrPendingExists
		}
		return nil, err
	}
	return &p, nil
}

// ListMine returns every proposal the given user has submitted,
// newest-first. Used by the studio "My proposals" tab so an expert
// can see the status of pending / rejected ones.
func (r *CommunityProposalsRepository) ListMine(userID int64) ([]*CommunityProposal, error) {
	rows, err := r.db.Query(
		`SELECT id, user_id, name, COALESCE(region_code, ''), description,
		        status, COALESCE(rejection_reason, ''), submitted_at,
		        reviewed_at, reviewed_by,
		        COALESCE(approved_community_id, '')
		   FROM community_proposals
		  WHERE user_id = $1
		  ORDER BY submitted_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*CommunityProposal, 0)
	for rows.Next() {
		p, err := scanProposal(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// AdminList returns proposals matching the given status filter,
// newest-first. Empty status returns every row regardless. Joins
// users so the dashboard can render "Sarah Chen" instead of just a
// numeric id.
func (r *CommunityProposalsRepository) AdminList(status string, limit int) ([]*CommunityProposal, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	q := `SELECT cp.id, cp.user_id,
	             COALESCE(NULLIF(u.name, ''), u.email),
	             u.email,
	             cp.name, COALESCE(cp.region_code, ''), cp.description,
	             cp.status, COALESCE(cp.rejection_reason, ''),
	             cp.submitted_at, cp.reviewed_at, cp.reviewed_by,
	             COALESCE(cp.approved_community_id, '')
	        FROM community_proposals cp
	        JOIN users u ON u.id = cp.user_id`
	args := []any{}
	if status != "" {
		args = append(args, status)
		q += ` WHERE cp.status = $1`
	}
	q += ` ORDER BY cp.submitted_at DESC LIMIT ` + itoa(limit)

	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*CommunityProposal, 0)
	for rows.Next() {
		var p CommunityProposal
		if err := rows.Scan(
			&p.ID, &p.UserID, &p.UserName, &p.UserEmail,
			&p.Name, &p.RegionCode, &p.Description,
			&p.Status, &p.RejectionReason,
			&p.SubmittedAt, &p.ReviewedAt, &p.ReviewedBy,
			&p.ApprovedCommunityID,
		); err != nil {
			return nil, err
		}
		out = append(out, &p)
	}
	return out, rows.Err()
}

// GetByID — single proposal lookup. Returns sql.ErrNoRows when the
// id doesn't exist.
//
// Joins users so the response carries UserName + UserEmail (mirrors
// AdminList shape). The admin detail page relies on those for the
// proposer card.
func (r *CommunityProposalsRepository) GetByID(id int64) (*CommunityProposal, error) {
	row := r.db.QueryRow(
		`SELECT cp.id, cp.user_id,
		        COALESCE(NULLIF(u.name, ''), u.email),
		        u.email,
		        cp.name, COALESCE(cp.region_code, ''), cp.description,
		        cp.status, COALESCE(cp.rejection_reason, ''),
		        cp.submitted_at, cp.reviewed_at, cp.reviewed_by,
		        COALESCE(cp.approved_community_id, '')
		   FROM community_proposals cp
		   JOIN users u ON u.id = cp.user_id
		  WHERE cp.id = $1`,
		id,
	)
	var p CommunityProposal
	if err := row.Scan(
		&p.ID, &p.UserID, &p.UserName, &p.UserEmail,
		&p.Name, &p.RegionCode, &p.Description,
		&p.Status, &p.RejectionReason,
		&p.SubmittedAt, &p.ReviewedAt, &p.ReviewedBy,
		&p.ApprovedCommunityID,
	); err != nil {
		return nil, err
	}
	return &p, nil
}

// Approve creates the matching community + sets the proposer as
// owner + auto-adds them as a member, then flips the proposal to
// `approved` with `approved_community_id` filled. Whole thing runs
// in one transaction so a half-failure rolls back cleanly.
//
// Returns the new community id on success.
func (r *CommunityProposalsRepository) Approve(
	proposalID int64, adminUserID int64,
) (string, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return "", err
	}
	defer tx.Rollback() //nolint:errcheck — committed below on success

	// Re-fetch under the tx so we read the latest state. Lock the row
	// to block a concurrent admin from double-approving.
	var p CommunityProposal
	err = tx.QueryRow(
		`SELECT id, user_id, name, COALESCE(region_code, ''), description, status
		   FROM community_proposals WHERE id = $1 FOR UPDATE`,
		proposalID,
	).Scan(&p.ID, &p.UserID, &p.Name, &p.RegionCode, &p.Description, &p.Status)
	if err != nil {
		return "", err
	}
	if p.Status != "pending" {
		return "", errors.New("proposal is not pending")
	}

	// Mint a community id that's stable, lowercase, slug-y. Keeps the
	// `c_*` prefix convention used by the seed data.
	communityID := mintCommunityID(p.Name)

	// Ensure uniqueness — append a numeric suffix if the slug collides.
	finalID := communityID
	for i := 1; i < 10; i++ {
		var exists bool
		_ = tx.QueryRow(`SELECT EXISTS(SELECT 1 FROM communities WHERE id = $1)`, finalID).Scan(&exists)
		if !exists {
			break
		}
		finalID = communityID + "_" + itoa(i)
	}

	// Create the community itself.
	_, err = tx.Exec(
		`INSERT INTO communities (id, name, tagline, region_code, owner_id)
		 VALUES ($1, $2, $3, NULLIF($4, ''), $5)`,
		finalID, p.Name, p.Description, p.RegionCode, p.UserID,
	)
	if err != nil {
		return "", err
	}

	// Owner is automatically a member.
	_, err = tx.Exec(
		`INSERT INTO community_members (user_id, community_id) VALUES ($1, $2)
		 ON CONFLICT DO NOTHING`,
		p.UserID, finalID,
	)
	if err != nil {
		return "", err
	}

	// Mark proposal approved.
	_, err = tx.Exec(
		`UPDATE community_proposals
		    SET status = 'approved',
		        reviewed_at = NOW(),
		        reviewed_by = $1,
		        approved_community_id = $2
		  WHERE id = $3`,
		adminUserID, finalID, proposalID,
	)
	if err != nil {
		return "", err
	}

	if err := tx.Commit(); err != nil {
		return "", err
	}
	return finalID, nil
}

// Reject flips the proposal to `rejected` with a (required) reason
// and a reviewer audit trail. No community is created.
func (r *CommunityProposalsRepository) Reject(
	proposalID int64, adminUserID int64, reason string,
) error {
	res, err := r.db.Exec(
		`UPDATE community_proposals
		    SET status = 'rejected',
		        reviewed_at = NOW(),
		        reviewed_by = $1,
		        rejection_reason = $2
		  WHERE id = $3 AND status = 'pending'`,
		adminUserID, reason, proposalID,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return errors.New("proposal not found or already reviewed")
	}
	return nil
}

// PendingCount — drives the dashboard sidebar badge.
func (r *CommunityProposalsRepository) PendingCount() (int, error) {
	var n int
	err := r.db.QueryRow(
		`SELECT COUNT(*) FROM community_proposals WHERE status = 'pending'`,
	).Scan(&n)
	return n, err
}

// ─── helpers ─────────────────────────────────────────────────────────

type proposalScanner interface {
	Scan(dest ...any) error
}

func scanProposal(s proposalScanner) (*CommunityProposal, error) {
	var p CommunityProposal
	err := s.Scan(
		&p.ID, &p.UserID, &p.Name, &p.RegionCode, &p.Description,
		&p.Status, &p.RejectionReason, &p.SubmittedAt,
		&p.ReviewedAt, &p.ReviewedBy,
		&p.ApprovedCommunityID,
	)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

// mintCommunityID — slugify name into something safe + recognisable
// as a community id. Format: c_<lowercased-no-special-chars>.
// Examples: "Halal Tech Saudi" → "c_halal_tech_saudi"
func mintCommunityID(name string) string {
	var b strings.Builder
	b.WriteString("c_")
	prevUnderscore := true
	for _, r := range strings.ToLower(name) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
			prevUnderscore = false
		case (r == ' ' || r == '-' || r == '_') && !prevUnderscore:
			b.WriteByte('_')
			prevUnderscore = true
		}
	}
	out := b.String()
	if out == "c_" {
		out = "c_unnamed"
	}
	if len(out) > 40 {
		out = out[:40]
	}
	return strings.TrimRight(out, "_")
}
