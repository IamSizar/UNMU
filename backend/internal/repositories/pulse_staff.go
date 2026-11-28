package repositories

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"halalstocks/internal/models"
	"halalstocks/internal/pulse"
)

// =============================================================================
// pulse_staff.go — who may do what in the Pulse CMS, and the basic analytics.
//
// Roles are read from the database on every request (never trusted from the
// login token), the same way RequireAdmin works: a role can be granted or
// removed at any time and takes effect immediately.
// =============================================================================

// ActorFor loads a user's Pulse permissions: system admin (users.role =
// 'ADMIN') plus any rows in pulse_staff.
func (r *PulseAdminRepository) ActorFor(ctx context.Context, userID int64) (pulse.Actor, error) {
	actor := pulse.Actor{UserID: userID, Roles: map[string]bool{}}

	var role string
	err := r.db.QueryRowContext(ctx, `SELECT role FROM users WHERE id = $1`, userID).Scan(&role)
	if err == sql.ErrNoRows {
		return actor, nil // unknown user: no permissions
	}
	if err != nil {
		return actor, fmt.Errorf("loading user role: %w", err)
	}
	actor.IsAdmin = role == "ADMIN"

	rows, err := r.db.QueryContext(ctx, `SELECT pulse_role FROM pulse_staff WHERE user_id = $1`, userID)
	if err != nil {
		return actor, fmt.Errorf("loading pulse roles: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var pr string
		if err := rows.Scan(&pr); err != nil {
			return actor, fmt.Errorf("reading pulse role: %w", err)
		}
		actor.Roles[pr] = true
	}
	return actor, rows.Err()
}

// ListStaff returns every Pulse role assignment with the user's email.
func (r *PulseAdminRepository) ListStaff(ctx context.Context) ([]models.PulseStaffMember, error) {
	rows, err := r.db.QueryContext(ctx,
		`SELECT s.id, s.user_id, u.email, s.pulse_role, s.created_at
		   FROM pulse_staff s JOIN users u ON u.id = s.user_id
		  ORDER BY u.email, s.pulse_role`)
	if err != nil {
		return nil, fmt.Errorf("listing pulse staff: %w", err)
	}
	defer rows.Close()
	out := []models.PulseStaffMember{}
	for rows.Next() {
		var m models.PulseStaffMember
		if err := rows.Scan(&m.ID, &m.UserID, &m.Email, &m.Role, &m.CreatedAt); err != nil {
			return nil, fmt.Errorf("scanning pulse staff: %w", err)
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// AddStaff gives the user with this email a Pulse role. Adding a role the
// user already has is a no-op. The caller must be a system admin.
func (r *PulseAdminRepository) AddStaff(ctx context.Context, email, role string, by int64) error {
	switch role {
	case models.PulseRoleEditor, models.PulseRoleReviewer, models.PulseRoleApprover:
	default:
		return &pulse.RuleError{Kind: "invalid", Message: "Unknown role",
			Fields: pulse.FieldErrors{"role": "Choose editor, reviewer or approver"}}
	}
	var userID int64
	err := r.db.QueryRowContext(ctx,
		`SELECT id FROM users WHERE LOWER(email) = $1 AND deleted_at IS NULL`,
		strings.ToLower(strings.TrimSpace(email))).Scan(&userID)
	if err == sql.ErrNoRows {
		return &pulse.RuleError{Kind: "invalid", Message: "No user has that email",
			Fields: pulse.FieldErrors{"email": "Ask them to create an account first"}}
	}
	if err != nil {
		return fmt.Errorf("finding user for pulse staff: %w", err)
	}
	_, err = r.db.ExecContext(ctx,
		`INSERT INTO pulse_staff (user_id, pulse_role, created_by) VALUES ($1, $2, $3)
		 ON CONFLICT (user_id, pulse_role) DO NOTHING`, userID, role, by)
	if err != nil {
		return fmt.Errorf("adding pulse staff: %w", err)
	}
	return nil
}

// RemoveStaff deletes one role assignment. Removing a missing one is a no-op.
func (r *PulseAdminRepository) RemoveStaff(ctx context.Context, id int64) error {
	if _, err := r.db.ExecContext(ctx, `DELETE FROM pulse_staff WHERE id = $1`, id); err != nil {
		return fmt.Errorf("removing pulse staff: %w", err)
	}
	return nil
}

// pulseDayExpr turns an event timestamp into the Pulse calendar day (UTC+3).
const pulseDayExpr = `(e.created_at AT TIME ZONE 'Asia/Baghdad')::date`

// Analytics summarises engagement between two days (YYYY-MM-DD, inclusive).
func (r *PulseAdminRepository) Analytics(ctx context.Context, from, to string) (*models.PulseAnalytics, error) {
	a := &models.PulseAnalytics{From: from, To: to, Items: []models.PulseItemStats{}}

	var reads int
	err := r.db.QueryRowContext(ctx, `
		SELECT COUNT(*) FILTER (WHERE e.event = 'view_day'),
		       COUNT(*) FILTER (WHERE e.event = 'open_item'),
		       COUNT(DISTINCT e.user_id) FILTER (WHERE e.event = 'open_item'),
		       COUNT(*) FILTER (WHERE e.event = 'read_complete'),
		       COUNT(*) FILTER (WHERE e.event = 'save'),
		       COUNT(*) FILTER (WHERE e.event = 'share')
		  FROM pulse_events e
		 WHERE `+pulseDayExpr+` BETWEEN $1 AND $2`, from, to).
		Scan(&a.DayViews, &a.ItemOpens, &a.UniqueReaders, &reads, &a.Saves, &a.Shares)
	if err != nil {
		return nil, fmt.Errorf("loading pulse totals: %w", err)
	}
	if a.ItemOpens > 0 {
		a.ReadCompletion = float64(reads) / float64(a.ItemOpens)
	}

	// Return rate: of the users who opened Pulse in the range, how many came
	// back on a second, different day.
	var returning, seen int
	err = r.db.QueryRowContext(ctx, `
		WITH d AS (
		  SELECT e.user_id, COUNT(DISTINCT `+pulseDayExpr+`) AS days
		    FROM pulse_events e
		   WHERE e.event = 'view_day' AND e.user_id IS NOT NULL
		     AND `+pulseDayExpr+` BETWEEN $1 AND $2
		   GROUP BY e.user_id)
		SELECT COUNT(*) FILTER (WHERE days >= 2), COUNT(*) FROM d`, from, to).Scan(&returning, &seen)
	if err != nil {
		return nil, fmt.Errorf("loading pulse return rate: %w", err)
	}
	if seen > 0 {
		a.ReturnRate = float64(returning) / float64(seen)
	}

	rows, err := r.db.QueryContext(ctx, `
		SELECT i.id, to_char(i.pulse_date, 'YYYY-MM-DD'), i.slot,
		       COALESCE(NULLIF(i.title_en, ''), i.title_ar),
		       COUNT(e.id) FILTER (WHERE e.event = 'open_item'),
		       COUNT(e.id) FILTER (WHERE e.event = 'read_complete'),
		       COUNT(e.id) FILTER (WHERE e.event = 'save'),
		       COUNT(e.id) FILTER (WHERE e.event = 'share')
		  FROM pulse_items i
		  LEFT JOIN pulse_events e ON e.item_id = i.id AND `+pulseDayExpr+` BETWEEN $1 AND $2
		 WHERE i.status IN ('published', 'archived') AND i.pulse_date BETWEEN $1 AND $2
		 GROUP BY i.id
		 ORDER BY 5 DESC, i.pulse_date DESC, i.id DESC
		 LIMIT 200`, from, to)
	if err != nil {
		return nil, fmt.Errorf("loading pulse item stats: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var s models.PulseItemStats
		if err := rows.Scan(&s.ItemID, &s.Date, &s.Slot, &s.Title, &s.Opens, &s.Reads, &s.Saves, &s.Shares); err != nil {
			return nil, fmt.Errorf("scanning pulse item stats: %w", err)
		}
		a.Items = append(a.Items, s)
	}
	return a, rows.Err()
}
