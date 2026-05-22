package main

import (
	"fmt"
	"log"

	"halalstocks/internal/config"
	"halalstocks/internal/marketdata"
)

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	if cfg.StockAPIProvider != "datajockey" {
		fmt.Printf("⚠️  Current provider is '%s', not 'datajockey'\n", cfg.StockAPIProvider)
		fmt.Println("Update .env file: STOCK_API_PROVIDER=datajockey")
		return
	}

	if cfg.DataJockeyAPIKey == "" {
		log.Fatal("DATAJOCKEY_API_KEY is not set in .env file")
	}

	// Create DataJockey provider
	provider := marketdata.NewDataJockeyProvider(cfg.DataJockeyAPIKey)

	fmt.Println("🧪 Testing DataJockey Fundamentals API...")
	fmt.Println()

	// Test fundamentals for AAPL
	fmt.Println("📊 Testing FetchFundamentalsBatch(['AAPL'])...")
	fundamentals, err := provider.FetchFundamentalsBatch([]string{"AAPL"})
	if err != nil {
		fmt.Printf("   ❌ Error: %v\n", err)
	} else {
		fmt.Printf("   ✅ Found fundamentals for %d tickers\n", len(fundamentals))
		if len(fundamentals) > 0 {
			f := fundamentals[0]
			fmt.Printf("\n   📈 Financial Data for %s:\n", f.Ticker)
			fmt.Printf("      Total Assets: $%.2f\n", f.TotalAssets)
			fmt.Printf("      Total Debt: $%.2f\n", f.TotalDebt)
			fmt.Printf("      Total Revenue: $%.2f\n", f.TotalRevenue)
			fmt.Printf("      Net Income: $%.2f\n", f.NetIncome)
			fmt.Printf("      As Of Date: %s\n", f.AsOfDate)
			
			// Calculate debt ratio
			if f.TotalAssets > 0 {
				debtRatio := (f.TotalDebt / f.TotalAssets) * 100
				fmt.Printf("\n   💰 Calculated Debt Ratio: %.2f%%\n", debtRatio)
			}
		}
	}

	fmt.Println()
	fmt.Println("✅ Fundamentals test complete!")
	fmt.Println()
	fmt.Println("ℹ️  Note: DataJockey doesn't have stock list/search endpoints.")
	fmt.Println("   Use the search feature in the app to find stocks by ticker.")
}

