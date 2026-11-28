// screening_refresh.go — re-pulls EODHD fundamentals for every covered
// stock, re-runs the Sharia screen and fires compliance-drift alerts.
//
// Moved out of cmd/ingest_eodhd (same logic, same log lines) so the daily
// job runner and the manual command share one implementation.
package services

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"time"

	"halalstocks/internal/marketdata"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"halalstocks/internal/shariah"
)

// screeningStockLimit is how many stocks one refresh loads.
const screeningStockLimit = 1000

// fundamentalsFetcher is the part of the EODHD provider the refresh needs.
type fundamentalsFetcher interface {
	FetchFundamentalsBatch(tickers []string) ([]marketdata.FundamentalsFromAPI, error)
}

// ScreeningRefreshStats counts the outcome of one refresh.
type ScreeningRefreshStats struct {
	Real, Skipped, Failed int
}

// String is the summary stored in job_runs.detail.
func (s ScreeningRefreshStats) String() string {
	return fmt.Sprintf("%d refreshed, %d skipped (no EODHD coverage), %d failed", s.Real, s.Skipped, s.Failed)
}

// ScreeningRefresher holds the repos and provider for a refresh.
type ScreeningRefresher struct {
	Stocks   *repositories.StockRepository
	Funds    *repositories.FundamentalRepository
	Statuses *repositories.ShariahStatusRepository
	Settings *repositories.AppSettingsRepository
	Drift    *DriftDetector
	Provider fundamentalsFetcher
}

// RefreshAll refreshes every stock. A single stock's failure is counted and
// logged, not returned; only a failure to load the stock list is an error.
func (r *ScreeningRefresher) RefreshAll(ctx context.Context) (ScreeningRefreshStats, error) {
	var stats ScreeningRefreshStats
	r.applyThresholds()
	stocks, err := r.Stocks.GetAll(screeningStockLimit, 0)
	if err != nil {
		return stats, fmt.Errorf("loading stocks: %w", err)
	}
	log.Printf("Loaded %d stocks from DB", len(stocks))
	for _, st := range stocks {
		if ctx.Err() != nil {
			return stats, ctx.Err()
		}
		switch r.refreshOne(st) {
		case refreshReal:
			stats.Real++
		case refreshSkipped:
			stats.Skipped++
		default:
			stats.Failed++
		}
	}
	return stats, nil
}

// applyThresholds loads admin-configured screening thresholds, same as the
// API server does at start-up.
func (r *ScreeningRefresher) applyThresholds() {
	s := r.Settings
	shariah.SetThresholds(shariah.Thresholds{
		DebtFail: s.ScreeningDebtFail(), DebtWarn: s.ScreeningDebtWarn(),
		DebtPass: s.ScreeningDebtPass(), DebtGood: s.ScreeningDebtGood(),
		HaramFail: s.ScreeningHaramFail(), HaramWarn: s.ScreeningHaramWarn(),
		HaramPass: s.ScreeningHaramPass(), HaramGood: s.ScreeningHaramGood(),
	})
}

type refreshOutcome int

const (
	refreshReal refreshOutcome = iota
	refreshSkipped
	refreshFailed
)

// refreshOne pulls, saves and re-screens one stock.
func (r *ScreeningRefresher) refreshOne(st *models.Stock) refreshOutcome {
	funds, _ := r.Provider.FetchFundamentalsBatch([]string{st.Ticker})
	if len(funds) == 0 {
		log.Printf("SKIP  %-6s %-28s — no EODHD coverage (left on existing data)", st.Ticker, st.Name)
		return refreshSkipped
	}
	f := funds[0]
	r.saveStockMeta(st, f)
	fund := fundamentalFromAPI(st.ID, f)
	if err := r.Funds.CreateOrUpdate(fund); err != nil {
		return r.fail(st, "save_fundamentals", "save fundamentals", err)
	}
	// Pre-update status, so DriftDetector sees "before" and "after".
	previous, _ := r.Statuses.GetLatestStatus(st.ID)
	status, err := shariah.Screen(st, fund)
	if err != nil {
		return r.fail(st, "screen", "screen", err)
	}
	status.AsOfDate = utcDateOrToday(status.AsOfDate)
	if err := r.Statuses.CreateOrUpdate(&status); err != nil {
		return r.fail(st, "save_status", "save status", err)
	}
	r.Drift.Check(st, previous, &status)
	logRefreshed(st, &status, f.AsOfDate)
	return refreshReal
}

