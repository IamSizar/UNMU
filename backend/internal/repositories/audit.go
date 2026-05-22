package repositories

import (
	"database/sql"
	"encoding/json"
	"halalstocks/internal/models"
	"strings"
)

// AuditRepository writes + reads audit_logs rows. The DB triggers from
// migration 0005 already write rows for things that flow through Postgres
// (application status changes, role flips, post inserts). This repository
// covers the rest — events that happen at the HTTP boundary like
// login/register, where there's no underlying row insert to hook into.
type AuditRepository struct {
	db *sql.DB
}

func NewAuditRepository(db *sql.DB) *AuditRepository {
	return &AuditRepository{db: db}
}

// Write inserts an audit row directly. Used by handlers for events that the
// DB triggers don't catch (login, logout, register, ...).
//
// Errors are returned but most call sites discard them — failing to log an
// audit event must NEVER fail the underlying operation.
func (r *AuditRepository) Write(
	eventType, severity string,
	actorID *int64,
	targetID, targetKind *string,
	summary string,
	metadata map[string]any,
) (*models.AuditLog, error) {
	if metadata == nil {
		metadata = map[string]any{}
	}
	metaJSON, err := json.Marshal(metadata)
	if err != nil {
		return nil, err
	}

	var actorIDArg any
	if actorID != nil {
		actorIDArg = *actorID
	}
	var targetIDArg any
	if targetID != nil {
		targetIDArg = *targetID
	}
	var targetKindArg any
	if targetKind != nil {
		targetKindArg = *targetKind
	}

	row := r.db.QueryRow(`
		SELECT write_audit($1,$2,$3,$4,$5,$6,$7::jsonb)
	`, eventType, severity, actorIDArg, targetIDArg, targetKindArg, summary, string(metaJSON))

	var newID int64
	if err := row.Scan(&newID); err != nil {
		return nil, err
	}

	return r.GetByID(newID)
}

func (r *AuditRepository) GetByID(id int64) (*models.AuditLog, error) {
	row := r.db.QueryRow(baseAuditSelect+` WHERE id = $1`, id)
	a, err := models.ScanAuditLog(row)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return a, err
}

const baseAuditSelect = `
	SELECT id, type, severity, actor_id, actor_email, target_id, target_kind,
	       summary, metadata, created_at
	FROM audit_logs
`

// ListFilter narrows the result set for the admin feed. All fields are optional.
type ListFilter struct {
	Types      []string // event types to include
	Severity   string   // info|success|warning|error
	ActorID    *int64
	TargetID   string // matches audit_logs.target_id (text in SQL)
	TargetKind string // e.g. "support_thread", "post"
	Limit      int    // capped to 200; 0 → 50
	Cursor     int64  // id of last row from previous page; 0 → newest
}

// List returns rows newest-first matching the filter.
func (r *AuditRepository) List(f ListFilter) ([]*models.AuditLog, error) {
	q := baseAuditSelect
	clauses := []string{}
	args := []any{}

	if f.Cursor > 0 {
		args = append(args, f.Cursor)
		clauses = append(clauses, `id < $`+itoa(len(args)))
	}
	if len(f.Types) > 0 {
		args = append(args, asAny(f.Types)...)
		ph := []string{}
		for i := range f.Types {
			ph = append(ph, `$`+itoa(len(args)-len(f.Types)+i+1))
		}
		clauses = append(clauses, `type IN (`+strings.Join(ph, ",")+`)`)
	}
	if f.Severity != "" {
		args = append(args, f.Severity)
		clauses = append(clauses, `severity = $`+itoa(len(args)))
	}
	if f.ActorID != nil {
		args = append(args, *f.ActorID)
		clauses = append(clauses, `actor_id = $`+itoa(len(args)))
	}
	if f.TargetID != "" {
		args = append(args, f.TargetID)
		clauses = append(clauses, `target_id = $`+itoa(len(args)))
	}
	if f.TargetKind != "" {
		args = append(args, f.TargetKind)
		clauses = append(clauses, `target_kind = $`+itoa(len(args)))
	}

	if len(clauses) > 0 {
		q += ` WHERE ` + strings.Join(clauses, ` AND `)
	}

	limit := f.Limit
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	args = append(args, limit)
	q += ` ORDER BY id DESC LIMIT $` + itoa(len(args))

	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.AuditLog
	for rows.Next() {
		a, err := models.ScanAuditLog(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b [10]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}

func asAny(xs []string) []any {
	out := make([]any, len(xs))
	for i, s := range xs {
		out[i] = s
	}
	return out
}
