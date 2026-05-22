package main

import (
	"fmt"
	"log"
	"halalstocks/internal/config"
	"halalstocks/internal/db"
	"halalstocks/internal/repositories"
	"halalstocks/internal/shariah"
)

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Connect to database
	database, err := db.Connect(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer database.Close()

	// Initialize repositories
	stockRepo := repositories.NewStockRepository(database)
	fundamentalRepo := repositories.NewFundamentalRepository(database)

	// Get a stock with financial data
	stocks, err := stockRepo.GetAll(10, 0)
	if err != nil {
		log.Fatalf("Failed to get stocks: %v", err)
	}

	for _, stock := range stocks {
		fund, err := fundamentalRepo.GetLatestFundamental(stock.ID)
		if err != nil {
			log.Printf("Error getting fundamental for %s: %v", stock.Ticker, err)
			continue
		}

		if fund == nil {
			fmt.Printf("Stock %s (%s): No fundamental data\n", stock.Ticker, stock.Name)
			continue
		}

		fmt.Printf("\nStock: %s (%s)\n", stock.Ticker, stock.Name)
		fmt.Printf("  TotalAssets: Valid=%v, Value=%v\n", fund.TotalAssets.Valid, fund.TotalAssets.Float64)
		fmt.Printf("  TotalDebt: Valid=%v, Value=%v\n", fund.TotalDebt.Valid, fund.TotalDebt.Float64)
		fmt.Printf("  TotalRevenue: Valid=%v, Value=%v\n", fund.TotalRevenue.Valid, fund.TotalRevenue.Float64)
		fmt.Printf("  InterestIncome: Valid=%v, Value=%v\n", fund.InterestIncome.Valid, fund.InterestIncome.Float64)

		// Test screening
		status, err := shariah.Screen(stock, fund)
		if err != nil {
			log.Printf("Error screening: %v", err)
			continue
		}

		fmt.Printf("  Status: %s, Grade: %s\n", status.Status, status.Grade.String)
		fmt.Printf("  DebtRatio: Valid=%v, Value=%v\n", status.DebtRatio.Valid, status.DebtRatio.Float64)
		fmt.Printf("  Reason: %s\n", status.Reason.String)
	}
}

