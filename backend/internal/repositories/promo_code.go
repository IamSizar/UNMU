package repositories

import (
	"database/sql"
	"errors"
	"halalstocks/internal/models"
	"strings"
	"time"

	"github.com/lib/pq"
)

type PromoCodeRepository struct {
	db *sql.DB
}

func NewPromoCodeRepository(db *sql.DB) *PromoCodeRepository {
	return &PromoCodeRepository{db: db}
}

// ErrPromoCodeExists — duplicate code on Create. Caller maps to 409.
var ErrPromoCodeExists = errors.New("promo: code already exists")

// promoCols — one column list shared by every SELECT path. Update
// scanPromo() in lockstep if you add a column.
const promoCols = `id, code, discount_type, discount_value, max_uses,
	used_count, is_active, valid_from, valid_until, created_at`

func scanPromo(row interface{ Scan(dest ...any) error }) (*models.PromoCode, error) {
	p := &models.PromoCode{}
	if err := row.Scan(
		&p.ID, &p.Code, &p.DiscountType, &p.DiscountValue,
		&p.MaxUses, &p.UsedCount, &p.IsActive,
		&p.ValidFrom, &p.ValidUntil, &p.CreatedAt,
	); err != nil {
		return nil, err
	}
	return p, nil
}

// GetByCode — used by the public /promo/validate endpoint. Returns
// (nil, nil) when no row matches.
func (r *PromoCodeRepository) GetByCode(code string) (*models.PromoCode, error) {
	row := r.db.QueryRow(
		`SELECT `+promoCols+` FROM promo_codes WHERE code = $1`,
		strings.ToUpper(strings.TrimSpace(code)),
	)
	p, err := scanPromo(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return p, err
}

func (r *PromoCodeRepository) HasUserUsedCode(userID, promoCodeID int64) (bool, error) {
	var count int
	err := r.db.QueryRow(
		`SELECT COUNT(*) FROM user_promo_usage WHERE user_id = $1 AND promo_code_id = $2`,
		userID, promoCodeID,
	).Scan(&count)
	return count > 0, err
}

func (r *PromoCodeRepository) RecordUsage(userID, promoCodeID int64) error {
	_, err := r.db.Exec(`
		INSERT INTO user_promo_usage (user_id, promo_code_id, used_at)
		VALUES ($1, $2, $3)
		ON CONFLICT DO NOTHING
	`, userID, promoCodeID, time.Now())
	if err != nil {
		return err
	}
	_, err = r.db.Exec(`UPDATE promo_codes SET used_count = used_count + 1 WHERE id = $1`, promoCodeID)
	return err
}

// ─── Admin CRUD ─────────────────────────────────────────────────────────

// AdminList — every promo, newest first.
func (r *PromoCodeRepository) AdminList() ([]*models.PromoCode, error) {
	rows, err := r.db.Query(
		`SELECT ` + promoCols + ` FROM promo_codes ORDER BY created_at DESC LIMIT 500`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*models.PromoCode, 0)
	for rows.Next() {
		p, err := scanPromo(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// AdminGet — by id. Returns (nil, nil) when missing.
func (r *PromoCodeRepository) AdminGet(id int64) (*models.PromoCode, error) {
	row := r.db.QueryRow(`SELECT `+promoCols+` FROM promo_codes WHERE id = $1`, id)
	p, err := scanPromo(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return p, err
}

// PromoMutation — shared shape for Create + Update. Same nullable-pointer
// pattern as AdMutation.
type PromoMutation struct {
	Code          string  // required on create; "" on update means "leave alone"
	DiscountType  string  // "PERCENTAGE" or "FIXED"
	DiscountValue float64
	MaxUses       *int64   // nil = no cap, &0 = capped at 0 (effectively disabled)
	IsActive      *bool
	ValidFrom     *time.Time
	ValidUntil    *time.Time

	// Update-only: when these are non-nil, we KNOW the admin touched the
	// field even though MaxUses / ValidFrom / ValidUntil are also
	// pointers (a *int64 of nil could mean either "untouched" or "clear
	// to NULL"). The boolean disambiguates.
	TouchMaxUses    bool
	TouchValidFrom  bool
	TouchValidUntil bool
}

// Create inserts a new promo code. Caller must have validated the
// discount type / value already.
func (r *PromoCodeRepository) Create(m PromoMutation) (*models.PromoCode, error) {
	code := strings.ToUpper(strings.TrimSpace(m.Code))
	if code == "" {
		return nil, errors.New("promo: code is required")
	}
	switch m.DiscountType {
	case "PERCENTAGE", "FIXED":
	default:
		return nil, errors.New("promo: discountType must be PERCENTAGE or FIXED")
	}
	if m.DiscountValue <= 0 {
		return nil, errors.New("promo: discountValue must be > 0")
	}
	isActive := true
	if m.IsActive != nil {
		isActive = *m.IsActive
	}
	row := r.db.QueryRow(`
		INSERT INTO promo_codes
		    (code, discount_type, discount_value, max_uses,
		     is_active, valid_from, valid_until)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING `+promoCols,
		code, m.DiscountType, m.DiscountValue,
		nullableInt64(m.MaxUses), isActive,
		nullableTime(m.ValidFrom), nullableTime(m.ValidUntil),
	)
	p, err := scanPromo(row)
	if err != nil {
		if pgErr, ok := err.(*pq.Error); ok && pgErr.Code == "23505" {
			return nil, ErrPromoCodeExists
		}
		return nil, err
	}
	return p, nil
}

// Update applies a partial mutation. The TouchXxx booleans signal which
// nullable fields the admin actually intended to change.
func (r *PromoCodeRepository) Update(id int64, m PromoMutation) (*models.PromoCode, error) {
	var codePresent any
	if m.Code != "" {
		codePresent = strings.ToUpper(strings.TrimSpace(m.Code))
	}
	var discountTypePresent any
	if m.DiscountType != "" {
		discountTypePresent = m.DiscountType
	}
	var discountValuePresent any
	if m.DiscountValue > 0 {
		discountValuePresent = m.DiscountValue
	}

	row := r.db.QueryRow(`
		UPDATE promo_codes SET
		    code           = COALESCE($1, code),
		    discount_type  = COALESCE($2, discount_type),
		    discount_value = COALESCE($3, discount_value),
		    max_uses       = CASE WHEN $4::boolean THEN $5 ELSE max_uses END,
		    is_active      = COALESCE($6, is_active),
		    valid_from     = CASE WHEN $7::boolean THEN $8 ELSE valid_from END,
		    valid_until    = CASE WHEN $9::boolean THEN $10 ELSE valid_until END
		WHERE id = $11
		RETURNING `+promoCols,
		codePresent, discountTypePresent, discountValuePresent,
		m.TouchMaxUses, nullableInt64(m.MaxUses),
		m.IsActive,
		m.TouchValidFrom, nullableTime(m.ValidFrom),
		m.TouchValidUntil, nullableTime(m.ValidUntil),
		id,
	)
	p, err := scanPromo(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		if pgErr, ok := err.(*pq.Error); ok && pgErr.Code == "23505" {
			return nil, ErrPromoCodeExists
		}
		return nil, err
	}
	return p, nil
}

// Delete removes a promo by id. Returns sql.ErrNoRows when nothing
// matched so the handler maps to 404.
func (r *PromoCodeRepository) Delete(id int64) error {
	res, err := r.db.Exec(`DELETE FROM promo_codes WHERE id = $1`, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// nullableInt64 / nullableTime — driver-friendly NULL handling for the
// COALESCE pattern. A nil pointer becomes SQL NULL; a non-nil pointer
// becomes the value.
func nullableInt64(p *int64) any {
	if p == nil {
		return nil
	}
	return *p
}

func nullableTime(p *time.Time) any {
	if p == nil {
		return nil
	}
	return *p
}
