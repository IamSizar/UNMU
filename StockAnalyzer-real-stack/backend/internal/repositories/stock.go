package repositories

import (
	"database/sql"
	"halalstocks/internal/models"
	"time"
)

type StockRepository struct {
	db *sql.DB
}

func NewStockRepository(db *sql.DB) *StockRepository {
	return &StockRepository{db: db}
}

func (r *StockRepository) CreateOrUpdate(stock *models.Stock) error {
	query := `
		INSERT INTO stocks (ticker, exchange, name, country, region_code, sector, industry, description, market_cap, is_active, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		ON CONFLICT (ticker, exchange) 
		DO UPDATE SET 
			name = EXCLUDED.name,
			country = EXCLUDED.country,
			region_code = EXCLUDED.region_code,
			sector = EXCLUDED.sector,
			industry = EXCLUDED.industry,
			description = EXCLUDED.description,
			market_cap = EXCLUDED.market_cap,
			is_active = EXCLUDED.is_active,
			updated_at = EXCLUDED.updated_at
		RETURNING id
	`

	var country, regionCode, sector, industry, description sql.NullString
	var marketCap sql.NullInt64

	if stock.Country.Valid {
		country = stock.Country
	}
	if stock.RegionCode.Valid {
		regionCode = stock.RegionCode
	}
	if stock.Sector.Valid {
		sector = stock.Sector
	}
	if stock.Industry.Valid {
		industry = stock.Industry
	}
	if stock.Description.Valid {
		description = stock.Description
	}
	if stock.MarketCap.Valid {
		marketCap = stock.MarketCap
	}

	err := r.db.QueryRow(query,
		stock.Ticker, stock.Exchange, stock.Name, country, regionCode,
		sector, industry, description, marketCap, stock.IsActive, time.Now(),
	).Scan(&stock.ID)

	return err
}

func (r *StockRepository) GetByTickerAndExchange(ticker, exchange string) (*models.Stock, error) {
	query := `
		SELECT id, ticker, exchange, name, country, region_code, sector, industry, description, market_cap, is_active, created_at, updated_at
		FROM stocks
		WHERE ticker = $1 AND exchange = $2
	`

	stock := &models.Stock{}
	err := r.db.QueryRow(query, ticker, exchange).Scan(
		&stock.ID, &stock.Ticker, &stock.Exchange, &stock.Name,
		&stock.Country, &stock.RegionCode, &stock.Sector, &stock.Industry,
		&stock.Description, &stock.MarketCap, &stock.IsActive,
		&stock.CreatedAt, &stock.UpdatedAt,
	)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	return stock, err
}

