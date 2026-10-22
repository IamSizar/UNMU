package repositories

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"halalstocks/internal/models"
	"halalstocks/internal/pulse"

	"github.com/lib/pq"
)

// =============================================================================
// pulse_admin.go — write side of UNMU Pulse: create / edit / delete / list
// items, plus the version history and change log. The status workflow
// (submit, review, approve, publish, ...) lives in pulse_workflow.go.
//
// Every write runs in ONE transaction that also writes the version snapshot
// and the change-log row, so the history can never disagree with the item.
// Workflow rules come from internal/pulse and are checked while the row is
// locked (SELECT ... FOR UPDATE), so two staff members cannot race each other.
// Tables: migration 0056_pulse.sql.
// =============================================================================

// pulseQuerier lets the helpers below run on either *sql.DB or *sql.Tx.
type pulseQuerier interface {
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

// PulseAdminRepository is the Pulse CMS data access.
type PulseAdminRepository struct {
	db *sql.DB
}

// NewPulseAdminRepository wires the repository to the shared database handle.
func NewPulseAdminRepository(db *sql.DB) *PulseAdminRepository {
	return &PulseAdminRepository{db: db}
}

const pulseAdminSelect = `
SELECT i.id, to_char(i.pulse_date, 'YYYY-MM-DD'), i.slot, i.classification,
       i.status, i.is_sensitive,
       i.title_ar, i.title_en, i.summary_ar, i.summary_en,
       i.details_ar, i.details_en, i.evidence_ar, i.evidence_en,
       i.source_name, i.source_url, i.verified_at,
       s.id, s.ticker, s.exchange, s.name,
       i.version, i.change_kind, i.last_changed_at, i.publish_at, i.published_at,
       i.created_by, i.reviewed_by, i.reviewed_at, i.approved_by, i.approved_at,
       i.created_at, i.updated_at
  FROM pulse_items i
  LEFT JOIN stocks s ON s.id = i.stock_id`

func timePtr(n sql.NullTime) *time.Time {
	if !n.Valid {
		return nil
	}
	t := n.Time
	return &t
}

func int64Ptr(n sql.NullInt64) *int64 {
	if !n.Valid {
		return nil
	}
	v := n.Int64
	return &v
}

// scanPulseAdminItem reads one row produced by pulseAdminSelect.
func scanPulseAdminItem(row rowScanner) (models.PulseAdminItem, error) {
	var (
		it                                     models.PulseAdminItem
		verified, changedAt, publishAt, pubAt  sql.NullTime
		reviewedAt, approvedAt                 sql.NullTime
		changeKind, sTicker, sExchange, sName  sql.NullString
		sID, createdBy, reviewedBy, approvedBy sql.NullInt64
	)
	err := row.Scan(
		&it.ID, &it.PulseDate, &it.Slot, &it.Classification, &it.Status, &it.IsSensitive,
		&it.TitleAr, &it.TitleEn, &it.SummaryAr, &it.SummaryEn,
		&it.DetailsAr, &it.DetailsEn, &it.EvidenceAr, &it.EvidenceEn,
		&it.SourceName, &it.SourceURL, &verified,
		&sID, &sTicker, &sExchange, &sName,
		&it.Version, &changeKind, &changedAt, &publishAt, &pubAt,
		&createdBy, &reviewedBy, &reviewedAt, &approvedBy, &approvedAt,
		&it.CreatedAt, &it.UpdatedAt,
	)
	if err != nil {
		return it, err
	}
	it.VerifiedAt, it.LastChangedAt = timePtr(verified), timePtr(changedAt)
	it.PublishAt, it.PublishedAt = timePtr(publishAt), timePtr(pubAt)
	it.ReviewedAt, it.ApprovedAt = timePtr(reviewedAt), timePtr(approvedAt)
	it.CreatedBy, it.ReviewedBy, it.ApprovedBy = int64Ptr(createdBy), int64Ptr(reviewedBy), int64Ptr(approvedBy)
	if changeKind.Valid {
		it.ChangeKind = &changeKind.String
	}
	if sID.Valid {
		it.Stock = &models.PulseStockRef{
			ID: int(sID.Int64), Ticker: sTicker.String, Exchange: sExchange.String, Name: sName.String,
		}
	}
	return it, nil
}

// getPulseAdminItem loads an item in any status. lock=true takes a row lock
// (use inside a transaction before changing the item).
func getPulseAdminItem(ctx context.Context, q pulseQuerier, id int64, lock bool) (*models.PulseAdminItem, error) {
	query := pulseAdminSelect + ` WHERE i.id = $1`
	if lock {
		query += ` FOR UPDATE OF i`
	}
	it, err := scanPulseAdminItem(q.QueryRowContext(ctx, query, id))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrPulseNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("loading pulse item %d: %w", id, err)
	}
	return &it, nil
}

