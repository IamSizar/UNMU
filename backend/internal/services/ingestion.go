package services

import (
	"fmt"
	"log"
	"halalstocks/internal/config"
	"halalstocks/internal/marketdata"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"halalstocks/internal/shariah"
	"database/sql"
	"time"
)

type IngestionService struct {
	cfg              *config.Config
	marketDataProvider marketdata.MarketDataProvider
	stockRepo        *repositories.StockRepository
	fundamentalRepo  *repositories.FundamentalRepository
	shariahRepo      *repositories.ShariahStatusRepository
	notificationRepo *repositories.NotificationRepository
}

func NewIngestionService(
	cfg *config.Config,
	marketDataProvider marketdata.MarketDataProvider,
	stockRepo *repositories.StockRepository,
	fundamentalRepo *repositories.FundamentalRepository,
	shariahRepo *repositories.ShariahStatusRepository,
	notificationRepo *repositories.NotificationRepository,
) *IngestionService {
	return &IngestionService{
		cfg:               cfg,
		marketDataProvider: marketDataProvider,
		stockRepo:         stockRepo,
		fundamentalRepo:   fundamentalRepo,
		shariahRepo:       shariahRepo,
		notificationRepo: notificationRepo,
	}
}

func (s *IngestionService) RunIngestion() error {
	log.Println("Starting stock data ingestion...")

	// Process all regions
	regions := []string{"US", "GCC", "MENA", "EU", "ASIA", "CN", "GLOBAL"}
	
	for _, region := range regions {
		log.Printf("Processing region: %s", region)
		
		// Fetch stocks from API
		stocks, err := s.marketDataProvider.FetchStockUniverse(region)
		if err != nil {
			log.Printf("Error fetching stocks for region %s: %v", region, err)
			continue
		}

		log.Printf("Fetched %d stocks for region %s", len(stocks), region)

		// Process each stock
		for _, stockAPI := range stocks {
			if err := s.processStock(stockAPI); err != nil {
				log.Printf("Error processing stock %s: %v", stockAPI.Ticker, err)
				continue
			}
		}
	}

	log.Println("Ingestion completed")
	return nil
}