func (r *StockRepository) Search(query string, limit int) ([]*models.Stock, error) {
	searchQuery := `
		SELECT id, ticker, exchange, name, country, region_code, sector, industry, description, market_cap, is_active, created_at, updated_at
		FROM stocks
		WHERE is_active = TRUE 
		AND (LOWER(name) LIKE LOWER($1) OR LOWER(ticker) LIKE LOWER($1))
		ORDER BY name
		LIMIT $2
	`

	rows, err := r.db.Query(searchQuery, "%"+query+"%", limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var stocks []*models.Stock
	for rows.Next() {
		stock := &models.Stock{}
		err := rows.Scan(
			&stock.ID, &stock.Ticker, &stock.Exchange, &stock.Name,
			&stock.Country, &stock.RegionCode, &stock.Sector, &stock.Industry,
			&stock.Description, &stock.MarketCap, &stock.IsActive,
			&stock.CreatedAt, &stock.UpdatedAt,
		)
		if err != nil {
			continue
		}
		stocks = append(stocks, stock)
	}

	return stocks, rows.Err()
}

func (r *StockRepository) GetByRegion(regionCode string, limit, offset int) ([]*models.Stock, error) {
	query := `
		SELECT id, ticker, exchange, name, country, region_code, sector, industry, description, market_cap, is_active, created_at, updated_at
		FROM stocks
		WHERE is_active = TRUE AND region_code = $1
		ORDER BY name
		LIMIT $2 OFFSET $3
	`

	rows, err := r.db.Query(query, regionCode, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var stocks []*models.Stock
	for rows.Next() {
		stock := &models.Stock{}
		err := rows.Scan(
			&stock.ID, &stock.Ticker, &stock.Exchange, &stock.Name,
			&stock.Country, &stock.RegionCode, &stock.Sector, &stock.Industry,
			&stock.Description, &stock.MarketCap, &stock.IsActive,
			&stock.CreatedAt, &stock.UpdatedAt,
		)
		if err != nil {
			continue
		}
		stocks = append(stocks, stock)
	}

	return stocks, rows.Err()
}

// GetByRegionWithShariahStatus fetches stocks with their latest Sharia status in one query
// This is much more efficient than fetching stocks and then statuses separately
func (r *StockRepository) GetByRegionWithShariahStatus(regionCode string, limit, offset int) ([]*models.Stock, map[int64]*models.ShariahStatus, error) {
	query := `
		SELECT 
			s.id, s.ticker, s.exchange, s.name, s.country, s.region_code, s.sector, s.industry, 
			s.description, s.market_cap, s.is_active, s.created_at, s.updated_at,
			ss.id, ss.status, ss.grade, ss.debt_ratio, ss.haram_income_ratio, 
			ss.purification_rate, ss.pays_zakat, ss.explanation, ss.reason, ss.as_of_date
		FROM stocks s
		LEFT JOIN LATERAL (
			SELECT id, status, grade, debt_ratio, haram_income_ratio, purification_rate,
				pays_zakat, explanation, reason, as_of_date
			FROM shariah_status
			WHERE stock_id = s.id
			ORDER BY as_of_date DESC
			LIMIT 1
		) ss ON true
		WHERE s.is_active = TRUE AND s.region_code = $1 AND s.market_cap > 0
		ORDER BY s.market_cap DESC NULLS LAST, s.name
		LIMIT $2 OFFSET $3
	`

	rows, err := r.db.Query(query, regionCode, limit, offset)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	var stocks []*models.Stock
	statusMap := make(map[int64]*models.ShariahStatus)

	for rows.Next() {
		stock := &models.Stock{}
		var statusID sql.NullInt64
		var statusStatus, statusGrade, statusExplanation, statusReason sql.NullString
		var statusDebtRatio, statusHaramIncomeRatio, statusPurificationRate sql.NullFloat64
		var statusPaysZakat sql.NullBool
		var statusAsOfDate sql.NullTime

		err := rows.Scan(
			&stock.ID, &stock.Ticker, &stock.Exchange, &stock.Name,
			&stock.Country, &stock.RegionCode, &stock.Sector, &stock.Industry,
			&stock.Description, &stock.MarketCap, &stock.IsActive,
			&stock.CreatedAt, &stock.UpdatedAt,
			&statusID, &statusStatus, &statusGrade, &statusDebtRatio, &statusHaramIncomeRatio,
			&statusPurificationRate, &statusPaysZakat, &statusExplanation, &statusReason, &statusAsOfDate,
		)
		if err != nil {
			continue
		}

		stocks = append(stocks, stock)

		// If we have Sharia status data, add it to the map
		if statusID.Valid {
			status := &models.ShariahStatus{
				ID:               statusID.Int64,
				StockID:          stock.ID,
				Status:           statusStatus.String,
				Grade:            statusGrade,
				DebtRatio:        statusDebtRatio,
				HaramIncomeRatio: statusHaramIncomeRatio,
				PurificationRate: statusPurificationRate,
				PaysZakat:        statusPaysZakat,
				Explanation:      statusExplanation,
				Reason:           statusReason,
			}
			if statusAsOfDate.Valid {
				status.AsOfDate = statusAsOfDate.Time
			}
			statusMap[stock.ID] = status
		}
	}

	return stocks, statusMap, rows.Err()
}

// GetAllWithShariahStatus fetches all stocks with their latest Sharia status
func (r *StockRepository) GetAllWithShariahStatus(limit, offset int) ([]*models.Stock, map[int64]*models.ShariahStatus, error) {
	query := `
		SELECT 
			s.id, s.ticker, s.exchange, s.name, s.country, s.region_code, s.sector, s.industry, 
			s.description, s.market_cap, s.is_active, s.created_at, s.updated_at,
			ss.id, ss.status, ss.grade, ss.debt_ratio, ss.haram_income_ratio, 
			ss.purification_rate, ss.pays_zakat, ss.explanation, ss.reason, ss.as_of_date
		FROM stocks s
		LEFT JOIN LATERAL (
			SELECT id, status, grade, debt_ratio, haram_income_ratio, purification_rate,
				pays_zakat, explanation, reason, as_of_date
			FROM shariah_status
			WHERE stock_id = s.id
			ORDER BY as_of_date DESC
			LIMIT 1
		) ss ON true
		WHERE s.is_active = TRUE AND s.market_cap > 0
		ORDER BY s.market_cap DESC NULLS LAST, s.name
		LIMIT $1 OFFSET $2
	`

	rows, err := r.db.Query(query, limit, offset)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	var stocks []*models.Stock
	statusMap := make(map[int64]*models.ShariahStatus)

	for rows.Next() {
		stock := &models.Stock{}
		var statusID sql.NullInt64
		var statusStatus, statusGrade, statusExplanation, statusReason sql.NullString
		var statusDebtRatio, statusHaramIncomeRatio, statusPurificationRate sql.NullFloat64
		var statusPaysZakat sql.NullBool
		var statusAsOfDate sql.NullTime

		err := rows.Scan(
			&stock.ID, &stock.Ticker, &stock.Exchange, &stock.Name,
			&stock.Country, &stock.RegionCode, &stock.Sector, &stock.Industry,
			&stock.Description, &stock.MarketCap, &stock.IsActive,
			&stock.CreatedAt, &stock.UpdatedAt,
			&statusID, &statusStatus, &statusGrade, &statusDebtRatio, &statusHaramIncomeRatio,
			&statusPurificationRate, &statusPaysZakat, &statusExplanation, &statusReason, &statusAsOfDate,
		)
		if err != nil {
			continue
		}

		stocks = append(stocks, stock)

		if statusID.Valid {
			status := &models.ShariahStatus{
				ID:               statusID.Int64,
				StockID:          stock.ID,
				Status:           statusStatus.String,
				Grade:            statusGrade,
				DebtRatio:        statusDebtRatio,
				HaramIncomeRatio: statusHaramIncomeRatio,
				PurificationRate: statusPurificationRate,
				PaysZakat:        statusPaysZakat,
				Explanation:      statusExplanation,
				Reason:           statusReason,
			}
			if statusAsOfDate.Valid {
				status.AsOfDate = statusAsOfDate.Time
			}
			statusMap[stock.ID] = status
		}
	}

	return stocks, statusMap, rows.Err()
}

func (r *StockRepository) GetAll(limit, offset int) ([]*models.Stock, error) {
	query := `
		SELECT id, ticker, exchange, name, country, region_code, sector, industry, description, market_cap, is_active, created_at, updated_at
		FROM stocks
		WHERE is_active = TRUE
		ORDER BY name
		LIMIT $1 OFFSET $2
	`

	rows, err := r.db.Query(query, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var stocks []*models.Stock
	for rows.Next() {
		stock := &models.Stock{}
		err := rows.Scan(
			&stock.ID, &stock.Ticker, &stock.Exchange, &stock.Name,
			&stock.Country, &stock.RegionCode, &stock.Sector, &stock.Industry,
			&stock.Description, &stock.MarketCap, &stock.IsActive,
			&stock.CreatedAt, &stock.UpdatedAt,
		)
		if err != nil {
			continue
		}
		stocks = append(stocks, stock)
	}

	return stocks, rows.Err()
}

func (r *StockRepository) GetByID(id int64) (*models.Stock, error) {
	query := `
		SELECT id, ticker, exchange, name, country, region_code, sector, industry, description, market_cap, is_active, created_at, updated_at
		FROM stocks
		WHERE id = $1
	`

	stock := &models.Stock{}
	err := r.db.QueryRow(query, id).Scan(
		&stock.ID, &stock.Ticker, &stock.Exchange, &stock.Name,
		&stock.Country, &stock.RegionCode, &stock.Sector, &stock.Industry,
		&stock.Description, &stock.MarketCap, &stock.IsActive,
		&stock.CreatedAt, &stock.UpdatedAt,
	)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	return stock, err
}
