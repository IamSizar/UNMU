// Command ingest_eodhd pulls REAL fundamentals from EODHD for every stock
// already in the DB that EODHD covers, writes them to the `fundamentals`
// table (source="EODHD"), and re-runs the Shariah screening engine so each
// stock's Halal verdict reflects real financials.
//
// Stocks EODHD does NOT cover (the Gulf/MENA names + the mislabeled VAC) are
// skipped and left exactly as they are, so nothing breaks — they switch to
// real once a Gulf-capable second provider is added.
//
// Run:  STOCK_API_PROVIDER unaffected — this reads EODHD_API_KEY directly.
//   cd backend && go run ./cmd/ingest_eodhd
package main

import (
	"database/sql"
	"log"
	"time"

	"halalstocks/internal/config"
	"halalstocks/internal/db"
	"halalstocks/internal/marketdata"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"halalstocks/internal/shariah"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	if cfg.EODHDAPIKey == "" {
		log.Fatal("EODHD_API_KEY is not set in backend/.env")
	}

	database, err := db.Connect(cfg)
	if err != nil {
		log.Fatalf("db connect: %v", err)
	}
	defer database.Close()

	stockRepo := repositories.NewStockRepository(database)
	fundRepo := repositories.NewFundamentalRepository(database)
	shariahRepo := repositories.NewShariahStatusRepository(database)

	prov := marketdata.NewEODHDProvider(cfg.EODHDAPIKey)

	stocks, err := stockRepo.GetAll(1000, 0)
	if err != nil {
		log.Fatalf("load stocks: %v", err)
	}
	log.Printf("Loaded %d stocks from DB", len(stocks))

	var real, skipped, failed int
	for _, st := range stocks {
		funds, _ := prov.FetchFundamentalsBatch([]string{st.Ticker})
		if len(funds) == 0 {
			log.Printf("SKIP  %-6s %-28s — no EODHD coverage (left on existing data)", st.Ticker, st.Name)
			skipped++
			continue
		}
		f := funds[0]

		// Enrich metadata (sector/industry/market cap) so activity screening
		// is accurate. GetAll returned the full row, so re-saving is loss-free.
		if f.Sector != "" {
			st.Sector = sql.NullString{String: f.Sector, Valid: true}
		}
		if f.Industry != "" {
			st.Industry = sql.NullString{String: f.Industry, Valid: true}
		}
		if f.MarketCap > 0 {
			st.MarketCap = sql.NullInt64{Int64: f.MarketCap, Valid: true}
		}
		if err := stockRepo.CreateOrUpdate(st); err != nil {
			log.Printf("WARN  %-6s update stock meta: %v", st.Ticker, err)
		}

		// Real fundamentals row (source=EODHD; newest as_of_date wins on read).
		fund := &models.Fundamental{StockID: st.ID}
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
		if t, perr := time.Parse("2006-01-02", f.AsOfDate); perr == nil {
			fund.AsOfDate = sql.NullTime{Time: t, Valid: true}
		} else {
			fund.AsOfDate = sql.NullTime{Time: time.Now(), Valid: true}
		}
		if err := fundRepo.CreateOrUpdate(fund); err != nil {
			log.Printf("FAIL  %-6s save fundamentals: %v", st.Ticker, err)
			failed++
			continue
		}

		// Re-screen on the real numbers.
		status, err := shariah.Screen(st, fund)
		if err != nil {
			log.Printf("FAIL  %-6s screen: %v", st.Ticker, err)
			failed++
			continue
		}
		if status.AsOfDate.IsZero() {
			status.AsOfDate = time.Now().UTC()
		}
		status.AsOfDate = time.Date(status.AsOfDate.Year(), status.AsOfDate.Month(),
			status.AsOfDate.Day(), 0, 0, 0, 0, time.UTC)
		if err := shariahRepo.CreateOrUpdate(&status); err != nil {
			log.Printf("FAIL  %-6s save status: %v", st.Ticker, err)
			failed++
			continue
		}

		grade := ""
		if status.Grade.Valid {
			grade = status.Grade.String
		}
		log.Printf("REAL  %-6s %-28s → %-8s grade=%-2s debt=%.3f haram=%.3f (asof %s)",
			st.Ticker, st.Name, status.Status, grade,
			status.DebtRatio.Float64, status.HaramIncomeRatio.Float64, f.AsOfDate)
		real++
	}

	log.Printf("──────────────────────────────────────────")
	log.Printf("DONE — %d real, %d skipped (left on demo), %d failed", real, skipped, failed)
}
