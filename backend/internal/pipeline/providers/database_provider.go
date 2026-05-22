package providers

import (
	"context"
	"database/sql"
	"fmt"
	"halalstocks/internal/pipeline"
	"log/slog"
	"time"

	_ "github.com/lib/pq"
)

// DatabaseProvider uses existing data from the database as a data source
// This is useful when API endpoints are unavailable or deprecated
type DatabaseProvider struct {
	db     *sql.DB
	logger *slog.Logger
}

// NewDatabaseProvider creates a provider that reads from existing database tables
func NewDatabaseProvider(db *sql.DB, logger *slog.Logger) *DatabaseProvider {
	if logger == nil {
		logger = slog.Default()
	}
	return &DatabaseProvider{
		db:     db,
		logger: logger,
	}
}

func (p *DatabaseProvider) Name() string {
	return "Database"
}

func (p *DatabaseProvider) IsAvailable(ctx context.Context) bool {
	// Check if database is accessible
	if err := p.db.PingContext(ctx); err != nil {
		return false
	}
	// Check if we have data
	var count int
	err := p.db.QueryRowContext(ctx, "SELECT COUNT(*) FROM stocks WHERE is_active = TRUE").Scan(&count)
	return err == nil && count > 0
}

func (p *DatabaseProvider) FetchSnapshot(ctx context.Context, symbol string, exchange string) (*pipeline.StockSnapshot, error) {
	snapshot := &pipeline.StockSnapshot{
		Symbol:      symbol,
		Exchange:    exchange,
		SnapshotDate: time.Now().UTC(),
		ProviderName: p.Name(),
	}

	// Get stock info
	var stockID int64
	var name, country, regionCode, sector, industry, description sql.NullString
	var marketCap sql.NullInt64

	stockQuery := `
		SELECT id, name, country, region_code, sector, industry, description, market_cap
		FROM stocks
		WHERE ticker = $1 AND exchange = $2 AND is_active = TRUE
	`
	err := p.db.QueryRowContext(ctx, stockQuery, symbol, exchange).Scan(
		&stockID, &name, &country, &regionCode, &sector, &industry, &description, &marketCap,
	)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("stock not found in database")
	}
	if err != nil {
		return nil, fmt.Errorf("failed to query stock: %w", err)
	}

	if name.Valid {
		snapshot.CompanyName = name.String
	}
	if country.Valid {
		snapshot.Country = country.String
	}
	if sector.Valid {
		snapshot.Sector = sector.String
	}
	if industry.Valid {
		snapshot.Industry = industry.String
	}
	if description.Valid {
		snapshot.Description = description.String
	}
	if marketCap.Valid {
		snapshot.MarketCap = float64(marketCap.Int64)
	}

	// Get latest fundamental
	var totalAssets, totalDebt, cashAndEquiv, totalRevenue sql.NullFloat64
	var interestIncome, interestExpense, netIncome sql.NullFloat64
	var asOfDate sql.NullTime

	fundamentalQuery := `
		SELECT total_assets, total_debt, cash_and_equiv, total_revenue,
		       interest_income, interest_expense, net_income, as_of_date
		FROM fundamentals
		WHERE stock_id = $1
		ORDER BY as_of_date DESC
		LIMIT 1
	`
	err = p.db.QueryRowContext(ctx, fundamentalQuery, stockID).Scan(
		&totalAssets, &totalDebt, &cashAndEquiv, &totalRevenue,
		&interestIncome, &interestExpense, &netIncome, &asOfDate,
	)
	if err == nil {
		if totalAssets.Valid {
			snapshot.TotalAssets = totalAssets.Float64
		}
		if totalDebt.Valid {
			snapshot.TotalDebt = totalDebt.Float64
		}
		if cashAndEquiv.Valid {
			snapshot.CashAndEquivalents = cashAndEquiv.Float64
		}
		if totalRevenue.Valid {
			snapshot.Revenue = totalRevenue.Float64
		}
		if interestIncome.Valid {
			snapshot.InterestIncome = interestIncome.Float64
		}
		if interestExpense.Valid {
			snapshot.InterestExpense = interestExpense.Float64
		}
		if netIncome.Valid {
			snapshot.NetIncome = netIncome.Float64
		}
		if asOfDate.Valid {
			snapshot.LastReportDate = asOfDate.Time
		}
	} else if err != sql.ErrNoRows {
		p.logger.Warn("Failed to fetch fundamental", "symbol", symbol, "error", err)
	}

	snapshot.AssessQuality()
	return snapshot, nil
}

func (p *DatabaseProvider) FetchSnapshotsBulk(ctx context.Context, symbols []string, exchanges []string) (map[string]*pipeline.StockSnapshot, []error) {
	results := make(map[string]*pipeline.StockSnapshot)
	var errors []error

	for i, symbol := range symbols {
		exchange := ""
		if i < len(exchanges) {
			exchange = exchanges[i]
		}

		snapshot, err := p.FetchSnapshot(ctx, symbol, exchange)
		if err != nil {
			errors = append(errors, fmt.Errorf("%s: %w", symbol, err))
			continue
		}
		results[symbol] = snapshot
	}

	return results, errors
}

