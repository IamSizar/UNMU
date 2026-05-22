package main

import (
	"database/sql"
	"log"
	"time"
	"halalstocks/internal/config"
	"halalstocks/internal/db"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"halalstocks/internal/shariah"
)

func main() {
	log.Println("Starting re-screening of stocks with fundamentals...")

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
	shariahRepo := repositories.NewShariahStatusRepository(database)

	// Get all stocks with fundamentals
	query := `
		SELECT DISTINCT s.id, s.ticker, s.exchange, s.name, s.country, s.region_code, 
			s.sector, s.industry, s.description, s.market_cap, s.is_active
		FROM stocks s
		INNER JOIN fundamentals f ON s.id = f.stock_id
		WHERE f.total_assets IS NOT NULL AND f.total_debt IS NOT NULL
		AND s.is_active = TRUE
		ORDER BY s.ticker
	`

	rows, err := database.Query(query)
	if err != nil {
		log.Fatalf("Failed to query stocks: %v", err)
	}
	defer rows.Close()

	count := 0
	updated := 0
	errors := 0

	for rows.Next() {
		count++
		var stock models.Stock
		var country, regionCode, sector, industry, description sql.NullString
		var marketCap sql.NullInt64

		err := rows.Scan(
			&stock.ID, &stock.Ticker, &stock.Exchange, &stock.Name,
			&country, &regionCode, &sector, &industry, &description,
			&marketCap, &stock.IsActive,
		)
		if err != nil {
			log.Printf("Error scanning stock: %v", err)
			errors++
			continue
		}

		stock.Country = country
		stock.RegionCode = regionCode
		stock.Sector = sector
		stock.Industry = industry
		stock.Description = description
		stock.MarketCap = marketCap

		// Get latest fundamental
		fundamental, err := fundamentalRepo.GetLatestFundamental(stock.ID)
		if err != nil {
			log.Printf("Error getting fundamental for %s: %v", stock.Ticker, err)
			errors++
			continue
		}

		if fundamental == nil {
			log.Printf("No fundamental found for %s", stock.Ticker)
			continue
		}

		// Verify the fundamental has Valid flags set by checking database directly
		// If Valid flags aren't set but values exist in DB, fix them
		var dbAssets, dbDebt sql.NullFloat64
		checkQuery := `SELECT total_assets, total_debt FROM fundamentals WHERE id = $1`
		if err := database.QueryRow(checkQuery, fundamental.ID).Scan(&dbAssets, &dbDebt); err == nil {
			// If database has values but Valid flags aren't set, fix them
			if dbAssets.Valid && !fundamental.TotalAssets.Valid {
				fundamental.TotalAssets = dbAssets
			}
			if dbDebt.Valid && !fundamental.TotalDebt.Valid {
				fundamental.TotalDebt = dbDebt
			}
			// If we fixed anything, update in database
			if (!fundamental.TotalAssets.Valid && dbAssets.Valid) || (!fundamental.TotalDebt.Valid && dbDebt.Valid) {
				if err := fundamentalRepo.CreateOrUpdate(fundamental); err != nil {
					log.Printf("Error updating fundamental for %s: %v", stock.Ticker, err)
					errors++
					continue
				}
			}
		}

		// Debug: Check Valid flags before screening
		if stock.Ticker == "AAPL" || stock.Ticker == "AMZN" {
			log.Printf("DEBUG %s: TotalAssets.Valid=%v, TotalAssets.Float64=%f, TotalDebt.Valid=%v, TotalDebt.Float64=%f",
				stock.Ticker,
				fundamental.TotalAssets.Valid, fundamental.TotalAssets.Float64,
				fundamental.TotalDebt.Valid, fundamental.TotalDebt.Float64)
		}

		// Run Sharia screening
		shariahStatus, err := shariah.Screen(&stock, fundamental)
		if err != nil {
			log.Printf("Error screening %s: %v", stock.Ticker, err)
			errors++
			continue
		}

		// Set as_of_date to today to ensure it's the latest status
		shariahStatus.AsOfDate = time.Now()

		// Debug: Check result
		if stock.Ticker == "AAPL" || stock.Ticker == "AMZN" {
			log.Printf("DEBUG %s: Status=%s, Grade=%s, DebtRatio.Valid=%v, DebtRatio.Float64=%f",
				stock.Ticker,
				shariahStatus.Status,
				getStringValue(shariahStatus.Grade),
				shariahStatus.DebtRatio.Valid,
				shariahStatus.DebtRatio.Float64)
		}

		// Save updated status
		if err := shariahRepo.CreateOrUpdate(&shariahStatus); err != nil {
			log.Printf("Error saving status for %s: %v", stock.Ticker, err)
			errors++
			continue
		}

		updated++
		if updated%10 == 0 {
			log.Printf("Processed %d stocks, updated %d, errors %d", count, updated, errors)
		}
	}

	log.Printf("Re-screening completed: Processed %d stocks, updated %d, errors %d", count, updated, errors)
}

func getStringValue(s sql.NullString) string {
	if s.Valid {
		return s.String
	}
	return ""
}

