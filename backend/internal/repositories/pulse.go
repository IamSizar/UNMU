package repositories

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"halalstocks/internal/models"
)

// =============================================================================
// pulse.go — read side of UNMU Pulse (published items, archive, saves,
// analytics events). The admin/CMS side lives in pulse_admin.go.
//
// Only rows with status = 'published' are ever returned here: drafts, items in
// review and scheduled items must never reach a user (spec §6-7).
// Tables: migration 0056_pulse.sql.
// =============================================================================

// ErrPulseNotFound means the item does not exist or is not published.
var ErrPulseNotFound = errors.New("pulse item not found")

// PulseRepository reads published Pulse content for the mobile app.
type PulseRepository struct {
	db *sql.DB
}

// NewPulseRepository wires the repository to the shared database handle.
func NewPulseRepository(db *sql.DB) *PulseRepository {
	return &PulseRepository{db: db}
}

// pulseSelect is the shared SELECT for every published-item query.
//
// $1 is always the viewing user's id. The two LEFT JOINs answer "is the linked
// stock in this user's portfolio / watchlist" and "has this user saved the
// item" in the same round trip, so the list endpoints never do N+1 lookups.
// user_portfolios holds both holdings and followed stocks: shares > 0 means
// portfolio, otherwise watchlist.
const pulseSelect = `
SELECT i.id, to_char(i.pulse_date, 'YYYY-MM-DD'), i.slot, i.classification,
       i.title_ar, i.title_en, i.summary_ar, i.summary_en,
       i.details_ar, i.details_en, i.evidence_ar, i.evidence_en,
       i.source_name, i.source_url, i.verified_at,
       i.published_at, i.last_changed_at, i.change_kind,
       s.id, s.ticker, s.exchange, s.name,
       up.stock_id, COALESCE(up.shares, 0),
       (sv.id IS NOT NULL)
  FROM pulse_items i
  LEFT JOIN stocks s ON s.id = i.stock_id
  LEFT JOIN user_portfolios up ON up.stock_id = i.stock_id AND up.user_id = $1
  LEFT JOIN pulse_saves sv ON sv.item_id = i.id AND sv.user_id = $1
 WHERE i.status = 'published'`

// pulseSlotOrder sorts the four slots in display order.
const pulseSlotOrder = `array_position(ARRAY['global','gulf','sharia','opportunity'], i.slot)`

// scanPulseItem reads one row produced by pulseSelect.
// withDetail=false blanks details/evidence so list payloads stay small.
func scanPulseItem(rows *sql.Rows, withDetail bool, now time.Time) (models.PulseItem, error) {
	var (
		it                           models.PulseItem
		verified, published, changed sql.NullTime
		changeKind                   sql.NullString
		stockID                      sql.NullInt64
		stockTicker, stockExchange   sql.NullString
		stockName                    sql.NullString
		portfolioStock               sql.NullInt64
		shares                       float64
	)
	err := rows.Scan(
		&it.ID, &it.Date, &it.Slot, &it.Classification,
		&it.TitleAr, &it.TitleEn, &it.SummaryAr, &it.SummaryEn,
		&it.DetailsAr, &it.DetailsEn, &it.EvidenceAr, &it.EvidenceEn,
		&it.SourceName, &it.SourceURL, &verified,
		&published, &changed, &changeKind,
		&stockID, &stockTicker, &stockExchange, &stockName,
		&portfolioStock, &shares,
		&it.IsSaved,
	)
	if err != nil {
		return it, err
	}
	if verified.Valid {
		it.VerifiedAt = &verified.Time
	}
	if published.Valid {
		it.PublishedAt = &published.Time
	}
	if changed.Valid {
		it.LastChangedAt = &changed.Time
	}
	if changeKind.Valid {
		it.ChangeKind = &changeKind.String
	}
	it.Marker = models.PulseMarker(it.PublishedAt, it.ChangeKind, now)

	if stockID.Valid {
		it.Stock = &models.PulseStockRef{
			ID: int(stockID.Int64), Ticker: stockTicker.String,
			Exchange: stockExchange.String, Name: stockName.String,
		}
		if portfolioStock.Valid {
			rel := "watchlist"
			if shares > 0 {
				rel = "portfolio"
			}
			it.Relation = &rel
		}
	}
	if !withDetail {
		it.DetailsAr, it.DetailsEn, it.EvidenceAr, it.EvidenceEn = "", "", "", ""
	}
	return it, nil
}

// queryItems runs a pulseSelect-based query and scans every row.
func (r *PulseRepository) queryItems(
	ctx context.Context, withDetail bool, query string, args ...any,
) ([]models.PulseItem, error) {
	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("querying pulse items: %w", err)
	}
	defer rows.Close()

	now := time.Now()
	items := []models.PulseItem{}
	for rows.Next() {
		it, err := scanPulseItem(rows, withDetail, now)
		if err != nil {
			return nil, fmt.Errorf("scanning pulse item: %w", err)
		}
		items = append(items, it)
	}
	return items, rows.Err()
}

