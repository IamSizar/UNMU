// Package repositories — community co-ownership + invitation handshake
// (migration 0032).
//
// Two-table model:
//
//   community_invitations  — pending/accepted/rejected handshake rows
//   community_owners       — the resolved co-owners (additional to
//                            communities.owner_id, which is the primary)
//
// All accept/reject transitions are wrapped in a transaction so the
// invitation status + the community_owners insertion stay consistent.
package repositories

import (
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// ── Models ─────────────────────────────────────────────────────────

// CommunityInvitation mirrors one row of community_invitations. The
// JSON-tagged fields match exactly what the mobile + admin clients
// consume — name them carefully because changing them is a breaking
// API change.
type CommunityInvitation struct {
	ID            int64     `json:"id"`
	CommunityID   string    `json:"communityId"`
	CommunityName string    `json:"communityName,omitempty"`
	InvitedUserID int64     `json:"invitedUserId"`
	InvitedUserEmail string `json:"invitedUserEmail,omitempty"`
	InvitedUserName  string `json:"invitedUserName,omitempty"`
	InvitedBy     int64     `json:"invitedBy"`
	InvitedByName string    `json:"invitedByName,omitempty"`
	Status        string    `json:"status"`
	Message       string    `json:"message,omitempty"`
	CreatedAt     time.Time `json:"createdAt"`
	ResolvedAt    *time.Time `json:"resolvedAt,omitempty"`
}

// CommunityCoOwner mirrors one row of community_owners + user details
// for display. Always returned WITHOUT the primary owner — that one is
// implicit via communities.owner_id.
type CommunityCoOwner struct {
	CommunityID string    `json:"communityId"`
	UserID      int64     `json:"userId"`
	Name        string    `json:"name"`
	Email       string    `json:"email"`
	ExpertID    string    `json:"expertId,omitempty"`
	GrantedAt   time.Time `json:"grantedAt"`
	GrantedBy   *int64    `json:"grantedBy,omitempty"`
}

// CommunityOwnersRepo wraps the two tables. No state — just methods.
type CommunityOwnersRepo struct {
	db *sql.DB
}

func NewCommunityOwnersRepo(db *sql.DB) *CommunityOwnersRepo {
	return &CommunityOwnersRepo{db: db}
}

// Sentinel errors so handlers can map them to specific HTTP codes
// without string-matching the underlying DB error.
var (
	// Already a pending invitation for (community, user).
	ErrInvitationAlreadyPending = errors.New("invitation already pending")
	// Tried to invite the primary owner or an existing co-owner.
	ErrAlreadyOwner = errors.New("user is already an owner")
	// Invitee is not an EXPERT — only experts can be invited as
	// co-owners. Keeps the model coherent.
	ErrInviteeNotExpert = errors.New("invited user must be an EXPERT")
	// Invitation moved out of `pending` before the caller could act.
	ErrInvitationNotPending = errors.New("invitation is no longer pending")
	// Caller tried to act on an invitation they don't own.
	ErrInvitationWrongUser = errors.New("invitation does not belong to caller")
)

// ─────────────────────────────────────────────────────────────────────
// Invitation lifecycle
// ─────────────────────────────────────────────────────────────────────

// CreateInvitation — primary owner (or existing co-owner) invites an
// expert to become a co-owner of the community.
//
// Validates:
//   * invitedUserID has role=EXPERT
//   * invitedUserID is not already an owner of the community
//   * no pending invitation exists for (community, invitee)
//
// Returns the newly-inserted row.
func (r *CommunityOwnersRepo) CreateInvitation(
	communityID string,
	invitedUserID int64,
	invitedBy int64,
	message string,
) (*CommunityInvitation, error) {
	// Confirm the invitee is an EXPERT. Anyone else can't take on
	// expert-tier responsibilities inside a community.
	var role string
	err := r.db.QueryRow(`SELECT role FROM users WHERE id = $1`, invitedUserID).Scan(&role)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("invited user not found")
	}
	if err != nil {
		return nil, err
	}
	if role != "EXPERT" {
		return nil, ErrInviteeNotExpert
	}

	// Already an owner? (Either primary or co-owner.)
	already, err := r.IsAnyOwner(communityID, invitedUserID)
	if err != nil {
		return nil, err
	}
	if already {
		return nil, ErrAlreadyOwner
	}

	// Insert the invitation. The partial-unique index on
	// (community_id, invited_user_id) WHERE status='pending'
	// surfaces ErrInvitationAlreadyPending if a pending row exists.
	inv := &CommunityInvitation{}
	err = r.db.QueryRow(`
		INSERT INTO community_invitations (community_id, invited_user_id, invited_by, message)
		VALUES ($1, $2, $3, NULLIF($4, ''))
		RETURNING id, community_id, invited_user_id, invited_by, status, COALESCE(message,''), created_at, resolved_at
	`, communityID, invitedUserID, invitedBy, message).Scan(
		&inv.ID, &inv.CommunityID, &inv.InvitedUserID, &inv.InvitedBy,
		&inv.Status, &inv.Message, &inv.CreatedAt, &inv.ResolvedAt,
	)
	if err != nil {
		// pq unique violation = pending row already exists.
		if isUniqueViolation(err) {
			return nil, ErrInvitationAlreadyPending
		}
		return nil, err
	}
	return inv, nil
}

