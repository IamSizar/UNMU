package main

import (
	"context"
	"log"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"halalstocks/internal/config"
	"halalstocks/internal/db"
	"halalstocks/internal/pipeline"
	"halalstocks/internal/pipeline/providers"
	"halalstocks/internal/shariah"

	_ "github.com/lib/pq"
)

func main() {
	// Setup structured logging
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	logger.Info("Starting daily update pipeline")

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

	// Initialize providers
	var providerList []pipeline.Provider

	// Primary provider: Database (use existing data as fallback/primary source)
	dbProvider := providers.NewDatabaseProvider(database, logger)
	providerList = append(providerList, dbProvider)
	logger.Info("Added Database provider", "provider", "Database")

	// Secondary provider: FMP (using adapter for existing implementation)
	// Use FMP if we have the key and provider is fmp, empty, or datajockey (fallback)
	if cfg.StockAPIKey != "" {
		if cfg.StockAPIProvider == "fmp" || cfg.StockAPIProvider == "" || cfg.StockAPIProvider == "datajockey" {
			fmpAdapter := providers.NewFMPAdapter(cfg.StockAPIKey, logger)
			providerList = append(providerList, fmpAdapter)
			logger.Info("Added FMP provider", "provider", "FMP", "api_key_set", cfg.StockAPIKey != "")
		}
	}

	// Secondary provider: Alpha Vantage (if configured)
	if cfg.AlphaVantageAPIKey != "" {
		// Note: You would implement AlphaVantageProvider similar to FMPProvider
		// For now, we'll use a placeholder
		logger.Info("Alpha Vantage provider not yet implemented")
	}

	// Tertiary provider: DataJockey (if configured)
	if cfg.DataJockeyAPIKey != "" {
		// Note: You would implement DataJockeyProvider similar to FMPProvider
		logger.Info("DataJockey provider not yet implemented")
	}

	if len(providerList) == 0 {
		log.Fatal("No providers configured. Please set at least one API key.")
	}

	// Create provider registry
	registry := pipeline.NewProviderRegistry(logger, providerList...)

	// Initialize repository
	repo := pipeline.NewRepository(database)

	// Initialize Shariah engine
	// Integrate with existing shariah package
	activityChecker := NewShariahActivityChecker()
	ratioCalculator := pipeline.NewStandardRatioCalculator()
	shariahEngine := pipeline.NewStandardShariahEngine(activityChecker, ratioCalculator)

	// Create pipeline
	workers := 5 // Can be made configurable
	updatePipeline := pipeline.NewDailyUpdatePipeline(
		registry,
		repo,
		shariahEngine,
		logger,
		workers,
	)

	// Setup graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// Run pipeline in goroutine
	done := make(chan error, 1)
	go func() {
		stats, err := updatePipeline.Run(ctx)
		if err != nil {
			done <- err
			return
		}

		// Log final statistics
		logger.Info("Pipeline completed successfully",
			"total_symbols", stats.TotalSymbols,
			"successful", stats.Successful,
			"failed", stats.Failed,
			"status_changes", stats.StatusChanges,
			"duration_seconds", stats.Duration.Seconds(),
		)

		done <- nil
	}()

	// Wait for completion or signal
	select {
	case err := <-done:
		if err != nil {
			log.Fatalf("Pipeline failed: %v", err)
		}
		logger.Info("Daily update completed successfully")
	case sig := <-sigChan:
		logger.Info("Received signal, shutting down", "signal", sig)
		cancel()
		// Wait for pipeline to finish with timeout
		select {
		case <-done:
			logger.Info("Pipeline stopped gracefully")
		case <-time.After(30 * time.Second):
			logger.Warn("Pipeline did not stop within timeout")
		}
	}
}

// ShariahActivityChecker integrates with existing shariah package
type ShariahActivityChecker struct{}

func NewShariahActivityChecker() *ShariahActivityChecker {
	return &ShariahActivityChecker{}
}

func (c *ShariahActivityChecker) CheckActivity(sector, industry, description string) (bool, string, []string) {
	// Use existing shariah.CheckHaramActivity function
	isHaram, reason := shariah.CheckHaramActivity(sector, industry, description)
	return !isHaram, reason, nil // Return compliance status (inverted)
}