// mapPulseDBError turns the database errors a bad request can cause into
// rule errors the dashboard can show next to the field.
func mapPulseDBError(err error) error {
	var pgErr *pq.Error
	if errors.As(err, &pgErr) {
		switch {
		case pgErr.Code == "23503" && pgErr.Constraint == "pulse_items_stock_id_fkey":
			return &pulse.RuleError{Kind: "invalid", Message: "That stock does not exist",
				Fields: pulse.FieldErrors{"stockId": "Pick a stock from the list"}}
		case pgErr.Code == "23505" && pgErr.Constraint == "pulse_items_one_published_per_slot":
			return &pulse.RuleError{Kind: "state", Message: "Another item is already published for this day and slot"}
		}
	}
	return err
}

// logPulseEvent appends one row to the change log. actor is nil for the
// system (the scheduler).
func logPulseEvent(
	ctx context.Context, q pulseQuerier, itemID int64, action string,
	actor *int64, from, to, note string,
) error {
	_, err := q.ExecContext(ctx,
		`INSERT INTO pulse_item_events (item_id, action, actor_id, from_status, to_status, note)
		 VALUES ($1, $2, $3, NULLIF($4,''), NULLIF($5,''), $6)`,
		itemID, action, actor, from, to, note)
	if err != nil {
		return fmt.Errorf("writing pulse change log: %w", err)
	}
	return nil
}

// snapshotPulseItem stores the item's CURRENT state as version item.Version.
func snapshotPulseItem(ctx context.Context, q pulseQuerier, itemID int64, reason string, actor *int64) error {
	it, err := getPulseAdminItem(ctx, q, itemID, false)
	if err != nil {
		return err
	}
	raw, err := json.Marshal(it)
	if err != nil {
		return fmt.Errorf("encoding pulse snapshot: %w", err)
	}
	_, err = q.ExecContext(ctx,
		`INSERT INTO pulse_item_versions (item_id, version, snapshot, reason, created_by)
		 VALUES ($1, $2, $3, $4, $5)`, itemID, it.Version, raw, reason, actor)
	if err != nil {
		return fmt.Errorf("writing pulse version: %w", err)
	}
	return nil
}

// inputColumns lists the editable columns in the order inputArgs returns them.
const inputColumns = `pulse_date, slot, classification, is_sensitive,
  title_ar, title_en, summary_ar, summary_en, details_ar, details_en,
  evidence_ar, evidence_en, source_name, source_url, verified_at, stock_id`

func inputArgs(in models.PulseItemInput) []any {
	return []any{
		in.PulseDate, in.Slot, in.Classification, in.IsSensitive,
		in.TitleAr, in.TitleEn, in.SummaryAr, in.SummaryEn, in.DetailsAr, in.DetailsEn,
		in.EvidenceAr, in.EvidenceEn, in.SourceName, in.SourceURL, in.VerifiedAt, in.StockID,
	}
}

