package repositories

import (
	"database/sql"
	"halalstocks/internal/models"
	"time"
)

type FundamentalRepository struct {
	db *sql.DB
}

func NewFundamentalRepository(db *sql.DB) *FundamentalRepository {
	return &FundamentalRepository{db: db}
}

func (r *FundamentalRepository) CreateOrUpdate(fundamental *models.Fundamental) error {
	// Use UPSERT with proper conflict handling
	query := `
		INSERT INTO fundamentals (stock_id, total_assets, total_debt, cash_and_equiv, total_revenue, 
			interest_income, interest_expense, net_income, dividends_per_share, as_of_date, source, raw_json, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
		ON CONFLICT (stock_id, as_of_date, source)
		DO UPDATE SET
			total_assets = EXCLUDED.total_assets,
			total_debt = EXCLUDED.total_debt,
			cash_and_equiv = EXCLUDED.cash_and_equiv,
			total_revenue = EXCLUDED.total_revenue,
			interest_income = EXCLUDED.interest_income,
			interest_expense = EXCLUDED.interest_expense,
			net_income = EXCLUDED.net_income,
			dividends_per_share = EXCLUDED.dividends_per_share,
			raw_json = EXCLUDED.raw_json,
			updated_at = EXCLUDED.updated_at
		RETURNING id
	`
	
	var id int64
	err := r.db.QueryRow(query,
		fundamental.StockID,
		fundamental.TotalAssets,
		fundamental.TotalDebt,
		fundamental.CashAndEquiv,
		fundamental.TotalRevenue,
		fundamental.InterestIncome,
		fundamental.InterestExpense,
		fundamental.NetIncome,
		fundamental.DividendsPerShare,
		fundamental.AsOfDate,
		fundamental.Source,
		fundamental.RawJSON,
		time.Now(),
	).Scan(&id)
	
	if err == nil {
		fundamental.ID = id
	}
	return err
}

func (r *FundamentalRepository) GetLatestFundamental(stockID int64) (*models.Fundamental, error) {
	query := `
		SELECT id, stock_id, total_assets, total_debt, cash_and_equiv, total_revenue,
			interest_income, interest_expense, net_income, dividends_per_share, as_of_date, source, raw_json, created_at, updated_at
		FROM fundamentals
		WHERE stock_id = $1
		ORDER BY as_of_date DESC
		LIMIT 1
	`
	
	fundamental := &models.Fundamental{}
	err := r.db.QueryRow(query, stockID).Scan(
		&fundamental.ID, &fundamental.StockID,
		&fundamental.TotalAssets, &fundamental.TotalDebt, &fundamental.CashAndEquiv,
		&fundamental.TotalRevenue, &fundamental.InterestIncome, &fundamental.InterestExpense,
		&fundamental.NetIncome, &fundamental.DividendsPerShare, &fundamental.AsOfDate,
		&fundamental.Source, &fundamental.RawJSON, &fundamental.CreatedAt, &fundamental.UpdatedAt,
	)
	
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return fundamental, err
}
