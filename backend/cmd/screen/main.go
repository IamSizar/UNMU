package main

import (
	"log"
	"time"
	"halalstocks/internal/config"
	"halalstocks/internal/db"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"halalstocks/internal/shariah"
	"database/sql"
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
	shariahRepo := repositories.NewShariahStatusRepository(database)

	// Get all active stocks in batches
	log.Println("Fetching active stocks...")
	batchSize := 1000
	offset := 0
	totalProcessed := 0
	totalErrors := 0

	for {
		stocks, err := stockRepo.GetAll(batchSize, offset)
		if err != nil {
			log.Fatalf("Failed to get stocks: %v", err)
		}
		
		if len(stocks) == 0 {
			break
		}
		
		log.Printf("Processing batch: %d stocks (offset: %d)", len(stocks), offset)

		for _, stock := range stocks {
			// Get latest fundamental (optional - we can screen without it)
			fund, err := fundamentalRepo.GetLatestFundamental(stock.ID)
			if err != nil {
				log.Printf("Error getting fundamental for stock %d (%s): %v", stock.ID, stock.Ticker, err)
			}
			
			// Create empty fundamental if none exists (with proper AsOfDate)
			if fund == nil {
				fund = &models.Fundamental{
					StockID:  stock.ID,
					AsOfDate: sql.NullTime{Time: time.Now(), Valid: true},
				}
			} else if !fund.AsOfDate.Valid {
				// Ensure AsOfDate is valid
				fund.AsOfDate = sql.NullTime{Time: time.Now(), Valid: true}
			}

			// Run Shariah screening (works with or without fundamentals)
			shariahStatus, err := shariah.Screen(stock, fund)
			if err != nil {
				log.Printf("Error screening stock %d (%s): %v", stock.ID, stock.Ticker, err)
				totalErrors++
				continue
			}

			// Save/update status
			if err := shariahRepo.CreateOrUpdate(&shariahStatus); err != nil {
				log.Printf("Error saving status for stock %d (%s): %v", stock.ID, stock.Ticker, err)
				totalErrors++
				continue
			}

			totalProcessed++
			if totalProcessed%100 == 0 {
				log.Printf("Processed %d stocks...", totalProcessed)
			}
		}

		offset += batchSize
		if len(stocks) < batchSize {
			break
		}
	}

	log.Printf("\n✅ Screening complete!")
	log.Printf("   Processed: %d stocks", totalProcessed)
	log.Printf("   Errors: %d", totalErrors)
}
