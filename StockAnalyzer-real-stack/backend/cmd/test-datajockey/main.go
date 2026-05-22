package main

import (
	"fmt"
	"log"
	"os"

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
		os.Exit(1)
	}

	if cfg.DataJockeyAPIKey == "" {
		log.Fatal("DATAJOCKEY_API_KEY is not set in .env file")
	}

	// Create DataJockey provider
	provider := marketdata.NewDataJockeyProvider(cfg.DataJockeyAPIKey)

	fmt.Println("🧪 Testing DataJockey API...")
	fmt.Println()

	// Test 1: Search for a stock
	fmt.Println("1️⃣  Testing SearchStocks('AAPL')...")
	searchResults, err := provider.SearchStocks("AAPL")
	if err != nil {
		fmt.Printf("   ❌ Error: %v\n", err)
	} else {
		fmt.Printf("   ✅ Found %d stocks\n", len(searchResults))
		if len(searchResults) > 0 {
			fmt.Printf("   First result: %s (%s) - %s\n", 
				searchResults[0].Ticker, 
				searchResults[0].Exchange, 
				searchResults[0].Name)
		}
	}
	fmt.Println()

	// Test 2: Fetch stock universe (US region)
	fmt.Println("2️⃣  Testing FetchStockUniverse('US')...")
	usStocks, err := provider.FetchStockUniverse("US")
	if err != nil {
		fmt.Printf("   ❌ Error: %v\n", err)
	} else {
		fmt.Printf("   ✅ Found %d US stocks\n", len(usStocks))
		if len(usStocks) > 0 {
			fmt.Printf("   First 3 stocks:\n")
			for i, stock := range usStocks {
				if i >= 3 {
					break
				}
				fmt.Printf("      - %s (%s): %s\n", stock.Ticker, stock.Exchange, stock.Name)
			}
		}
	}
	fmt.Println()

	// Test 3: Fetch fundamentals (if search worked)
	if len(searchResults) > 0 {
		ticker := searchResults[0].Ticker
		fmt.Printf("3️⃣  Testing FetchFundamentalsBatch(['%s'])...\n", ticker)
		fundamentals, err := provider.FetchFundamentalsBatch([]string{ticker})
		if err != nil {
			fmt.Printf("   ❌ Error: %v\n", err)
		} else {
			fmt.Printf("   ✅ Found fundamentals for %d tickers\n", len(fundamentals))
			if len(fundamentals) > 0 {
				f := fundamentals[0]
				fmt.Printf("   Total Assets: %.2f\n", f.TotalAssets)
				fmt.Printf("   Total Debt: %.2f\n", f.TotalDebt)
				fmt.Printf("   Total Revenue: %.2f\n", f.TotalRevenue)
			}
		}
	}

	fmt.Println()
	fmt.Println("✅ Testing complete!")
}