func (r *ScreeningRefresher) fail(st *models.Stock, stage, what string, err error) refreshOutcome {
	log.Printf("FAIL  %-6s %s: %v", st.Ticker, what, err)
	CaptureError(err, map[string]string{"job": "ingest_eodhd", "ticker": st.Ticker, "stage": stage})
	return refreshFailed
}

// saveStockMeta enriches sector/industry/market cap so activity screening
// is accurate. GetAll returned the full row, so re-saving is loss-free.
func (r *ScreeningRefresher) saveStockMeta(st *models.Stock, f marketdata.FundamentalsFromAPI) {
	if f.Sector != "" {
		st.Sector = sql.NullString{String: f.Sector, Valid: true}
	}
	if f.Industry != "" {
		st.Industry = sql.NullString{String: f.Industry, Valid: true}
	}
	if f.MarketCap > 0 {
		st.MarketCap = sql.NullInt64{Int64: f.MarketCap, Valid: true}
	}
	if err := r.Stocks.CreateOrUpdate(st); err != nil {
		log.Printf("WARN  %-6s update stock meta: %v", st.Ticker, err)
	}
}

// fundamentalFromAPI builds the fundamentals row (source=EODHD; the newest
// as_of_date wins on read).
func fundamentalFromAPI(stockID int64, f marketdata.FundamentalsFromAPI) *models.Fundamental {
	fund := &models.Fundamental{StockID: stockID}
	if f.TotalAssets > 0 {
		fund.TotalAssets = sql.NullFloat64{Float64: f.TotalAssets, Valid: true}
	}
	// 0 debt is meaningful (no debt = good), so always set it.
	fund.TotalDebt = sql.NullFloat64{Float64: f.TotalDebt, Valid: true}
	if f.CashAndEquiv > 0 {
		fund.CashAndEquiv = sql.NullFloat64{Float64: f.CashAndEquiv, Valid: true}
	}
	if f.TotalRevenue > 0 {
		fund.TotalRevenue = sql.NullFloat64{Float64: f.TotalRevenue, Valid: true}
	}
	fund.InterestIncome = sql.NullFloat64{Float64: f.InterestIncome, Valid: true}
	if f.NetIncome != 0 {
		fund.NetIncome = sql.NullFloat64{Float64: f.NetIncome, Valid: true}
	}
	fund.Source = sql.NullString{String: "EODHD", Valid: true}
	asOf := time.Now()
	if t, err := time.Parse("2006-01-02", f.AsOfDate); err == nil {
		asOf = t
	}
	fund.AsOfDate = sql.NullTime{Time: asOf, Valid: true}
	return fund
}

// utcDateOrToday truncates to a UTC date; a zero time becomes today.
func utcDateOrToday(t time.Time) time.Time {
	if t.IsZero() {
		t = time.Now().UTC()
	}
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}

func logRefreshed(st *models.Stock, status *models.ShariahStatus, asOf string) {
	grade := ""
	if status.Grade.Valid {
		grade = status.Grade.String
	}
	log.Printf("REAL  %-6s %-28s → %-8s grade=%-2s debt=%.3f haram=%.3f (asof %s)",
		st.Ticker, st.Name, status.Status, grade,
		status.DebtRatio.Float64, status.HaramIncomeRatio.Float64, asOf)
}
