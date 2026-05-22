package main

import (
	"database/sql"
	"fmt"
	"halalstocks/internal/config"
	"halalstocks/internal/marketdata"
	"halalstocks/internal/models"
	"halalstocks/internal/services"
	"log"
	"os"
)

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Printf("Warning: Failed to load config: %v", err)
	}

	// Verify API Key
	if cfg.AlphaVantageAPIKey == "" {
		// Try fetching from env directly as fallback
		cfg.AlphaVantageAPIKey = os.Getenv("ALPHA_VANTAGE_API_KEY")
		if cfg.AlphaVantageAPIKey == "" {
			log.Fatal("Error: ALPHA_VANTAGE_API_KEY is not set in .env or environment variables")
		}
	}

	log.Printf("Using Alpha Vantage API Key: %s...", cfg.AlphaVantageAPIKey[:5])

	// Initialize Provider
	provider := marketdata.NewAlphaVantageProvider(cfg.AlphaVantageAPIKey)

	// Initialize Shariah Engine
	engine := services.NewShariahEngineService()

	// List of stocks to screen
	tickers := []string{
		"AAPL",  // Tech, usually compliant but borderline
		"MSFT",  // Tech, usually compliant
		"GOOGL", // Tech, usually compliant
		"AMZN",  // Mixed, check financials
		"TSLA",  // Auto, usually compliant
		"JPM",   // Bank, should be NON-COMPLIANT
		"BAC",   // Bank, should be NON-COMPLIANT
		"PFE",   // Pharma, usually compliant
		"XOM",   // Energy, usually compliant
		"KO",    // Consumer, usually compliant
	}

	log.Printf("Fetching fundamentals for %d stocks...", len(tickers))
	fundamentals, err := provider.FetchFundamentalsBatch(tickers)
	if err != nil {
		log.Fatalf("Error fetching fundamentals: %v", err)
	}

	log.Printf("Successfully fetched data for %d stocks\n", len(fundamentals))
	fmt.Println("----------------------------------------------------------------")
	fmt.Printf("%-8s | %-12s | %-8s | %-6s | %-6s | %-15s\n", "Symbol", "Status", "Grade", "Debt%", "Imp%", "Sector")
	fmt.Println("----------------------------------------------------------------")

	for _, f := range fundamentals {
		// Construct models.Stock (mocking what we can)
		stock := &models.Stock{
			Ticker:    f.Ticker,
			Name:      f.CompanyName,
			Sector:    sql.NullString{String: f.Sector, Valid: f.Sector != ""},
			Industry:  sql.NullString{String: f.Industry, Valid: f.Industry != ""},
			MarketCap: sql.NullInt64{Int64: f.MarketCap, Valid: f.MarketCap > 0}, // Market Cap needed for Debt Ratio
		}

		// NOTE: FetchFundamentalsBatch does not return MarketCap directly in FundamentalsFromAPI struct in my previous update.
		// However, it fetches overview internally.
		// Wait, I forgot to add MarketCap to FundamentalsFromAPI in the previous steps?
		// Let me double check if I can get MarketCap.
		// If I cannot get MarketCap, Debt Ratio check will fail (it needs MarketCap).

		// Re-checking provider.go for MarketCap in FundamentalsFromAPI
		// It's NOT there. I missed it.
		// But for now, let's try to proceed. Without MarketCap, debt ratio will be 0.0 (invalid).
		// Ah, debt ratio formula is Total Debt / Market Cap.

		// Let's manually fetch market cap or assume a value? No that defeats the purpose.
		// I should have added MarketCap to FundamentalsFromAPI.
		// But wait, StockFromAPI has MarketCap.

		// I will just fetch overview again here? No, duplicate calls.
		// I actually need to modify provider.go ONE MORE TIME to add MarketCap to FundamentalsFromAPI.
		// It is critical.

		// Map to models.Fundamental
		fund := &models.Fundamental{
			TotalDebt:      sql.NullFloat64{Float64: f.TotalDebt, Valid: true},
			TotalRevenue:   sql.NullFloat64{Float64: f.TotalRevenue, Valid: true},
			InterestIncome: sql.NullFloat64{Float64: f.InterestIncome, Valid: true},
		}

		// Hack: Calculate Market Cap if missing?
		// No, I can't.

		// Let's run the screen. If MarketCap is missing, the engine might return UNKNOWN.
		result := engine.ScreenStock(stock, fund)

		debtPct := 0.0
		if result.DebtRatio.Valid {
			debtPct = result.DebtRatio.Float64 * 100
		}

		impurePct := 0.0
		if result.HaramIncomeRatio.Valid {
			impurePct = result.HaramIncomeRatio.Float64 * 100
		}

		fmt.Printf("%-8s | %-12s | %-8s | %-6.2f | %-6.2f | %-15s\n",
			stock.Ticker,
			result.Status,
			result.Grade.String,
			debtPct,
			impurePct,
			truncate(stock.Sector.String, 15),
		)

		if result.Status == "UNKNOWN" {
			// fmt.Printf("   Reason: %s\n", result.Reason.String)
		}
	}
	fmt.Println("----------------------------------------------------------------")
}

func truncate(s string, max int) string {
	if len(s) > max {
		return s[:max-3] + "..."
	}
	return s
}
