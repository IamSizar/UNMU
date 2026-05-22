package repositories

import (
	"database/sql"
	"halalstocks/internal/models"
	"time"
)

type AnalystRatingRepository struct {
	db *sql.DB
}

func NewAnalystRatingRepository(db *sql.DB) *AnalystRatingRepository {
	return &AnalystRatingRepository{db: db}
}

func (r *AnalystRatingRepository) CreateOrUpdate(analystRating *models.AnalystRating) error {
	query := `
		INSERT INTO analyst_ratings (stock_id, analyst_name, rating, target_price, rating_date, source, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT DO NOTHING
		RETURNING id
	`
	
	var analystName, ratingValue, source sql.NullString
	var targetPrice sql.NullFloat64
	var ratingDate sql.NullTime
	
	if analystRating.AnalystName.Valid {
		analystName = analystRating.AnalystName
	}
	if analystRating.Rating.Valid {
		ratingValue = analystRating.Rating
	}
	if analystRating.TargetPrice.Valid {
		targetPrice = analystRating.TargetPrice
	}
	if analystRating.RatingDate.Valid {
		ratingDate = analystRating.RatingDate
	}
	if analystRating.Source.Valid {
		source = analystRating.Source
	}
	
	var id int64
	err := r.db.QueryRow(query,
		analystRating.StockID, analystName, ratingValue, targetPrice, ratingDate, source, time.Now(),
	).Scan(&id)
	
	if err == sql.ErrNoRows {
		return nil // Already exists
	}
	
	if err == nil {
		analystRating.ID = id
	}
	return err
}

func (r *AnalystRatingRepository) GetByStockID(stockID int64) ([]*models.AnalystRating, error) {
	query := `
		SELECT id, stock_id, analyst_name, rating, target_price, rating_date, source, created_at
		FROM analyst_ratings
		WHERE stock_id = $1
		ORDER BY rating_date DESC
	`
	
	rows, err := r.db.Query(query, stockID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	
	var ratings []*models.AnalystRating
	for rows.Next() {
		rating := &models.AnalystRating{}
		err := rows.Scan(
			&rating.ID, &rating.StockID, &rating.AnalystName,
			&rating.Rating, &rating.TargetPrice, &rating.RatingDate,
			&rating.Source, &rating.CreatedAt,
		)
		if err != nil {
			continue
		}
		ratings = append(ratings, rating)
	}
	
	return ratings, rows.Err()
}

