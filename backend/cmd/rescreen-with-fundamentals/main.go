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
	fundamentalRepo := repositories.NewFundamentalRepository(database)

	// Get all stocks that have fundamentals but status is UNKNOWN or has "Not available" in reason
	log.Println("Finding stocks with fundamentals but outdated status...")
	
	query := `
		SELECT DISTINCT s.id, s.ticker, s.exchange, s.name
		FROM stocks s
		INNER JOIN fundamentals f ON s.id = f.stock_id
		LEFT JOIN shariah_status ss ON s.id = ss.stock_id
		WHERE s.is_active = TRUE
		AND (ss.status = 'UNKNOWN' 
			OR ss.reason LIKE '%Not available%'
			OR ss.id IS NULL)
		AND (f.total_assets IS NOT NULL OR f.total_debt IS NOT NULL)
		ORDER BY s.id
		LIMIT 10000
	`
	
	rows, err := database.Query(query)
	if err != nil {
		log.Fatalf("Failed to query stocks: %v", err)
	}
	defer rows.Close()

	var stocksToRescreen []*models.Stock
	for rows.Next() {
		stock := &models.Stock{}
		err := rows.Scan(&stock.ID, &stock.Ticker, &stock.Exchange, &stock.Name)
		if err != nil {
			log.Printf("Error scanning stock: %v", err)
			continue
		}
		stocksToRescreen = append(stocksToRescreen, stock)
	}

	log.Printf("Found %d stocks with fundamentals that need re-screening", len(stocksToRescreen))

	processed := 0
	errors := 0

	for _, stock := range stocksToRescreen {
		// Get latest fundamental
		fund, err := fundamentalRepo.GetLatestFundamental(stock.ID)
		if err != nil {
			log.Printf("Error getting fundamental for stock %d (%s): %v", stock.ID, stock.Ticker, err)
			errors++
			continue
		}
		
		if fund == nil {
			log.Printf("No fundamental found for stock %d (%s)", stock.ID, stock.Ticker)
			continue
		}

		// Ensure AsOfDate is valid
		if !fund.AsOfDate.Valid {
			fund.AsOfDate = sql.NullTime{Time: time.Now(), Valid: true}
		}

		// Run Shariah screening
		shariahStatus, err := shariah.Screen(stock, fund)
		if err != nil {
			log.Printf("Error screening stock %d (%s): %v", stock.ID, stock.Ticker, err)
			errors++
			continue
		}

		// Force update the status (delete old and insert new to ensure update)
		// First, delete existing status for this stock
		deleteQuery := `DELETE FROM shariah_status WHERE stock_id = $1`
		_, err = database.Exec(deleteQuery, stock.ID)
		if err != nil {
			log.Printf("Error deleting old status for stock %d (%s): %v", stock.ID, stock.Ticker, err)
		}

		// Insert new status
		insertQuery := `
			INSERT INTO shariah_status (stock_id, status, grade, debt_ratio, haram_income_ratio, 
				purification_rate, pays_zakat, explanation, reason, as_of_date, created_at, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		`
		_, err = database.Exec(insertQuery,
			shariahStatus.StockID, shariahStatus.Status, shariahStatus.Grade,
			shariahStatus.DebtRatio, shariahStatus.HaramIncomeRatio, shariahStatus.PurificationRate,
			shariahStatus.PaysZakat, shariahStatus.Explanation, shariahStatus.Reason,
			shariahStatus.AsOfDate, time.Now(), time.Now(),
		)
		if err != nil {
			log.Printf("Error inserting status for stock %d (%s): %v", stock.ID, stock.Ticker, err)
			errors++
			continue
		}

		processed++
		if processed%100 == 0 {
			log.Printf("Processed %d stocks... (Status: %s, Grade: %s, DebtRatio: %.2f%%)", 
				processed, shariahStatus.Status, shariahStatus.Grade.String, 
				func() float64 {
					if shariahStatus.DebtRatio.Valid {
						return shariahStatus.DebtRatio.Float64
					}
					return 0
				}())
		}
	}

	log.Printf("\n✅ Re-screening complete!")
	log.Printf("   Processed: %d stocks", processed)
	log.Printf("   Errors: %d", errors)
}

