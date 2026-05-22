package pipeline

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"
)

// DailyUpdatePipeline orchestrates the daily data update process
type DailyUpdatePipeline struct {
	registry      *ProviderRegistry
	repository    *Repository
	shariahEngine ShariahEngine
	logger        *slog.Logger
	workers       int
}

// PipelineStats tracks statistics for the update run
type PipelineStats struct {
	TotalSymbols      int
	Processed          int
	Successful         int
	Failed             int
	StatusChanges      int
	NeedsReview        int
	ProviderFailures   map[string]int
	StartTime          time.Time
	EndTime            time.Time
	Duration           time.Duration
}

// NewDailyUpdatePipeline creates a new pipeline instance
func NewDailyUpdatePipeline(
	registry *ProviderRegistry,
	repository *Repository,
	shariahEngine ShariahEngine,
	logger *slog.Logger,
	workers int,
) *DailyUpdatePipeline {
	if logger == nil {
		logger = slog.Default()
	}
	if workers <= 0 {
		workers = 5 // Default to 5 concurrent workers
	}

	return &DailyUpdatePipeline{
		registry:      registry,
		repository:    repository,
		shariahEngine: shariahEngine,
		logger:        logger,
		workers:       workers,
	}
}

// Run executes the daily update pipeline
func (p *DailyUpdatePipeline) Run(ctx context.Context) (*PipelineStats, error) {
	stats := &PipelineStats{
		StartTime:        time.Now(),
		ProviderFailures: make(map[string]int),
	}

	p.logger.Info("Starting daily update pipeline")

	// Get list of tracked symbols
	symbols, err := p.repository.ListTrackedSymbols(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to list tracked symbols: %w", err)
	}

	stats.TotalSymbols = len(symbols)
	p.logger.Info("Found tracked symbols", "count", stats.TotalSymbols)

	// Process symbols with worker pool
	stats = p.processSymbols(ctx, symbols, stats)

	stats.EndTime = time.Now()
	stats.Duration = stats.EndTime.Sub(stats.StartTime)

	p.logger.Info("Daily update pipeline completed",
		"total", stats.TotalSymbols,
		"processed", stats.Processed,
		"successful", stats.Successful,
		"failed", stats.Failed,
		"status_changes", stats.StatusChanges,
		"needs_review", stats.NeedsReview,
		"duration", stats.Duration,
	)

	return stats, nil
}

// processSymbols processes symbols using a worker pool pattern
func (p *DailyUpdatePipeline) processSymbols(ctx context.Context, symbols []SymbolExchange, stats *PipelineStats) *PipelineStats {
	// Create channels for work distribution
	jobs := make(chan SymbolExchange, len(symbols))
	results := make(chan *SymbolResult, len(symbols))

	// Start workers
	var wg sync.WaitGroup
	for i := 0; i < p.workers; i++ {
		wg.Add(1)
		go p.worker(ctx, jobs, results, &wg)
	}

	// Send jobs
	for _, symbol := range symbols {
		jobs <- symbol
	}
	close(jobs)

	// Collect results
	go func() {
		wg.Wait()
		close(results)
	}()

	// Process results
	for result := range results {
		stats.Processed++
		if result.Error != nil {
			stats.Failed++
			p.logger.Warn("Failed to process symbol",
				"symbol", result.Symbol,
				"exchange", result.Exchange,
				"error", result.Error,
			)
			if result.ProviderName != "" {
				stats.ProviderFailures[result.ProviderName]++
			}
		} else {
			stats.Successful++
			if result.StatusChanged {
				stats.StatusChanges++
			}
			if result.Result != nil && result.Result.Status == ShariahStatusNeedsReview {
				stats.NeedsReview++
			}
		}
	}

	return stats
}

// SymbolResult represents the result of processing a single symbol
type SymbolResult struct {
	Symbol        string
	Exchange      string
	ProviderName  string
	Result        *ShariahResult
	StatusChanged bool
	Error         error
}

// worker processes symbols from the jobs channel
func (p *DailyUpdatePipeline) worker(ctx context.Context, jobs <-chan SymbolExchange, results chan<- *SymbolResult, wg *sync.WaitGroup) {
	defer wg.Done()

	for symbol := range jobs {
		result := p.processSymbol(ctx, symbol)
		results <- result
	}
}

// processSymbol processes a single symbol through the full pipeline
func (p *DailyUpdatePipeline) processSymbol(ctx context.Context, symbol SymbolExchange) *SymbolResult {
	result := &SymbolResult{
		Symbol:   symbol.Symbol,
		Exchange: symbol.Exchange,
	}

	// Create context with timeout for this symbol
	symbolCtx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()

	// Step 1: Fetch snapshot from any available provider
	snapshot, errors := p.registry.FetchSnapshotFromAny(symbolCtx, symbol.Symbol, symbol.Exchange)
	if snapshot == nil {
		result.Error = fmt.Errorf("all providers failed: %v", errors)
		return result
	}

	result.ProviderName = snapshot.ProviderName

	// Step 2: Upsert stock basic info
	if err := p.repository.UpsertStock(symbolCtx, snapshot); err != nil {
		p.logger.Warn("Failed to upsert stock", "symbol", symbol.Symbol, "error", err)
		// Continue anyway - not critical
	}

	// Step 3: Insert snapshot (time-series data)
	if err := p.repository.InsertSnapshot(symbolCtx, snapshot); err != nil {
		result.Error = fmt.Errorf("failed to insert snapshot: %w", err)
		return result
	}

	// Step 4: Evaluate Shariah compliance
	shariahResult, err := p.shariahEngine.Evaluate(snapshot)
	if err != nil {
		result.Error = fmt.Errorf("failed to evaluate shariah compliance: %w", err)
		return result
	}

	// Step 5: Check for status changes
	lastResult, err := p.repository.GetLastShariahResult(symbolCtx, symbol.Symbol, symbol.Exchange)
	if err != nil {
		p.logger.Warn("Failed to get last shariah result", "symbol", symbol.Symbol, "error", err)
		// Continue anyway
	}

	if lastResult != nil && lastResult.Status != shariahResult.Status {
		result.StatusChanged = true
		p.logger.Info("Shariah status changed",
			"symbol", symbol.Symbol,
			"old_status", lastResult.Status,
			"new_status", shariahResult.Status,
		)
	}

	// Step 6: Upsert latest Shariah result
	// The database trigger will automatically create history entry if status changed
	if err := p.repository.UpsertLatestShariahResult(symbolCtx, shariahResult); err != nil {
		result.Error = fmt.Errorf("failed to upsert shariah result: %w", err)
		return result
	}

	result.Result = shariahResult

	p.logger.Debug("Successfully processed symbol",
		"symbol", symbol.Symbol,
		"status", shariahResult.Status,
		"provider", snapshot.ProviderName,
	)

	return result
}

