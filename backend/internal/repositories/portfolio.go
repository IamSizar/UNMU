package repositories

import (
	"database/sql"
	"halalstocks/internal/models"
	"time"
)

type PortfolioRepository struct {
	db *sql.DB
}

func NewPortfolioRepository(db *sql.DB) *PortfolioRepository {
	return &PortfolioRepository{db: db}
}

func (r *PortfolioRepository) AddToPortfolio(portfolio *models.UserPortfolio) error {
	query := `
		INSERT INTO user_portfolios (user_id, stock_id, shares, avg_buy_price, added_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (user_id, stock_id)
		DO UPDATE SET shares = EXCLUDED.shares, avg_buy_price = EXCLUDED.avg_buy_price
		RETURNING id
	`
	
	var shares, avgBuyPrice sql.NullFloat64
	if portfolio.Shares.Valid {
		shares = portfolio.Shares
	}
	if portfolio.AvgBuyPrice.Valid {
		avgBuyPrice = portfolio.AvgBuyPrice
	}
	
	err := r.db.QueryRow(query,
		portfolio.UserID, portfolio.StockID, shares, avgBuyPrice, time.Now(),
	).Scan(&portfolio.ID)
	
	return err
}

func (r *PortfolioRepository) GetUserPortfolio(userID int64) ([]*models.UserPortfolio, error) {
	query := `
		SELECT id, user_id, stock_id, shares, avg_buy_price, added_at
		FROM user_portfolios
		WHERE user_id = $1
		ORDER BY added_at DESC
	`
	
	rows, err := r.db.Query(query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	
	var portfolios []*models.UserPortfolio
	for rows.Next() {
		portfolio := &models.UserPortfolio{}
		err := rows.Scan(
			&portfolio.ID, &portfolio.UserID, &portfolio.StockID,
			&portfolio.Shares, &portfolio.AvgBuyPrice, &portfolio.AddedAt,
		)
		if err != nil {
			continue
		}
		portfolios = append(portfolios, portfolio)
	}
	
	return portfolios, rows.Err()
}

func (r *PortfolioRepository) RemoveFromPortfolio(userID, stockID int64) error {
	query := `DELETE FROM user_portfolios WHERE user_id = $1 AND stock_id = $2`
	_, err := r.db.Exec(query, userID, stockID)
	return err
}

