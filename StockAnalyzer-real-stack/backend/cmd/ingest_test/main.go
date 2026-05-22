package main

import (
	"halalstocks/internal/config"
	"halalstocks/internal/db"
	"halalstocks/internal/marketdata"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
	"log"
)

func main() {
	// 1. Config (Load env or defaults)
	// We'll hardcode the API key for this test script as requested by user
	apiKey := "F6FegPuKcKze6tRJ8fw7Fd57fmUDCReU"

	cfg, err := config.Load()
	if err != nil {
		log.Printf("Warning: failed to load config, using defaults. Error: %v", err)
		// Proceed anyway if possible, or set defaults manually if critical
		if cfg == nil {
			cfg = &config.Config{
				DBHost:     "localhost",
				DBPort:     "5432",
				DBUser:     "postgres", // Adjust based on your local env if needed
				DBPassword: "password",
				DBName:     "halalstocks",
				DBSSLMode:  "disable",
			}
		}
	}
	// Update config to reflect FMP usage (for internal checks if any)
	cfg.StockAPIProvider = "fmp"
	cfg.StockAPIKey = apiKey

	// 2. DB Connection
	database, err := db.Connect(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer database.Close()

	// 3. Repositories
	stockRepo := repositories.NewStockRepository(database)
	fundamentalRepo := repositories.NewFundamentalRepository(database)
	shariahRepo := repositories.NewShariahStatusRepository(database)
	notificationRepo := repositories.NewNotificationRepository(database)

	// 4. Provider (FMP)
	provider := marketdata.NewFMPProvider(apiKey)

	// 5. Ingestion Service
	ingestionService := services.NewIngestionService(
		cfg,
		provider,
		stockRepo,
		fundamentalRepo,
		shariahRepo,
		notificationRepo,
	)

	// 6. Run
	log.Println("--- Starting EODHD Ingestion Test ---")
	err = ingestionService.RunIngestion()
	if err != nil {
		log.Fatalf("Ingestion failed: %v", err)
	}
	log.Println("--- Ingestion Complete ---")
}