func (s *IngestionService) processStock(stockAPI marketdata.StockFromAPI) error {
	// Create or update stock
	stock := &models.Stock{
		Ticker:   stockAPI.Ticker,
		Exchange: stockAPI.Exchange,
		Name:     stockAPI.Name,
		IsActive: true,
	}
	
	if stockAPI.Country != "" {
		stock.Country = sql.NullString{String: stockAPI.Country, Valid: true}
	}
	if stockAPI.RegionCode != "" {
		stock.RegionCode = sql.NullString{String: stockAPI.RegionCode, Valid: true}
	}
	if stockAPI.Sector != "" {
		stock.Sector = sql.NullString{String: stockAPI.Sector, Valid: true}
	}
	if stockAPI.Industry != "" {
		stock.Industry = sql.NullString{String: stockAPI.Industry, Valid: true}
	}
	if stockAPI.Description != "" {
		stock.Description = sql.NullString{String: stockAPI.Description, Valid: true}
	}
	if stockAPI.MarketCap > 0 {
		stock.MarketCap = sql.NullInt64{Int64: stockAPI.MarketCap, Valid: true}
	}

	if err := s.stockRepo.CreateOrUpdate(stock); err != nil {
		return fmt.Errorf("failed to create/update stock: %w", err)
	}

	// Fetch fundamentals
	fundamentalsAPI, err := s.marketDataProvider.FetchFundamentalsBatch([]string{stockAPI.Ticker})
	
	var fundamental *models.Fundamental
	if err != nil || len(fundamentalsAPI) == 0 {
		log.Printf("No fundamentals for %s, running activity-based Sharia screening only", stockAPI.Ticker)
		// Create empty fundamental for activity-based screening
		fundamental = &models.Fundamental{
			StockID:  stock.ID,
			AsOfDate: sql.NullTime{Time: time.Now(), Valid: true},
		}
	} else {
		fundAPI := fundamentalsAPI[0]
		
		// Update stock name from fundamentals if available and current name is just the ticker
		if fundAPI.CompanyName != "" && (stock.Name == stock.Ticker || stock.Name == "") {
			stock.Name = fundAPI.CompanyName
			// Update the stock record with the company name
			if err := s.stockRepo.CreateOrUpdate(stock); err != nil {
				log.Printf("Warning: Failed to update stock name for %s: %v", stock.Ticker, err)
			} else {
				log.Printf("Updated stock name for %s: %s", stock.Ticker, fundAPI.CompanyName)
			}
		}
		
		// Create or update fundamental
		fundamental = &models.Fundamental{
			StockID: stock.ID,
		}
		
		// Set values if they exist (including 0, which is valid for debt, revenue, etc.)
		// Only skip if the value is truly missing (we'll check if > 0 for some fields that can't be 0)
		if fundAPI.TotalAssets > 0 {
			fundamental.TotalAssets = sql.NullFloat64{Float64: fundAPI.TotalAssets, Valid: true}
		}
		// TotalDebt can be 0 (no debt is good!), so we need to check if it was provided
		// Since DataJockey returns 0 for companies with no debt, we should accept 0 as valid
		// We'll set it if TotalAssets exists (meaning we got financial data)
		if fundAPI.TotalAssets > 0 {
			// If TotalDebt was provided (even if 0), set it
			fundamental.TotalDebt = sql.NullFloat64{Float64: fundAPI.TotalDebt, Valid: true}
		}
		if fundAPI.CashAndEquiv > 0 {
			fundamental.CashAndEquiv = sql.NullFloat64{Float64: fundAPI.CashAndEquiv, Valid: true}
		}
		if fundAPI.TotalRevenue > 0 {
			fundamental.TotalRevenue = sql.NullFloat64{Float64: fundAPI.TotalRevenue, Valid: true}
		}
		// InterestIncome and InterestExpense can be 0 for non-financial companies
		// Only set if we have revenue data (meaning we got financial statements)
		if fundAPI.TotalRevenue > 0 {
			// Set interest fields even if 0 (0 means no interest income/expense, which is valid)
			fundamental.InterestIncome = sql.NullFloat64{Float64: fundAPI.InterestIncome, Valid: true}
			fundamental.InterestExpense = sql.NullFloat64{Float64: fundAPI.InterestExpense, Valid: true}
		}
		if fundAPI.NetIncome != 0 {
			fundamental.NetIncome = sql.NullFloat64{Float64: fundAPI.NetIncome, Valid: true}
		}
		if fundAPI.DividendsPerShare > 0 {
			fundamental.DividendsPerShare = sql.NullFloat64{Float64: fundAPI.DividendsPerShare, Valid: true}
		}
		
		if fundAPI.AsOfDate != "" {
			if date, err := time.Parse("2006-01-02", fundAPI.AsOfDate); err == nil {
				fundamental.AsOfDate = sql.NullTime{Time: date, Valid: true}
			}
		} else {
			fundamental.AsOfDate = sql.NullTime{Time: time.Now(), Valid: true}
		}
		
		// Set source based on provider
		source := "datajockey"
		switch s.cfg.StockAPIProvider {
case "fmp":
			source = "FMP"
		case "alphavantage", "alpha":
			source = "AlphaVantage"
		}
		fundamental.Source = sql.NullString{String: source, Valid: true}
		if fundAPI.RawJSON != "" {
			fundamental.RawJSON = sql.NullString{String: fundAPI.RawJSON, Valid: true}
		}

		if err := s.fundamentalRepo.CreateOrUpdate(fundamental); err != nil {
			return fmt.Errorf("failed to create/update fundamental: %w", err)
		}
	}

	// Run Sharia screening (works with or without financial data)
	shariahStatus, err := shariah.Screen(stock, fundamental)
	if err != nil {
		return fmt.Errorf("failed to screen stock: %w", err)
	}

	// Normalize as_of_date to just the date (no time component) to ensure updates work correctly
	// This ensures that multiple runs on the same day will update the same record
	// Use UTC to avoid timezone issues
	if shariahStatus.AsOfDate.IsZero() {
		shariahStatus.AsOfDate = time.Now().UTC()
	}
	// Truncate to date only (remove time component) - use UTC to ensure consistency
	shariahStatus.AsOfDate = time.Date(
		shariahStatus.AsOfDate.Year(),
		shariahStatus.AsOfDate.Month(),
		shariahStatus.AsOfDate.Day(),
		0, 0, 0, 0,
		time.UTC,
	)
	
	// Log for debugging
	log.Printf("Setting Sharia status for %s with date: %s", stock.Ticker, shariahStatus.AsOfDate.Format("2006-01-02"))

	// Get latest status to check for changes (not previous, but latest)
	latestStatus, _ := s.shariahRepo.GetLatestStatus(stock.ID)
	
	// Save new status (will update if same stock_id and as_of_date exist)
	if err := s.shariahRepo.CreateOrUpdate(&shariahStatus); err != nil {
		return fmt.Errorf("failed to save Sharia status: %w", err)
	}

	// Check for status changes and create notifications
	// Only notify if this is actually a change (not just an update of the same day's status)
	if latestStatus != nil {
		// Check if the latest status is from a different date (not just an update)
		latestDate := time.Date(
			latestStatus.AsOfDate.Year(),
			latestStatus.AsOfDate.Month(),
			latestStatus.AsOfDate.Day(),
			0, 0, 0, 0,
			latestStatus.AsOfDate.Location(),
		)
		newDate := time.Date(
			shariahStatus.AsOfDate.Year(),
			shariahStatus.AsOfDate.Month(),
			shariahStatus.AsOfDate.Day(),
			0, 0, 0, 0,
			shariahStatus.AsOfDate.Location(),
		)
		
		// Only notify if it's a different date AND the status changed
		if !latestDate.Equal(newDate) && latestStatus.Status != shariahStatus.Status {
			// Status changed on a new date - notify users
			s.createStatusChangeNotification(stock, latestStatus.Status, shariahStatus.Status)
		}
		
		// Check purification rate change (only if different date)
		if !latestDate.Equal(newDate) && latestStatus.PurificationRate.Valid && shariahStatus.PurificationRate.Valid {
			change := shariahStatus.PurificationRate.Float64 - latestStatus.PurificationRate.Float64
			if change > 0.5 || change < -0.5 { // Significant change
				s.createPurificationChangeNotification(stock, latestStatus.PurificationRate.Float64, shariahStatus.PurificationRate.Float64)
			}
		}
	}

	return nil
}