// Create inserts a new draft authored by the actor.
func (r *PulseAdminRepository) Create(
	ctx context.Context, actor pulse.Actor, in models.PulseItemInput,
) (*models.PulseAdminItem, error) {
	if !actor.Has(models.PulseRoleEditor) {
		return nil, &pulse.RuleError{Kind: "forbidden", Message: "Your Pulse role does not allow creating items"}
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("starting pulse create: %w", err)
	}
	defer tx.Rollback()

	var id int64
	err = tx.QueryRowContext(ctx,
		`INSERT INTO pulse_items (`+inputColumns+`, status, created_by)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,'draft',$17)
		 RETURNING id`,
		append(inputArgs(in), actor.UserID)...).Scan(&id)
	if err != nil {
		return nil, mapPulseDBError(fmt.Errorf("creating pulse item: %w", err))
	}
	by := actor.UserID
	if err := logPulseEvent(ctx, tx, id, models.PulseActionCreated, &by, "", models.PulseStatusDraft, ""); err != nil {
		return nil, err
	}
	if err := snapshotPulseItem(ctx, tx, id, "create", &by); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("committing pulse create: %w", err)
	}
	return getPulseAdminItem(ctx, r.db, id, false)
}

// Update rewrites a DRAFT item's content and bumps its version.
func (r *PulseAdminRepository) Update(
	ctx context.Context, id int64, actor pulse.Actor, in models.PulseItemInput,
) (*models.PulseAdminItem, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("starting pulse update: %w", err)
	}
	defer tx.Rollback()

	it, err := getPulseAdminItem(ctx, tx, id, true)
	if err != nil {
		return nil, err
	}
	if err := pulse.CheckAction(pulse.DoEdit, *it, actor); err != nil {
		return nil, err
	}
	_, err = tx.ExecContext(ctx,
		`UPDATE pulse_items SET (`+inputColumns+`) =
		   ($2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17),
		   version = version + 1
		 WHERE id = $1`,
		append([]any{id}, inputArgs(in)...)...)
	if err != nil {
		return nil, mapPulseDBError(fmt.Errorf("updating pulse item %d: %w", id, err))
	}
	by := actor.UserID
	if err := logPulseEvent(ctx, tx, id, models.PulseActionEdited, &by, it.Status, it.Status, ""); err != nil {
		return nil, err
	}
	if err := snapshotPulseItem(ctx, tx, id, "edit", &by); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("committing pulse update: %w", err)
	}
	return getPulseAdminItem(ctx, r.db, id, false)
}

