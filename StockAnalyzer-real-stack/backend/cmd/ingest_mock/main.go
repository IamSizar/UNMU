package main

import (
	"database/sql"
	"halalstocks/internal/config"
	"halalstocks/internal/db"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
	"log"
	"time"
)

func main() {
	// 1. Setup
	cfg := &config.Config{
		DBHost:     "localhost",
		DBPort:     "5432",
		DBUser:     "zaidaqrawi",
		DBPassword: "",
		DBName:     "halalstocks",
		DBSSLMode:  "disable",
	}

	database, err := db.Connect(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer database.Close()

	stockRepo := repositories.NewStockRepository(database)
	fundamentalRepo := repositories.NewFundamentalRepository(database)
	shariahRepo := repositories.NewShariahStatusRepository(database)

	// We need the engine to run the screening
	shariahEngine := services.NewShariahEngineService()

	// 1.5 Cleanup Duplicates (Remove old NASDAQ/NYSE entries for these tickers)
	cleanupTickers := []string{"MSFT", "AAPL", "JPM", "TSLA", "DOW"}
	log.Println("Cleaning up potential duplicates (non-US exchanges)...")
	for _, t := range cleanupTickers {
		// Delete from child tables first (no cascading assumed)
		_, _ = database.Exec(`DELETE FROM shariah_status WHERE stock_id IN (SELECT id FROM stocks WHERE ticker = $1 AND exchange != 'US')`, t)
		_, _ = database.Exec(`DELETE FROM fundamentals WHERE stock_id IN (SELECT id FROM stocks WHERE ticker = $1 AND exchange != 'US')`, t)
		_, _ = database.Exec(`DELETE FROM stocks WHERE ticker = $1 AND exchange != 'US'`, t)
	}

	// 2. Mock Data Definitions
	// Based on "Minimal Dataset Example" provided by user

	type MockData struct {
		Stock       models.Stock
		Fundamental models.Fundamental
	}

	mockStocks := []MockData{
		// 1. MSFT: Compliant
		{
			Stock: models.Stock{
				Ticker:     "MSFT",
				Exchange:   "US",
				Name:       "Microsoft Corporation",
				Sector:     sql.NullString{String: "Technology", Valid: true},
				Industry:   sql.NullString{String: "Software - Infrastructure", Valid: true},
				MarketCap:  sql.NullInt64{Int64: 3000000000000, Valid: true}, // $3T
				RegionCode: sql.NullString{String: "US", Valid: true},
				Country:    sql.NullString{String: "USA", Valid: true},
				IsActive:   true,
			},
			Fundamental: models.Fundamental{
				TotalAssets:    sql.NullFloat64{Float64: 411000000000, Valid: true},
				TotalDebt:      sql.NullFloat64{Float64: 70000000000, Valid: true}, // Low Debt
				TotalRevenue:   sql.NullFloat64{Float64: 212000000000, Valid: true},
				InterestIncome: sql.NullFloat64{Float64: 3200000000, Valid: true}, // Low Interest Income (<2%)
				NetIncome:      sql.NullFloat64{Float64: 80000000000, Valid: true},
				Source:         sql.NullString{String: "MOCK", Valid: true},
				AsOfDate:       sql.NullTime{Time: time.Now(), Valid: true},
			},
		},
		// 2. AAPL: Compliant (Usually)
		{
			Stock: models.Stock{
				Ticker:     "AAPL",
				Exchange:   "US",
				Name:       "Apple Inc.",
				Sector:     sql.NullString{String: "Technology", Valid: true},
				Industry:   sql.NullString{String: "Consumer Electronics", Valid: true},
				MarketCap:  sql.NullInt64{Int64: 2800000000000, Valid: true}, // $2.8T
				RegionCode: sql.NullString{String: "US", Valid: true},
				Country:    sql.NullString{String: "USA", Valid: true},
				IsActive:   true,
			},
			Fundamental: models.Fundamental{
				TotalAssets:    sql.NullFloat64{Float64: 350000000000, Valid: true},
				TotalDebt:      sql.NullFloat64{Float64: 95000000000, Valid: true}, // ~3.4% Debt Ratio (Low)
				TotalRevenue:   sql.NullFloat64{Float64: 380000000000, Valid: true},
				InterestIncome: sql.NullFloat64{Float64: 2800000000, Valid: true}, // Low Interest Income
				Source:         sql.NullString{String: "MOCK", Valid: true},
				AsOfDate:       sql.NullTime{Time: time.Now(), Valid: true},
			},
		},
		// 3. JPM: Non-Compliant (Business Activity)
		{
			Stock: models.Stock{
				Ticker:     "JPM",
				Exchange:   "US",
				Name:       "JPMorgan Chase & Co.",
				Sector:     sql.NullString{String: "Financial Services", Valid: true}, // Will trigger Sector Check
				Industry:   sql.NullString{String: "Banks - Diversified", Valid: true},
				MarketCap:  sql.NullInt64{Int64: 500000000000, Valid: true},
				RegionCode: sql.NullString{String: "US", Valid: true},
				Country:    sql.NullString{String: "USA", Valid: true},
				IsActive:   true,
			},
			Fundamental: models.Fundamental{
				TotalAssets:    sql.NullFloat64{Float64: 3000000000000, Valid: true},
				TotalDebt:      sql.NullFloat64{Float64: 250000000000, Valid: true},
				TotalRevenue:   sql.NullFloat64{Float64: 150000000000, Valid: true},
				InterestIncome: sql.NullFloat64{Float64: 80000000000, Valid: true}, // High Interest Income
				Source:         sql.NullString{String: "MOCK", Valid: true},
				AsOfDate:       sql.NullTime{Time: time.Now(), Valid: true},
			},
		},
		// 4. TSLA: Borderline/Compliant (Check Debt)
		{
			Stock: models.Stock{
				Ticker:     "TSLA",
				Exchange:   "US",
				Name:       "Tesla Inc.",
				Sector:     sql.NullString{String: "Consumer Cyclical", Valid: true},
				Industry:   sql.NullString{String: "Auto Manufacturers", Valid: true},
				MarketCap:  sql.NullInt64{Int64: 600000000000, Valid: true},
				RegionCode: sql.NullString{String: "US", Valid: true},
				Country:    sql.NullString{String: "USA", Valid: true},
				IsActive:   true,
			},
			Fundamental: models.Fundamental{
				TotalAssets:    sql.NullFloat64{Float64: 100000000000, Valid: true},
				TotalDebt:      sql.NullFloat64{Float64: 5000000000, Valid: true}, // Very Low Debt
				TotalRevenue:   sql.NullFloat64{Float64: 90000000000, Valid: true},
				InterestIncome: sql.NullFloat64{Float64: 1000000000, Valid: true}, // ~1.1%
				Source:         sql.NullString{String: "MOCK", Valid: true},
				AsOfDate:       sql.NullTime{Time: time.Now(), Valid: true},
			},
		},
		// 5. TEST_FAIL_DEBT: Non-Compliant (High Debt)
		{
			Stock: models.Stock{
				Ticker:     "DOW",
				Exchange:   "US",
				Name:       "Dow Inc. (Mock High Debt)",
				Sector:     sql.NullString{String: "Basic Materials", Valid: true},
				Industry:   sql.NullString{String: "Chemicals", Valid: true},
				MarketCap:  sql.NullInt64{Int64: 30000000000, Valid: true}, // $30B
				RegionCode: sql.NullString{String: "US", Valid: true},
				Country:    sql.NullString{String: "USA", Valid: true},
				IsActive:   true,
			},
			Fundamental: models.Fundamental{
				TotalAssets:    sql.NullFloat64{Float64: 60000000000, Valid: true},
				TotalDebt:      sql.NullFloat64{Float64: 15000000000, Valid: true}, // $15B Debt / $30B Cap = 50% (>33%) -> FAIL
				TotalRevenue:   sql.NullFloat64{Float64: 40000000000, Valid: true},
				InterestIncome: sql.NullFloat64{Float64: 100000000, Valid: true},
				Source:         sql.NullString{String: "MOCK", Valid: true},
				AsOfDate:       sql.NullTime{Time: time.Now(), Valid: true},
			},
		},
	}

	// 3. Execution
	log.Println("Starting Mock Data Ingestion...")

	for _, data := range mockStocks {
		// A. Save Stock
		err := stockRepo.CreateOrUpdate(&data.Stock)
		if err != nil {
			log.Printf("Error saving stock %s: %v", data.Stock.Ticker, err)
			continue
		}

		// Retrieve correct ID
		existingStock, err := stockRepo.GetByTickerAndExchange(data.Stock.Ticker, data.Stock.Exchange)
		if err != nil {
			log.Printf("Error retrieving stock %s: %v", data.Stock.Ticker, err)
			continue
		}
		data.Fundamental.StockID = existingStock.ID

		// B. Save Fundamentals
		err = fundamentalRepo.CreateOrUpdate(&data.Fundamental)
		if err != nil {
			log.Printf("Error saving fundamentals for %s: %v", existingStock.Ticker, err)
			continue
		}

		// C. RUN SHARIAH SCREENING
		status := shariahEngine.ScreenStock(existingStock, &data.Fundamental)

		// D. Save Shariah Status
		err = shariahRepo.CreateOrUpdate(status)
		if err != nil {
			log.Printf("Error saving status for %s: %v", existingStock.Ticker, err)
			continue
		}

		log.Printf("Successfully processed %s: Status=%s, Grade=%s, DebtRatio=%.2f, IncomeRatio=%.2f",
			existingStock.Ticker, status.Status, status.Grade.String, status.DebtRatio.Float64, status.HaramIncomeRatio.Float64)
	}

	log.Println("Mock Data Ingestion Complete.")
}
