package repositories

import (
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/lib/pq"
)

// ReportRepository owns the abuse-report queue. Backed by the `reports`
// table (mig 0036). Reports flow: open → resolved_action_taken |
// resolved_no_action | dismissed.
type ReportRepository struct {
	db *sql.DB
}

func NewReportRepository(db *sql.DB) *ReportRepository {
	return &ReportRepository{db: db}
}

// Report mirrors the table row. Joined columns (reporter_email etc.) are
// populated only in admin-facing queries; user-facing endpoints leave
// them empty.
type Report struct {
	ID             int64      `json:"id"`
	ReporterID     int64      `json:"reporterId"`
	TargetType     string     `json:"targetType"`
	TargetID       string     `json:"targetId"`
	Reason         string     `json:"reason"`
	Details        *string    `json:"details,omitempty"`
	Status         string     `json:"status"`
	ResolvedBy     *int64     `json:"resolvedBy,omitempty"`
	ResolvedAt     *time.Time `json:"resolvedAt,omitempty"`
	ResolutionNote *string    `json:"resolutionNote,omitempty"`
	CreatedAt      time.Time  `json:"createdAt"`
	UpdatedAt      time.Time  `json:"updatedAt"`

	// Joined columns (admin only).
	ReporterEmail string `json:"reporterEmail,omitempty"`
	ReporterName  string `json:"reporterName,omitempty"`
	ResolverEmail string `json:"resolverEmail,omitempty"`
}

// ErrDuplicateOpenReport — the same reporter already has an open report
// for this target. Caller maps to a 409 with a friendly message.
var ErrDuplicateOpenReport = fmt.Errorf("reports: duplicate open report")

const reportCols = `r.id, r.reporter_id, r.target_type, r.target_id, r.reason,
	r.details, r.status, r.resolved_by, r.resolved_at, r.resolution_note,
	r.created_at, r.updated_at`

// Create inserts a new open report. Hits the partial unique index when
// the same user already reported the same target and the prior report
// is still open — returns ErrDuplicateOpenReport.
func (r *ReportRepository) Create(
	reporterID int64,
	targetType, targetID, reason string,
	details string,
) (*Report, error) {
	var d any
	if strings.TrimSpace(details) != "" {
		d = strings.TrimSpace(details)
	}
	row := r.db.QueryRow(`
		INSERT INTO reports (reporter_id, target_type, target_id, reason, details)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING `+reportColsBareInsert,
		reporterID, targetType, targetID, reason, d,
	)
	rep, err := scanReport(row, false)
	if err != nil {
		if pgErr, ok := err.(*pq.Error); ok && pgErr.Code == "23505" {
			return nil, ErrDuplicateOpenReport
		}
		return nil, err
	}
	return rep, nil
}

// scanReport — central scanner used by every read path. `withJoined`
// controls whether the trailing 3 strings are expected in the row.
func scanReport(row scanner, withJoined bool) (*Report, error) {
	var rep Report
	var details, resolutionNote sql.NullString
	var resolvedBy sql.NullInt64
	var resolvedAt sql.NullTime
	var reporterEmail, reporterName, resolverEmail sql.NullString
	dests := []any{
		&rep.ID, &rep.ReporterID, &rep.TargetType, &rep.TargetID, &rep.Reason,
		&details, &rep.Status, &resolvedBy, &resolvedAt, &resolutionNote,
		&rep.CreatedAt, &rep.UpdatedAt,
	}
	if withJoined {
		dests = append(dests, &reporterEmail, &reporterName, &resolverEmail)
	}
	if err := row.Scan(dests...); err != nil {
		return nil, err
	}
	if details.Valid {
		rep.Details = &details.String
	}
	if resolutionNote.Valid {
		rep.ResolutionNote = &resolutionNote.String
	}
	if resolvedBy.Valid {
		rep.ResolvedBy = &resolvedBy.Int64
	}
	if resolvedAt.Valid {
		rep.ResolvedAt = &resolvedAt.Time
	}
	rep.ReporterEmail = reporterEmail.String
	rep.ReporterName = reporterName.String
	rep.ResolverEmail = resolverEmail.String
	return &rep, nil
}

// Used by Create's RETURNING. No 'r.' prefix because we're in the
// inserted row's scope.
const reportColsBareInsert = `id, reporter_id, target_type, target_id, reason,
	details, status, resolved_by, resolved_at, resolution_note,
	created_at, updated_at`