func (s *IngestionService) createStatusChangeNotification(stock *models.Stock, oldStatus, newStatus string) {
	// Get all users who have this stock in their portfolio
	// For now, create a general notification (would need portfolio repo)
	notification := &models.Notification{
		StockID:   sql.NullInt64{Int64: stock.ID, Valid: true},
		Type:      "STATUS_CHANGE",
		Title:     fmt.Sprintf("Sharia Status Changed: %s", stock.Ticker),
		Message:   fmt.Sprintf("The Sharia status of %s has changed from %s to %s", stock.Name, oldStatus, newStatus),
		IsRead:    false,
	}
	
	// This would need to be sent to all users with this stock
	// For now, we'll skip user_id (NULL) to indicate it's a general notification
	s.notificationRepo.Create(notification)
}

func (s *IngestionService) createPurificationChangeNotification(stock *models.Stock, oldRate, newRate float64) {
	notification := &models.Notification{
		StockID:   sql.NullInt64{Int64: stock.ID, Valid: true},
		Type:      "PURIFICATION_CHANGE",
		Title:     fmt.Sprintf("Purification Rate Changed: %s", stock.Ticker),
		Message:   fmt.Sprintf("The purification rate for %s has changed from %.2f%% to %.2f%%", stock.Name, oldRate, newRate),
		IsRead:    false,
	}
	
	s.notificationRepo.Create(notification)
}
