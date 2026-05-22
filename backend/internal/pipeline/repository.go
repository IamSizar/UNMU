package pipeline

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

// Repository handles database operations for the pipeline
type Repository struct {
	db *sql.DB
}

// NewRepository creates a new repository instance
func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

// UpsertStock updates or inserts basic stock information
func (r *Repository) UpsertStock(ctx context.Context, snapshot *StockSnapshot) error {
	query := `
		INSERT INTO tracked_symbols (symbol, exchange, is_tracked, updated_at)
		VALUES ($1, $2, TRUE, $3)
		ON CONFLICT (symbol, exchange)
		DO UPDATE SET
			is_tracked = TRUE,
			updated_at = $3
	`
	_, err := r.db.ExecContext(ctx, query, snapshot.Symbol, snapshot.Exchange, time.Now())
	if err != nil {
		return fmt.Errorf("failed to upsert stock: %w", err)
	}
	return nil
}

// InsertSnapshot inserts a new stock snapshot (time-series data)
func (r *Repository) InsertSnapshot(ctx context.Context, snapshot *StockSnapshot) error {
	query := `
		INSERT INTO stock_snapshots (
			symbol, exchange, company_name, country, sector, industry, description,
			price, market_cap, shares_outstanding, currency,
			revenue, operating_income, net_income, interest_income, interest_expense, other_income,
			total_assets, total_liabilities, total_debt, short_term_debt, long_term_debt,
			cash_and_equivalents, short_term_investments,
			operating_cash_flow, financing_cash_flow, interest_paid,
			fiscal_year_end, last_report_date, snapshot_date,
			provider_name, data_quality
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7,
			$8, $9, $10, $11,
			$12, $13, $14, $15, $16, $17,
			$18, $19, $20, $21, $22,
			$23, $24,
			$25, $26, $27,
			$28, $29, $30,
			$31, $32
		)
		ON CONFLICT (symbol, exchange, snapshot_date)
		DO UPDATE SET
			company_name = EXCLUDED.company_name,
			country = EXCLUDED.country,
			sector = EXCLUDED.sector,
			industry = EXCLUDED.industry,
			description = EXCLUDED.description,
			price = EXCLUDED.price,
			market_cap = EXCLUDED.market_cap,
			shares_outstanding = EXCLUDED.shares_outstanding,
			currency = EXCLUDED.currency,
			revenue = EXCLUDED.revenue,
			operating_income = EXCLUDED.operating_income,
			net_income = EXCLUDED.net_income,
			interest_income = EXCLUDED.interest_income,
			interest_expense = EXCLUDED.interest_expense,
			other_income = EXCLUDED.other_income,
			total_assets = EXCLUDED.total_assets,
			total_liabilities = EXCLUDED.total_liabilities,
			total_debt = EXCLUDED.total_debt,
			short_term_debt = EXCLUDED.short_term_debt,
			long_term_debt = EXCLUDED.long_term_debt,
			cash_and_equivalents = EXCLUDED.cash_and_equivalents,
			short_term_investments = EXCLUDED.short_term_investments,
			operating_cash_flow = EXCLUDED.operating_cash_flow,
			financing_cash_flow = EXCLUDED.financing_cash_flow,
			interest_paid = EXCLUDED.interest_paid,
			fiscal_year_end = EXCLUDED.fiscal_year_end,
			last_report_date = EXCLUDED.last_report_date,
			provider_name = EXCLUDED.provider_name,
			data_quality = EXCLUDED.data_quality
	`
	
	_, err := r.db.ExecContext(ctx, query,
		snapshot.Symbol, snapshot.Exchange, snapshot.CompanyName, snapshot.Country,
		snapshot.Sector, snapshot.Industry, snapshot.Description,
		snapshot.Price, snapshot.MarketCap, snapshot.SharesOutstanding, snapshot.Currency,
		snapshot.Revenue, snapshot.OperatingIncome, snapshot.NetIncome,
		snapshot.InterestIncome, snapshot.InterestExpense, snapshot.OtherIncome,
		snapshot.TotalAssets, snapshot.TotalLiabilities, snapshot.TotalDebt,
		snapshot.ShortTermDebt, snapshot.LongTermDebt,
		snapshot.CashAndEquivalents, snapshot.ShortTermInvestments,
		snapshot.OperatingCashFlow, snapshot.FinancingCashFlow, snapshot.InterestPaid,
		snapshot.FiscalYearEnd, snapshot.LastReportDate, snapshot.SnapshotDate,
		snapshot.ProviderName, snapshot.DataQuality,
	)
	
	if err != nil {
		return fmt.Errorf("failed to insert snapshot: %w", err)
	}
	return nil
}

