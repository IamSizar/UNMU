package repositories

import (
	"database/sql"
	"halalstocks/internal/models"
)

type AdRepository struct {
	db *sql.DB
}

func NewAdRepository(db *sql.DB) *AdRepository {
	return &AdRepository{db: db}
}

func (r *AdRepository) GetActiveAdsByRegion(regionCode string) ([]*models.Ad, error) {
	query := `
		SELECT id, company_name, title, description, image_url, target_url, region_code, is_active, start_date, end_date, created_at
		FROM ads
		WHERE is_active = TRUE
		AND (region_code = $1 OR region_code IS NULL OR region_code = 'GLOBAL')
		AND (start_date IS NULL OR start_date <= CURRENT_DATE)
		AND (end_date IS NULL OR end_date >= CURRENT_DATE)
		ORDER BY created_at DESC
	`
	
	rows, err := r.db.Query(query, regionCode)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	
	var ads []*models.Ad
	for rows.Next() {
		ad := &models.Ad{}
		err := rows.Scan(
			&ad.ID, &ad.CompanyName, &ad.Title, &ad.Description,
			&ad.ImageURL, &ad.TargetURL, &ad.RegionCode, &ad.IsActive,
			&ad.StartDate, &ad.EndDate, &ad.CreatedAt,
		)
		if err != nil {
			continue
		}
		ads = append(ads, ad)
	}
	
	return ads, rows.Err()
}