// scanner is a tiny interface so *sql.Row and *sql.Rows both fit.
type scanner interface {
	Scan(dest ...any) error
}

// ListMine — reports the current user filed. Newest first.
func (r *ReportRepository) ListMine(userID int64, limit int) ([]Report, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := r.db.Query(`
		SELECT `+reportColsBareInsert+`
		FROM reports
		WHERE reporter_id = $1
		ORDER BY created_at DESC
		LIMIT $2
	`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Report, 0)
	for rows.Next() {
		rep, err := scanReport(rows, false)
		if err != nil {
			return nil, err
		}
		out = append(out, *rep)
	}
	return out, rows.Err()
}

// ReportListFilter — admin queue filters.
type ReportListFilter struct {
	Status     string // "" = all, else "open"|"resolved_..."|"dismissed"
	TargetType string // "" = all, else "post"|"user"|...
	Limit      int
	Offset     int
}

// ListAdmin — admin queue. Joins reporter + resolver for the UI.
func (r *ReportRepository) ListAdmin(f ReportListFilter) ([]Report, int, error) {
	if f.Limit <= 0 || f.Limit > 200 {
		f.Limit = 50
	}
	if f.Offset < 0 {
		f.Offset = 0
	}
	args := []any{}
	conds := []string{}
	if f.Status != "" {
		args = append(args, f.Status)
		conds = append(conds, fmt.Sprintf("r.status = $%d", len(args)))
	}
	if f.TargetType != "" {
		args = append(args, f.TargetType)
		conds = append(conds, fmt.Sprintf("r.target_type = $%d", len(args)))
	}
	where := ""
	if len(conds) > 0 {
		where = "WHERE " + strings.Join(conds, " AND ")
	}

	// Total — same WHERE.
	var total int
	if err := r.db.QueryRow(
		`SELECT COUNT(*) FROM reports r `+where, args...,
	).Scan(&total); err != nil {
		return nil, 0, err
	}

	args = append(args, f.Limit, f.Offset)
	rows, err := r.db.Query(`
		SELECT `+reportCols+`,
		       reporter.email, COALESCE(reporter.name, ''),
		       COALESCE(resolver.email, '')
		FROM reports r
		JOIN users reporter ON reporter.id = r.reporter_id
		LEFT JOIN users resolver ON resolver.id = r.resolved_by
		`+where+`
		ORDER BY r.created_at DESC
		LIMIT $`+fmt.Sprint(len(args)-1)+` OFFSET $`+fmt.Sprint(len(args)),
		args...,
	)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := make([]Report, 0)
	for rows.Next() {
		rep, err := scanReport(rows, true)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, *rep)
	}
	return out, total, rows.Err()
}

// CountOpen — used by the sidebar badge.
func (r *ReportRepository) CountOpen() (int, error) {
	var n int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM reports WHERE status = 'open'`).Scan(&n)
	return n, err
}

// GetByID — admin drill-in.
func (r *ReportRepository) GetByID(id int64) (*Report, error) {
	row := r.db.QueryRow(`
		SELECT `+reportCols+`,
		       reporter.email, COALESCE(reporter.name, ''),
		       COALESCE(resolver.email, '')
		FROM reports r
		JOIN users reporter ON reporter.id = r.reporter_id
		LEFT JOIN users resolver ON resolver.id = r.resolved_by
		WHERE r.id = $1
	`, id)
	return scanReport(row, true)
}

// Resolve flips status to a terminal state with a note.
func (r *ReportRepository) Resolve(
	id, adminID int64,
	newStatus, note string,
) (*Report, error) {
	switch newStatus {
	case "resolved_action_taken", "resolved_no_action", "dismissed":
	default:
		return nil, fmt.Errorf("reports: invalid status %q", newStatus)
	}
	var n any
	if strings.TrimSpace(note) != "" {
		n = strings.TrimSpace(note)
	}
	row := r.db.QueryRow(`
		UPDATE reports
		SET status = $1,
		    resolved_by = $2,
		    resolved_at = NOW(),
		    resolution_note = $3,
		    updated_at = NOW()
		WHERE id = $4
		  AND status = 'open'
		RETURNING `+reportColsBareInsert,
		newStatus, adminID, n, id,
	)
	return scanReport(row, false)
}