// UpsertLatestShariahResult updates or inserts the latest Shariah result
func (r *Repository) UpsertLatestShariahResult(ctx context.Context, result *ShariahResult) error {
	query := `
		INSERT INTO shariah_results (
			symbol, exchange, status, status_reason, detailed_breakdown, evaluated_at,
			debt_ratio, haram_income_ratio, cash_to_market_cap_ratio, purification_rate, grade
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		ON CONFLICT (symbol, exchange)
		DO UPDATE SET
			status = EXCLUDED.status,
			status_reason = EXCLUDED.status_reason,
			detailed_breakdown = EXCLUDED.detailed_breakdown,
			evaluated_at = EXCLUDED.evaluated_at,
			debt_ratio = EXCLUDED.debt_ratio,
			haram_income_ratio = EXCLUDED.haram_income_ratio,
			cash_to_market_cap_ratio = EXCLUDED.cash_to_market_cap_ratio,
			purification_rate = EXCLUDED.purification_rate,
			grade = EXCLUDED.grade,
			updated_at = CURRENT_TIMESTAMP
	`
	
	_, err := r.db.ExecContext(ctx, query,
		result.Symbol, result.Exchange, result.Status, result.StatusReason,
		result.DetailedBreakdown, result.EvaluatedAt,
		result.DebtRatio, result.HaramIncomeRatio, result.CashToMarketCapRatio,
		result.PurificationRate, result.Grade,
	)
	
	if err != nil {
		return fmt.Errorf("failed to upsert shariah result: %w", err)
	}
	return nil
}

// GetLastShariahResult retrieves the most recent Shariah result for a symbol
func (r *Repository) GetLastShariahResult(ctx context.Context, symbol string, exchange string) (*ShariahResult, error) {
	query := `
		SELECT symbol, exchange, status, status_reason, detailed_breakdown, evaluated_at,
		       debt_ratio, haram_income_ratio, cash_to_market_cap_ratio, purification_rate, grade
		FROM shariah_results
		WHERE symbol = $1 AND exchange = $2
	`
	
	var result ShariahResult
	var debtRatio, haramIncomeRatio, cashRatio, purifRate sql.NullFloat64
	
	err := r.db.QueryRowContext(ctx, query, symbol, exchange).Scan(
		&result.Symbol, &result.Exchange, &result.Status, &result.StatusReason,
		&result.DetailedBreakdown, &result.EvaluatedAt,
		&debtRatio, &haramIncomeRatio, &cashRatio, &purifRate, &result.Grade,
	)
	
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to get last shariah result: %w", err)
	}
	
	if debtRatio.Valid {
		result.DebtRatio = &debtRatio.Float64
	}
	if haramIncomeRatio.Valid {
		result.HaramIncomeRatio = &haramIncomeRatio.Float64
	}
	if cashRatio.Valid {
		result.CashToMarketCapRatio = &cashRatio.Float64
	}
	if purifRate.Valid {
		result.PurificationRate = &purifRate.Float64
	}
	
	return &result, nil
}

// ListTrackedSymbols returns all symbols that should be tracked
func (r *Repository) ListTrackedSymbols(ctx context.Context) ([]SymbolExchange, error) {
	query := `
		SELECT symbol, exchange
		FROM tracked_symbols
		WHERE is_tracked = TRUE
		ORDER BY priority DESC, symbol
	`
	
	rows, err := r.db.QueryContext(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to list tracked symbols: %w", err)
	}
	defer rows.Close()
	
	var symbols []SymbolExchange
	for rows.Next() {
		var s SymbolExchange
		if err := rows.Scan(&s.Symbol, &s.Exchange); err != nil {
			return nil, fmt.Errorf("failed to scan symbol: %w", err)
		}
		symbols = append(symbols, s)
	}
	
	return symbols, nil
}

// SymbolExchange represents a symbol with its exchange
type SymbolExchange struct {
	Symbol   string
	Exchange string
}

// GetStatusChanges returns status changes within a time range
func (r *Repository) GetStatusChanges(ctx context.Context, since time.Time) ([]StatusChange, error) {
	query := `
		SELECT symbol, exchange, old_status, new_status, old_grade, new_grade,
		       status_reason, evaluated_at
		FROM shariah_result_history
		WHERE evaluated_at >= $1
		ORDER BY evaluated_at DESC
	`
	
	rows, err := r.db.QueryContext(ctx, query, since)
	if err != nil {
		return nil, fmt.Errorf("failed to get status changes: %w", err)
	}
	defer rows.Close()
	
	var changes []StatusChange
	for rows.Next() {
		var change StatusChange
		var oldGrade, newGrade sql.NullString
		
		if err := rows.Scan(
			&change.Symbol, &change.Exchange, &change.OldStatus, &change.NewStatus,
			&oldGrade, &newGrade, &change.Reason, &change.EvaluatedAt,
		); err != nil {
			return nil, fmt.Errorf("failed to scan status change: %w", err)
		}
		
		if oldGrade.Valid {
			change.OldGrade = oldGrade.String
		}
		if newGrade.Valid {
			change.NewGrade = newGrade.String
		}
		
		changes = append(changes, change)
	}
	
	return changes, nil
}

// StatusChange represents a status change event
type StatusChange struct {
	Symbol      string
	Exchange    string
	OldStatus   sql.NullString
	NewStatus   string
	OldGrade    string
	NewGrade    string
	Reason      string
	EvaluatedAt time.Time
}