// ListIncoming — invitations addressed to userID, default to pending
// only (UI shows them in an inbox).
func (r *CommunityOwnersRepo) ListIncoming(userID int64, status string) ([]*CommunityInvitation, error) {
	q := `
		SELECT i.id, i.community_id, COALESCE(c.name, i.community_id) AS community_name,
		       i.invited_user_id,
		       i.invited_by, COALESCE(uinv.name, uinv.email) AS invited_by_name,
		       i.status, COALESCE(i.message,''),
		       i.created_at, i.resolved_at
		FROM community_invitations i
		LEFT JOIN communities c ON c.id = i.community_id
		LEFT JOIN users uinv ON uinv.id = i.invited_by
		WHERE i.invited_user_id = $1
	`
	args := []any{userID}
	if status != "" {
		q += " AND i.status = $2"
		args = append(args, status)
	}
	q += " ORDER BY i.created_at DESC LIMIT 100"
	return r.scanInvitations(q, args...)
}

// ListForCommunity — invitations sent FROM a community. Useful for the
// admin Community Detail page and for an "Outbox" view on the owner's
// settings screen.
func (r *CommunityOwnersRepo) ListForCommunity(communityID, status string) ([]*CommunityInvitation, error) {
	q := `
		SELECT i.id, i.community_id, COALESCE(c.name, i.community_id) AS community_name,
		       i.invited_user_id,
		       i.invited_by, COALESCE(uinv.name, uinv.email) AS invited_by_name,
		       i.status, COALESCE(i.message,''),
		       i.created_at, i.resolved_at
		FROM community_invitations i
		LEFT JOIN communities c ON c.id = i.community_id
		LEFT JOIN users uinv ON uinv.id = i.invited_by
		WHERE i.community_id = $1
	`
	args := []any{communityID}
	if status != "" {
		q += " AND i.status = $2"
		args = append(args, status)
	}
	q += " ORDER BY i.created_at DESC LIMIT 100"
	return r.scanInvitations(q, args...)
}

func (r *CommunityOwnersRepo) scanInvitations(q string, args ...any) ([]*CommunityInvitation, error) {
	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*CommunityInvitation
	for rows.Next() {
		inv := &CommunityInvitation{}
		var byName sql.NullString
		if err := rows.Scan(
			&inv.ID, &inv.CommunityID, &inv.CommunityName,
			&inv.InvitedUserID,
			&inv.InvitedBy, &byName,
			&inv.Status, &inv.Message,
			&inv.CreatedAt, &inv.ResolvedAt,
		); err != nil {
			return nil, err
		}
		if byName.Valid {
			inv.InvitedByName = byName.String
		}
		out = append(out, inv)
	}
	return out, rows.Err()
}