// Day returns the published items of one day in slot order (max four).
// date is YYYY-MM-DD in the Pulse time zone, decided by the caller.
func (r *PulseRepository) Day(ctx context.Context, userID int64, date string) (*models.PulseDay, error) {
	items, err := r.queryItems(ctx, false,
		pulseSelect+` AND i.pulse_date = $2 ORDER BY `+pulseSlotOrder, userID, date)
	if err != nil {
		return nil, fmt.Errorf("loading pulse day %s: %w", date, err)
	}
	day := &models.PulseDay{Date: date, Items: items}
	for _, it := range items {
		for _, t := range []*time.Time{it.PublishedAt, it.LastChangedAt} {
			if t != nil && (day.UpdatedAt == nil || t.After(*day.UpdatedAt)) {
				tt := *t
				day.UpdatedAt = &tt
			}
		}
	}
	return day, nil
}

// Item returns one published item with full details and evidence.
func (r *PulseRepository) Item(ctx context.Context, userID, itemID int64) (*models.PulseItem, error) {
	items, err := r.queryItems(ctx, true, pulseSelect+` AND i.id = $2`, userID, itemID)
	if err != nil {
		return nil, fmt.Errorf("loading pulse item %d: %w", itemID, err)
	}
	if len(items) == 0 {
		return nil, ErrPulseNotFound
	}
	return &items[0], nil
}

// escapeLike makes user text safe inside ILIKE ... ESCAPE '\'.
func escapeLike(s string) string {
	return strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(s)
}

// ArchiveFilter narrows the archive list. Empty fields mean "no filter".
type ArchiveFilter struct {
	From, To string // YYYY-MM-DD, inclusive
	Query    string // free-text over titles and summaries (both languages)
}

// Archive lists published items, newest day first, one page at a time.
// It asks for limit+1 rows so the caller can tell whether more pages exist.
func (r *PulseRepository) Archive(
	ctx context.Context, userID int64, f ArchiveFilter, limit, offset int,
) (items []models.PulseItem, hasMore bool, err error) {
	query := pulseSelect
	args := []any{userID}
	add := func(clause string, v any) {
		args = append(args, v)
		query += fmt.Sprintf(clause, len(args))
	}
	if f.From != "" {
		add(" AND i.pulse_date >= $%d", f.From)
	}
	if f.To != "" {
		add(" AND i.pulse_date <= $%d", f.To)
	}
	if q := strings.TrimSpace(f.Query); q != "" {
		add(` AND (i.title_en ILIKE $%[1]d ESCAPE '\' OR i.title_ar ILIKE $%[1]d ESCAPE '\'
		       OR i.summary_en ILIKE $%[1]d ESCAPE '\' OR i.summary_ar ILIKE $%[1]d ESCAPE '\')`,
			"%"+escapeLike(q)+"%")
	}
	args = append(args, limit+1, offset)
	query += fmt.Sprintf(" ORDER BY i.pulse_date DESC, %s LIMIT $%d OFFSET $%d",
		pulseSlotOrder, len(args)-1, len(args))

	items, err = r.queryItems(ctx, false, query, args...)
	if err != nil {
		return nil, false, fmt.Errorf("loading pulse archive: %w", err)
	}
	if len(items) > limit {
		return items[:limit], true, nil
	}
	return items, false, nil
}

// Saved lists the items a user saved, newest save first.
func (r *PulseRepository) Saved(
	ctx context.Context, userID int64, limit, offset int,
) (items []models.PulseItem, hasMore bool, err error) {
	query := pulseSelect + ` AND sv.id IS NOT NULL ORDER BY sv.created_at DESC LIMIT $2 OFFSET $3`
	items, err = r.queryItems(ctx, false, query, userID, limit+1, offset)
	if err != nil {
		return nil, false, fmt.Errorf("loading saved pulse: %w", err)
	}
	if len(items) > limit {
		return items[:limit], true, nil
	}
	return items, false, nil
}

// Save bookmarks a published item for the user. Saving twice is a no-op.
func (r *PulseRepository) Save(ctx context.Context, userID, itemID int64) error {
	var ok bool
	err := r.db.QueryRowContext(ctx,
		`SELECT EXISTS (SELECT 1 FROM pulse_items WHERE id = $1 AND status = 'published')`,
		itemID).Scan(&ok)
	if err != nil {
		return fmt.Errorf("checking pulse item %d: %w", itemID, err)
	}
	if !ok {
		return ErrPulseNotFound
	}
	_, err = r.db.ExecContext(ctx,
		`INSERT INTO pulse_saves (user_id, item_id) VALUES ($1, $2)
		 ON CONFLICT (user_id, item_id) DO NOTHING`, userID, itemID)
	if err != nil {
		return fmt.Errorf("saving pulse item %d: %w", itemID, err)
	}
	return nil
}

// Unsave removes a bookmark. Removing a non-existent one is a no-op.
func (r *PulseRepository) Unsave(ctx context.Context, userID, itemID int64) error {
	_, err := r.db.ExecContext(ctx,
		`DELETE FROM pulse_saves WHERE user_id = $1 AND item_id = $2`, userID, itemID)
	if err != nil {
		return fmt.Errorf("unsaving pulse item %d: %w", itemID, err)
	}
	return nil
}

// RecordEvent stores one analytics event. itemID is nil for day-level events.
// The event name must already be validated by the caller; the table CHECK is
// the last line of defence.
func (r *PulseRepository) RecordEvent(ctx context.Context, userID int64, itemID *int64, event string) error {
	_, err := r.db.ExecContext(ctx,
		`INSERT INTO pulse_events (user_id, item_id, event) VALUES ($1, $2, $3)`,
		userID, itemID, event)
	if err != nil {
		return fmt.Errorf("recording pulse event %s: %w", event, err)
	}
	return nil
}
