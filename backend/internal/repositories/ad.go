package repositories

import (
	"database/sql"
	"errors"
	"halalstocks/internal/models"
	"strings"
	"time"
)

type AdRepository struct {
	db *sql.DB
}

func NewAdRepository(db *sql.DB) *AdRepository {
	return &AdRepository{db: db}
}

// adCols — one definition the SELECT paths share. Column order must
// match the scan order in scanAd().
const adCols = `id, company_name, title, description, image_url, target_url,
	region_code, is_active, start_date, end_date, created_at`

func scanAd(row interface{ Scan(dest ...any) error }) (*models.Ad, error) {
	a := &models.Ad{}
	if err := row.Scan(
		&a.ID, &a.CompanyName, &a.Title, &a.Description,
		&a.ImageURL, &a.TargetURL, &a.RegionCode, &a.IsActive,
		&a.StartDate, &a.EndDate, &a.CreatedAt,
	); err != nil {
		return nil, err
	}
	return a, nil
}

// GetActiveAdsByRegion — public endpoint (today's behavior, unchanged).
// Returns ads matching the caller's region plus GLOBAL/null, filtered by
// is_active and date window.
func (r *AdRepository) GetActiveAdsByRegion(regionCode string) ([]*models.Ad, error) {
	rows, err := r.db.Query(`
		SELECT `+adCols+`
		FROM ads
		WHERE is_active = TRUE
		  AND (region_code = $1 OR region_code IS NULL OR region_code = 'GLOBAL')
		  AND (start_date IS NULL OR start_date <= CURRENT_DATE)
		  AND (end_date   IS NULL OR end_date   >= CURRENT_DATE)
		ORDER BY created_at DESC
	`, regionCode)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ads []*models.Ad
	for rows.Next() {
		ad, err := scanAd(rows)
		if err != nil {
			continue
		}
		ads = append(ads, ad)
	}
	return ads, rows.Err()
}

// AdminList — every ad, newest first. No region/date filter; the admin
// dashboard sees inactive + expired rows so they can re-activate them.
func (r *AdRepository) AdminList() ([]*models.Ad, error) {
	rows, err := r.db.Query(`SELECT ` + adCols + ` FROM ads ORDER BY created_at DESC LIMIT 500`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*models.Ad, 0)
	for rows.Next() {
		ad, err := scanAd(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, ad)
	}
	return out, rows.Err()
}

// AdminGet — by id. Returns (nil, nil) when not found.
func (r *AdRepository) AdminGet(id int64) (*models.Ad, error) {
	row := r.db.QueryRow(`SELECT `+adCols+` FROM ads WHERE id = $1`, id)
	a, err := scanAd(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return a, err
}

// AdMutation — shared shape for Create + Update. Pointer fields let the
// admin clear individual columns (PATCH with `"description":null`).
// Required-on-create fields (company_name, title) are non-pointer.
type AdMutation struct {
	CompanyName string
	Title       string
	Description *string
	ImageURL    *string
	TargetURL   *string
	RegionCode  *string
	IsActive    *bool
	StartDate   *time.Time
	EndDate     *time.Time
}

// Create inserts a new ad. is_active defaults to true if the caller
// didn't say otherwise.
func (r *AdRepository) Create(m AdMutation) (*models.Ad, error) {
	if strings.TrimSpace(m.CompanyName) == "" || strings.TrimSpace(m.Title) == "" {
		return nil, errors.New("ad: companyName and title are required")
	}
	isActive := true
	if m.IsActive != nil {
		isActive = *m.IsActive
	}
	row := r.db.QueryRow(`
		INSERT INTO ads
		    (company_name, title, description, image_url, target_url,
		     region_code, is_active, start_date, end_date)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING `+adCols,
		m.CompanyName, m.Title, m.Description, m.ImageURL, m.TargetURL,
		m.RegionCode, isActive, m.StartDate, m.EndDate,
	)
	return scanAd(row)
}

// Update applies a partial mutation. nil pointer = leave column alone;
// non-nil = set (even to NULL-equivalent zero values). Returns the
// fresh row.
func (r *AdRepository) Update(id int64, m AdMutation) (*models.Ad, error) {
	// COALESCE for "leave column alone if param is nil". For nullable
	// text columns we also use NULLIF($N, '') so an admin can clear a
	// column by sending `"description": ""` (PATCH semantics: empty
	// string = clear, omitting the field = no change).
	row := r.db.QueryRow(`
		UPDATE ads SET
		    company_name = COALESCE($1, company_name),
		    title        = COALESCE($2, title),
		    description  = CASE WHEN $3::boolean THEN NULLIF($4, '') ELSE description END,
		    image_url    = CASE WHEN $5::boolean THEN NULLIF($6, '') ELSE image_url END,
		    target_url   = CASE WHEN $7::boolean THEN NULLIF($8, '') ELSE target_url END,
		    region_code  = CASE WHEN $9::boolean THEN NULLIF($10, '') ELSE region_code END,
		    is_active    = COALESCE($11, is_active),
		    start_date   = CASE WHEN $12::boolean THEN $13 ELSE start_date END,
		    end_date     = CASE WHEN $14::boolean THEN $15 ELSE end_date END
		WHERE id = $16
		RETURNING `+adCols,
		nullableString(m.CompanyName != "", m.CompanyName),
		nullableString(m.Title != "", m.Title),
		m.Description != nil, derefStr(m.Description),
		m.ImageURL != nil, derefStr(m.ImageURL),
		m.TargetURL != nil, derefStr(m.TargetURL),
		m.RegionCode != nil, derefStr(m.RegionCode),
		m.IsActive,
		m.StartDate != nil, derefTime(m.StartDate),
		m.EndDate != nil, derefTime(m.EndDate),
		id,
	)
	a, err := scanAd(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return a, err
}

// Delete removes an ad row. Returns sql.ErrNoRows when nothing was
// deleted so the handler can map to 404.
func (r *AdRepository) Delete(id int64) error {
	res, err := r.db.Exec(`DELETE FROM ads WHERE id = $1`, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// ─── tiny helpers — keep the Update SQL terse ───────────────────────────

// nullableString returns nil when present is false so COALESCE leaves
// the column unchanged; otherwise the string value.
func nullableString(present bool, s string) any {
	if !present {
		return nil
	}
	return s
}

func derefStr(p *string) any {
	if p == nil {
		return nil
	}
	return *p
}

func derefTime(p *time.Time) any {
	if p == nil {
		return nil
	}
	return *p
}
