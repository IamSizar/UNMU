package repositories

import (
	"database/sql"
	"halalstocks/internal/models"
	"time"
)

type PromoCodeRepository struct {
	db *sql.DB
}

func NewPromoCodeRepository(db *sql.DB) *PromoCodeRepository {
	return &PromoCodeRepository{db: db}
}

func (r *PromoCodeRepository) GetByCode(code string) (*models.PromoCode, error) {
	query := `
		SELECT id, code, discount_type, discount_value, max_uses, used_count, is_active, valid_from, valid_until, created_at
		FROM promo_codes
		WHERE code = $1
	`
	
	promo := &models.PromoCode{}
	err := r.db.QueryRow(query, code).Scan(
		&promo.ID, &promo.Code, &promo.DiscountType, &promo.DiscountValue,
		&promo.MaxUses, &promo.UsedCount, &promo.IsActive,
		&promo.ValidFrom, &promo.ValidUntil, &promo.CreatedAt,
	)
	
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return promo, err
}

func (r *PromoCodeRepository) HasUserUsedCode(userID, promoCodeID int64) (bool, error) {
	query := `SELECT COUNT(*) FROM user_promo_usage WHERE user_id = $1 AND promo_code_id = $2`
	var count int
	err := r.db.QueryRow(query, userID, promoCodeID).Scan(&count)
	return count > 0, err
}

func (r *PromoCodeRepository) RecordUsage(userID, promoCodeID int64) error {
	query := `
		INSERT INTO user_promo_usage (user_id, promo_code_id, used_at)
		VALUES ($1, $2, $3)
		ON CONFLICT DO NOTHING
	`
	
	_, err := r.db.Exec(query, userID, promoCodeID, time.Now())
	if err != nil {
		return err
	}
	
	// Increment used count
	updateQuery := `UPDATE promo_codes SET used_count = used_count + 1 WHERE id = $1`
	_, err = r.db.Exec(updateQuery, promoCodeID)
	return err
}

