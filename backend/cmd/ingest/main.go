package main

import (
	"halalstocks/internal/config"
	"halalstocks/internal/db"
	"halalstocks/internal/marketdata"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
	"log"
	"os"
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
	notificationRepo := repositories.NewNotificationRepository(database)

	// Initialize market data provider
	var marketDataProvider marketdata.MarketDataProvider
	switch cfg.StockAPIProvider {
	case "fmp":
		log.Println("Using FMP (Financial Modeling Prep) provider")
		marketDataProvider = marketdata.NewFMPProvider(cfg.StockAPIKey)
	case "alphavantage", "alpha":
		log.Println("Using Alpha Vantage provider")
		avp := marketdata.NewAlphaVantageProvider(cfg.AlphaVantageAPIKey)
		avp.SetStore(repositories.NewMarketRepository(database))
		marketDataProvider = avp
	case "datajockey":
		log.Println("Using DataJockey provider")
		marketDataProvider = marketdata.NewDataJockeyProvider(cfg.DataJockeyAPIKey)
	case "eodhd":
		log.Println("Using EODHD provider")
		ep := marketdata.NewEODHDProvider(cfg.EODHDAPIKey)
		ep.SetStore(repositories.NewMarketRepository(database))
		marketDataProvider = ep
	default:
		log.Printf("Unknown provider: %s, using Alpha Vantage", cfg.StockAPIProvider)
		avp := marketdata.NewAlphaVantageProvider(cfg.AlphaVantageAPIKey)
		avp.SetStore(repositories.NewMarketRepository(database))
		marketDataProvider = avp
	}

	// Initialize ingestion service
	ingestionService := services.NewIngestionService(
		cfg,
		marketDataProvider,
		stockRepo,
		fundamentalRepo,
		shariahRepo,
		notificationRepo,
	)

	// Run ingestion
	if err := ingestionService.RunIngestion(); err != nil {
		log.Printf("Ingestion failed: %v", err)
		os.Exit(1)
	}

	log.Println("Ingestion completed successfully")
}