// AcceptInvitation — invitee accepts. Atomically:
//   1. Move invitation to status='accepted'
//   2. Insert community_owners row
//
// Both happen in one transaction so a half-success is impossible.
// `callerID` MUST be the invitee — handler enforces this.
func (r *CommunityOwnersRepo) AcceptInvitation(invID, callerID int64) (*CommunityInvitation, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback() // safe — Rollback after Commit is a no-op

	inv := &CommunityInvitation{}
	err = tx.QueryRow(`
		SELECT id, community_id, invited_user_id, invited_by, status,
		       COALESCE(message,''), created_at, resolved_at
		FROM community_invitations
		WHERE id = $1
		FOR UPDATE
	`, invID).Scan(
		&inv.ID, &inv.CommunityID, &inv.InvitedUserID, &inv.InvitedBy,
		&inv.Status, &inv.Message, &inv.CreatedAt, &inv.ResolvedAt,
	)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("invitation not found")
	}
	if err != nil {
		return nil, err
	}
	if inv.InvitedUserID != callerID {
		return nil, ErrInvitationWrongUser
	}
	if inv.Status != "pending" {
		return nil, ErrInvitationNotPending
	}

	// Mark accepted.
	now := time.Now()
	_, err = tx.Exec(`
		UPDATE community_invitations
		SET status='accepted', resolved_at=$1
		WHERE id=$2
	`, now, invID)
	if err != nil {
		return nil, err
	}
	inv.Status = "accepted"
	inv.ResolvedAt = &now

	// Insert co-owner row. ON CONFLICT DO NOTHING covers the corner
	// case where the invitee was concurrently promoted via another
	// path (admin tool, etc).
	_, err = tx.Exec(`
		INSERT INTO community_owners (community_id, user_id, granted_by)
		VALUES ($1, $2, $3)
		ON CONFLICT (community_id, user_id) DO NOTHING
	`, inv.CommunityID, inv.InvitedUserID, inv.InvitedBy)
	if err != nil {
		return nil, err
	}

	// Auto-join as a member too. A co-owner who can't see the
	// community's content + chat would be a bizarre state. This is
	// the same effect as if the user had tapped "Join" before
	// accepting; the row is idempotent (community_members has a
	// composite PK) so re-joining a community they're already in
	// is a no-op.
	_, err = tx.Exec(`
		INSERT INTO community_members (community_id, user_id)
		VALUES ($1, $2)
		ON CONFLICT (user_id, community_id) DO NOTHING
	`, inv.CommunityID, inv.InvitedUserID)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return inv, nil
}

// RejectInvitation — invitee declines. Status → 'rejected'.
func (r *CommunityOwnersRepo) RejectInvitation(invID, callerID int64) (*CommunityInvitation, error) {
	return r.transitionInvitation(invID, callerID, "rejected", true /*mustBeInvitee*/)
}

// CancelInvitation — owner withdraws a pending invitation before the
// invitee responds. Caller must be the invited_by user OR an admin
// (admin path enforced at the handler).
func (r *CommunityOwnersRepo) CancelInvitation(invID, callerID int64) (*CommunityInvitation, error) {
	return r.transitionInvitation(invID, callerID, "cancelled", false /*mustBeInvitee*/)
}

func (r *CommunityOwnersRepo) transitionInvitation(
	invID, callerID int64,
	newStatus string,
	mustBeInvitee bool,
) (*CommunityInvitation, error) {
	inv := &CommunityInvitation{}
	err := r.db.QueryRow(`
		SELECT id, community_id, invited_user_id, invited_by, status,
		       COALESCE(message,''), created_at, resolved_at
		FROM community_invitations
		WHERE id=$1
	`, invID).Scan(
		&inv.ID, &inv.CommunityID, &inv.InvitedUserID, &inv.InvitedBy,
		&inv.Status, &inv.Message, &inv.CreatedAt, &inv.ResolvedAt,
	)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("invitation not found")
	}
	if err != nil {
		return nil, err
	}
	if mustBeInvitee && inv.InvitedUserID != callerID {
		return nil, ErrInvitationWrongUser
	}
	if !mustBeInvitee && inv.InvitedBy != callerID {
		// Cancel path — only the inviter may cancel (handler can
		// allow admins via a separate path).
		return nil, ErrInvitationWrongUser
	}
	if inv.Status != "pending" {
		return nil, ErrInvitationNotPending
	}
	now := time.Now()
	_, err = r.db.Exec(`
		UPDATE community_invitations
		SET status=$1, resolved_at=$2
		WHERE id=$3
	`, newStatus, now, invID)
	if err != nil {
		return nil, err
	}
	inv.Status = newStatus
	inv.ResolvedAt = &now
	return inv, nil
}

