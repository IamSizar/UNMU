// pulse_autodraft.go — the repository side of the Pulse auto-draft job
// (docs/pulse/AUTODRAFT.md): which slots are free, saving a system draft,
// and recent Sharia verdict changes for the Sharia slot.
package repositories

import (
	"context"
	"fmt"
	"time"

	"halalstocks/internal/models"
)

// AutoDraftNote is the change-log note on every system-created draft, so
// editors can tell a machine draft from a human one.
const AutoDraftNote = "auto-draft from news (AI); verify the source before review"

// TakenSlots returns the slots that already have an item (any status) on
// date (YYYY-MM-DD). The auto-draft job never adds a second item to them.
func (r *PulseAdminRepository) TakenSlots(ctx context.Context, date string) (map[string]bool, error) {
	rows, err := r.db.QueryContext(ctx,
		`SELECT DISTINCT slot FROM pulse_items WHERE pulse_date = $1`, date)
	if err != nil {
		return nil, fmt.Errorf("listing taken pulse slots: %w", err)
	}
	defer rows.Close()
	taken := map[string]bool{}
	for rows.Next() {
		var slot string
		if err := rows.Scan(&slot); err != nil {
			return nil, fmt.Errorf("scanning pulse slot: %w", err)
		}
		taken[slot] = true
	}
	return taken, rows.Err()
}

// CreateAutoDraft inserts a draft with no author (created_by NULL) and
// logs it as a system action. Same history rows as Create.
func (r *PulseAdminRepository) CreateAutoDraft(
	ctx context.Context, in models.PulseItemInput,
) (*models.PulseAdminItem, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("starting pulse auto-draft: %w", err)
	}
	defer tx.Rollback()

	var id int64
	err = tx.QueryRowContext(ctx,
		`INSERT INTO pulse_items (`+inputColumns+`, status, created_by)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,'draft',NULL)
		 RETURNING id`, inputArgs(in)...).Scan(&id)
	if err != nil {
		return nil, mapPulseDBError(fmt.Errorf("creating pulse auto-draft: %w", err))
	}
	if err := logPulseEvent(ctx, tx, id, models.PulseActionCreated, nil, "", models.PulseStatusDraft, AutoDraftNote); err != nil {
		return nil, err
	}
	if err := snapshotPulseItem(ctx, tx, id, "create", nil); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("committing pulse auto-draft: %w", err)
	}
	return getPulseAdminItem(ctx, r.db, id, false)
}

// ShariahChange is a stock whose latest verdict differs from the one
// before it.
type ShariahChange struct {
	StockID    int64
	Ticker     string
	Name       string
	From, To   string
	AsOfDate   string
	Reason     string
	DebtRatio  float64
	HaramRatio float64
}

// RecentShariahChanges lists verdict changes whose new status is dated on
// or after since, newest first.
func (r *PulseAdminRepository) RecentShariahChanges(ctx context.Context, since time.Time) ([]ShariahChange, error) {
	rows, err := r.db.QueryContext(ctx, `
		WITH ranked AS (
		  SELECT s.*, ROW_NUMBER() OVER (PARTITION BY stock_id ORDER BY as_of_date DESC) AS rn
		    FROM shariah_status s)
		SELECT st.id, st.ticker, st.name, prev.status, cur.status, cur.as_of_date::text,
		       COALESCE(cur.reason, ''), COALESCE(cur.debt_ratio, 0), COALESCE(cur.haram_income_ratio, 0)
		  FROM ranked cur
		  JOIN ranked prev ON prev.stock_id = cur.stock_id AND prev.rn = 2
		  JOIN stocks st ON st.id = cur.stock_id
		 WHERE cur.rn = 1 AND cur.as_of_date >= $1 AND cur.status <> prev.status
		 ORDER BY cur.as_of_date DESC, st.ticker`, since.Format("2006-01-02"))
	if err != nil {
		return nil, fmt.Errorf("listing shariah changes: %w", err)
	}
	defer rows.Close()
	out := []ShariahChange{}
	for rows.Next() {
		var c ShariahChange
		if err := rows.Scan(&c.StockID, &c.Ticker, &c.Name, &c.From, &c.To, &c.AsOfDate,
			&c.Reason, &c.DebtRatio, &c.HaramRatio); err != nil {
			return nil, fmt.Errorf("scanning shariah change: %w", err)
		}
		out = append(out, c)
	}
	return out, rows.Err()
}