// Delete removes a DRAFT item (and, by cascade, its history).
// Anything that was ever submitted is archived instead, never deleted.
func (r *PulseAdminRepository) Delete(ctx context.Context, id int64, actor pulse.Actor) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("starting pulse delete: %w", err)
	}
	defer tx.Rollback()

	it, err := getPulseAdminItem(ctx, tx, id, true)
	if err != nil {
		return err
	}
	if err := pulse.CheckAction(pulse.DoDelete, *it, actor); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM pulse_items WHERE id = $1`, id); err != nil {
		return fmt.Errorf("deleting pulse item %d: %w", id, err)
	}
	return tx.Commit()
}

// Get returns one item in any status.
func (r *PulseAdminRepository) Get(ctx context.Context, id int64) (*models.PulseAdminItem, error) {
	return getPulseAdminItem(ctx, r.db, id, false)
}

// PulseListFilter narrows the admin list. Empty fields mean "no filter".
type PulseListFilter struct {
	Status, Slot, Date string
}

// List returns items, newest day first, one page at a time.
func (r *PulseAdminRepository) List(
	ctx context.Context, f PulseListFilter, limit, offset int,
) (items []models.PulseAdminItem, hasMore bool, err error) {
	query := pulseAdminSelect + ` WHERE TRUE`
	var args []any
	add := func(clause, v string) {
		if v == "" {
			return
		}
		args = append(args, v)
		query += fmt.Sprintf(clause, len(args))
	}
	add(" AND i.status = $%d", f.Status)
	add(" AND i.slot = $%d", f.Slot)
	add(" AND i.pulse_date = $%d", f.Date)
	args = append(args, limit+1, offset)
	query += fmt.Sprintf(` ORDER BY i.pulse_date DESC, %s, i.id DESC LIMIT $%d OFFSET $%d`,
		pulseSlotOrder, len(args)-1, len(args))

	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, false, fmt.Errorf("listing pulse items: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		it, err := scanPulseAdminItem(rows)
		if err != nil {
			return nil, false, fmt.Errorf("scanning pulse item: %w", err)
		}
		items = append(items, it)
	}
	if err := rows.Err(); err != nil {
		return nil, false, err
	}
	if len(items) > limit {
		return items[:limit], true, nil
	}
	return items, false, nil
}

// Versions returns every stored snapshot of an item, newest first.
func (r *PulseAdminRepository) Versions(ctx context.Context, itemID int64) ([]models.PulseVersion, error) {
	rows, err := r.db.QueryContext(ctx,
		`SELECT version, reason, snapshot, created_by, created_at
		   FROM pulse_item_versions WHERE item_id = $1 ORDER BY version DESC`, itemID)
	if err != nil {
		return nil, fmt.Errorf("loading pulse versions: %w", err)
	}
	defer rows.Close()
	out := []models.PulseVersion{}
	for rows.Next() {
		var v models.PulseVersion
		var by sql.NullInt64
		if err := rows.Scan(&v.Version, &v.Reason, &v.Snapshot, &by, &v.CreatedAt); err != nil {
			return nil, fmt.Errorf("scanning pulse version: %w", err)
		}
		v.CreatedBy = int64Ptr(by)
		out = append(out, v)
	}
	return out, rows.Err()
}

// ChangeLog returns the append-only history of an item, oldest first.
func (r *PulseAdminRepository) ChangeLog(ctx context.Context, itemID int64) ([]models.PulseChangeLogEntry, error) {
	rows, err := r.db.QueryContext(ctx,
		`SELECT e.id, e.action, e.actor_id, COALESCE(u.email, ''),
		        COALESCE(e.from_status, ''), COALESCE(e.to_status, ''), e.note, e.created_at
		   FROM pulse_item_events e
		   LEFT JOIN users u ON u.id = e.actor_id
		  WHERE e.item_id = $1 ORDER BY e.created_at, e.id`, itemID)
	if err != nil {
		return nil, fmt.Errorf("loading pulse change log: %w", err)
	}
	defer rows.Close()
	out := []models.PulseChangeLogEntry{}
	for rows.Next() {
		var e models.PulseChangeLogEntry
		var actor sql.NullInt64
		if err := rows.Scan(&e.ID, &e.Action, &actor, &e.ActorEmail,
			&e.FromStatus, &e.ToStatus, &e.Note, &e.CreatedAt); err != nil {
			return nil, fmt.Errorf("scanning pulse change log: %w", err)
		}
		e.ActorID = int64Ptr(actor)
		out = append(out, e)
	}
	return out, rows.Err()
}

// SearchStocks finds stocks by ticker or name for the "linked stock" picker.
// Text is matched literally (LIKE wildcards are escaped) and capped at limit.
func (r *PulseAdminRepository) SearchStocks(ctx context.Context, q string, limit int) ([]models.PulseStockRef, error) {
	pattern := "%" + escapeLike(q) + "%"
	rows, err := r.db.QueryContext(ctx,
		`SELECT id, ticker, exchange, name FROM stocks
		  WHERE is_active IS NOT FALSE
		    AND (ticker ILIKE $1 ESCAPE '\' OR name ILIKE $1 ESCAPE '\')
		  ORDER BY (LOWER(ticker) = LOWER($2)) DESC, ticker
		  LIMIT $3`, pattern, q, limit)
	if err != nil {
		return nil, fmt.Errorf("searching stocks: %w", err)
	}
	defer rows.Close()
	out := []models.PulseStockRef{}
	for rows.Next() {
		var s models.PulseStockRef
		if err := rows.Scan(&s.ID, &s.Ticker, &s.Exchange, &s.Name); err != nil {
			return nil, fmt.Errorf("scanning stock: %w", err)
		}
		out = append(out, s)
	}
	return out, rows.Err()
}