// ─────────────────────────────────────────────────────────────────────
// Co-owner queries + management
// ─────────────────────────────────────────────────────────────────────

// ListCoOwners — community_owners + user details, ordered newest first.
// Does NOT include the primary owner; the caller should union with
// communities.owner_id if they want the full picture.
func (r *CommunityOwnersRepo) ListCoOwners(communityID string) ([]*CommunityCoOwner, error) {
	rows, err := r.db.Query(`
		SELECT co.community_id,
		       co.user_id,
		       COALESCE(u.name, u.email) AS name,
		       u.email,
		       COALESCE(u.expert_id, '') AS expert_id,
		       co.granted_at,
		       co.granted_by
		FROM community_owners co
		JOIN users u ON u.id = co.user_id
		WHERE co.community_id = $1
		ORDER BY co.granted_at DESC
	`, communityID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*CommunityCoOwner
	for rows.Next() {
		o := &CommunityCoOwner{}
		var grantedBy sql.NullInt64
		if err := rows.Scan(
			&o.CommunityID, &o.UserID, &o.Name, &o.Email,
			&o.ExpertID, &o.GrantedAt, &grantedBy,
		); err != nil {
			return nil, err
		}
		if grantedBy.Valid {
			v := grantedBy.Int64
			o.GrantedBy = &v
		}
		out = append(out, o)
	}
	return out, rows.Err()
}

// IsCoOwner — does (community, user) have a row in community_owners?
// Cheap point query; safe to call inline from authz checks.
func (r *CommunityOwnersRepo) IsCoOwner(communityID string, userID int64) (bool, error) {
	var n int
	err := r.db.QueryRow(`
		SELECT 1 FROM community_owners
		WHERE community_id=$1 AND user_id=$2
	`, communityID, userID).Scan(&n)
	if err == sql.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// IsAnyOwner — primary OR co-owner. Single query that unions
// communities.owner_id with community_owners.
func (r *CommunityOwnersRepo) IsAnyOwner(communityID string, userID int64) (bool, error) {
	var n int
	err := r.db.QueryRow(`
		SELECT 1 FROM communities WHERE id=$1 AND owner_id=$2
		UNION ALL
		SELECT 1 FROM community_owners WHERE community_id=$1 AND user_id=$2
		LIMIT 1
	`, communityID, userID).Scan(&n)
	if err == sql.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// RemoveCoOwner — primary owner demotes a co-owner. Handler verifies
// the caller is the primary owner of the community.
func (r *CommunityOwnersRepo) RemoveCoOwner(communityID string, userID int64) error {
	res, err := r.db.Exec(`
		DELETE FROM community_owners
		WHERE community_id=$1 AND user_id=$2
	`, communityID, userID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// LookupUserByExpertID — given a public expert id like "ex_26", return
// the underlying users.id. Used by the invitation handler so the
// mobile app can pass an expert id (which is what /api/experts
// surfaces) without exposing user_id in the public payload.
func (r *CommunityOwnersRepo) LookupUserByExpertID(expertID string) (int64, error) {
	var uid int64
	err := r.db.QueryRow(
		`SELECT id FROM users WHERE expert_id = $1 AND role = 'EXPERT'`,
		expertID,
	).Scan(&uid)
	if err == sql.ErrNoRows {
		return 0, fmt.Errorf("expert not found")
	}
	return uid, err
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

// isUniqueViolation — Postgres SQLSTATE 23505. Used to surface
// "pending invitation already exists" as a typed error instead of a
// raw DB string.
func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	// We avoid pulling pq.Error to keep the build stable across the
	// db driver upgrades; string-matching the SQLSTATE is safe — the
	// driver always sets pq: ... 23505 ... when uniqueness is violated.
	return errStringContains(err.Error(), "23505")
}

func errStringContains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
