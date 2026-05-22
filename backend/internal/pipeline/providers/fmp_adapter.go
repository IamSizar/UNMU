package providers

import (
	"context"
	"fmt"
	"halalstocks/internal/marketdata"
	"halalstocks/internal/pipeline"
	"log/slog"
	"time"
)

// FMPAdapter adapts the existing marketdata.FMPProvider to the new pipeline.Provider interface
type FMPAdapter struct {
	provider *marketdata.FMPProvider
	logger   *slog.Logger
}

// NewFMPAdapter creates a new adapter for the existing FMP provider
func NewFMPAdapter(apiKey string, logger *slog.Logger) *FMPAdapter {
	if logger == nil {
		logger = slog.Default()
	}
	
	return &FMPAdapter{
		provider: marketdata.NewFMPProvider(apiKey),
		logger:   logger,
	}
}

func (a *FMPAdapter) Name() string {
	return "FMP"
}

func (a *FMPAdapter) IsAvailable(ctx context.Context) bool {
	// FMP provider is available if it was created (has API key)
	return a.provider != nil
}

func (a *FMPAdapter) FetchSnapshot(ctx context.Context, symbol string, exchange string) (*pipeline.StockSnapshot, error) {
	snapshot := &pipeline.StockSnapshot{
		Symbol:      symbol,
		Exchange:    exchange,
		SnapshotDate: time.Now().UTC(),
		ProviderName: a.Name(),
	}

	// Fetch fundamentals using existing provider
	fundamentals, err := a.provider.FetchFundamentalsBatch([]string{symbol})
	if err != nil || len(fundamentals) == 0 {
		return nil, fmt.Errorf("failed to fetch fundamentals: %w", err)
	}

	fund := fundamentals[0]

	// Map to StockSnapshot
	snapshot.CompanyName = fund.CompanyName
	snapshot.TotalAssets = fund.TotalAssets
	snapshot.TotalDebt = fund.TotalDebt
	snapshot.CashAndEquivalents = fund.CashAndEquiv
	snapshot.Revenue = fund.TotalRevenue
	snapshot.InterestIncome = fund.InterestIncome
	snapshot.InterestExpense = fund.InterestExpense
	snapshot.NetIncome = fund.NetIncome

	// Parse date
	if fund.AsOfDate != "" {
		if date, err := time.Parse("2006-01-02", fund.AsOfDate); err == nil {
			snapshot.LastReportDate = date
		}
	}

	// Fetch profile for additional info (sector, industry, description)
	// We'll use SearchStocks to get profile info
	stocks, err := a.provider.SearchStocks(symbol)
	if err == nil && len(stocks) > 0 {
		stock := stocks[0]
		snapshot.Sector = stock.Sector
		snapshot.Industry = stock.Industry
		snapshot.Description = stock.Description
		snapshot.Country = stock.Country
		if stock.MarketCap > 0 {
			snapshot.MarketCap = float64(stock.MarketCap)
		}
	}

	// Fetch price and market cap from profile
	// Note: The existing FMP provider doesn't expose price directly in FetchFundamentalsBatch
	// We'd need to add a method or use the profile endpoint
	// For now, we'll mark price as 0 if not available
	snapshot.Price = 0 // Will be populated if available

	// Assess quality
	snapshot.AssessQuality()

	return snapshot, nil
}

func (a *FMPAdapter) FetchSnapshotsBulk(ctx context.Context, symbols []string, exchanges []string) (map[string]*pipeline.StockSnapshot, []error) {
	results := make(map[string]*pipeline.StockSnapshot)
	var errors []error

	// Use existing provider's batch method
	fundamentals, err := a.provider.FetchFundamentalsBatch(symbols)
	if err != nil {
		errors = append(errors, fmt.Errorf("batch fetch failed: %w", err))
	}

	// Map fundamentals to snapshots
	for i, fund := range fundamentals {
		if i >= len(symbols) {
			break
		}
		symbol := symbols[i]
		exchange := ""
		if i < len(exchanges) {
			exchange = exchanges[i]
		}

		snapshot := &pipeline.StockSnapshot{
			Symbol:      symbol,
			Exchange:    exchange,
			SnapshotDate: time.Now().UTC(),
			ProviderName: a.Name(),
		}

		// Map fundamental data
		snapshot.CompanyName = fund.CompanyName
		snapshot.TotalAssets = fund.TotalAssets
		snapshot.TotalDebt = fund.TotalDebt
		snapshot.CashAndEquivalents = fund.CashAndEquiv
		snapshot.Revenue = fund.TotalRevenue
		snapshot.InterestIncome = fund.InterestIncome
		snapshot.InterestExpense = fund.InterestExpense
		snapshot.NetIncome = fund.NetIncome

		if fund.AsOfDate != "" {
			if date, err := time.Parse("2006-01-02", fund.AsOfDate); err == nil {
				snapshot.LastReportDate = date
			}
		}

		// Try to get profile info
		stocks, err := a.provider.SearchStocks(symbol)
		if err == nil && len(stocks) > 0 {
			stock := stocks[0]
			snapshot.Sector = stock.Sector
			snapshot.Industry = stock.Industry
			snapshot.Description = stock.Description
			snapshot.Country = stock.Country
			if stock.MarketCap > 0 {
				snapshot.MarketCap = float64(stock.MarketCap)
			}
		}

		snapshot.AssessQuality()
		results[symbol] = snapshot
	}

	return results, errors
}

