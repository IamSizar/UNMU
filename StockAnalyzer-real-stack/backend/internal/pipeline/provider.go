package pipeline

import (
	"context"
	"fmt"
	"log/slog"
	"time"
)

// Provider defines the interface for fetching stock data from external APIs
type Provider interface {
	// Name returns the provider's identifier
	Name() string

	// FetchSnapshot fetches fundamentals + latest price for a single symbol
	// Returns error if the symbol cannot be fetched or if the API call fails
	FetchSnapshot(ctx context.Context, symbol string, exchange string) (*StockSnapshot, error)

	// FetchSnapshotsBulk optionally fetches multiple symbols in one call
	// Returns a map of symbol -> snapshot, and any errors encountered
	// If a symbol fails, it should be omitted from the map but the error logged
	FetchSnapshotsBulk(ctx context.Context, symbols []string, exchanges []string) (map[string]*StockSnapshot, []error)

	// IsAvailable checks if the provider is currently available (e.g., API key valid, not rate limited)
	IsAvailable(ctx context.Context) bool
}

// ProviderRegistry manages multiple providers with priority ordering
type ProviderRegistry struct {
	providers []Provider
	logger    *slog.Logger
}

// NewProviderRegistry creates a new registry with ordered providers
func NewProviderRegistry(logger *slog.Logger, providers ...Provider) *ProviderRegistry {
	return &ProviderRegistry{
		providers: providers,
		logger:    logger,
	}
}

// FetchSnapshotFromAny attempts to fetch a snapshot from providers in order
// Returns the first successful, complete snapshot, or nil if all fail
// Also returns all errors encountered for debugging
func (r *ProviderRegistry) FetchSnapshotFromAny(ctx context.Context, symbol string, exchange string) (*StockSnapshot, []error) {
	var allErrors []error
	var bestSnapshot *StockSnapshot
	bestScore := 0.0

	for _, provider := range r.providers {
		// Check if provider is available
		if !provider.IsAvailable(ctx) {
			r.logger.Warn("Provider unavailable, skipping",
				"provider", provider.Name(),
				"symbol", symbol,
			)
			continue
		}

		// Attempt fetch with timeout
		providerCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
		snapshot, err := provider.FetchSnapshot(providerCtx, symbol, exchange)
		cancel()

		if err != nil {
			allErrors = append(allErrors, fmt.Errorf("%s: %w", provider.Name(), err))
			r.logger.Warn("Provider fetch failed",
				"provider", provider.Name(),
				"symbol", symbol,
				"error", err,
			)
			continue
		}

		if snapshot == nil {
			allErrors = append(allErrors, fmt.Errorf("%s: returned nil snapshot", provider.Name()))
			continue
		}

		// Assess quality
		snapshot.AssessQuality()

		// Check if this snapshot is complete enough
		if snapshot.IsComplete() {
			r.logger.Info("Successfully fetched complete snapshot",
				"provider", provider.Name(),
				"symbol", symbol,
				"quality", snapshot.DataQuality,
				"completeness", snapshot.CompletenessScore(),
			)
			return snapshot, allErrors
		}

		// Track best partial snapshot
		score := snapshot.CompletenessScore()
		if score > bestScore {
			bestScore = score
			bestSnapshot = snapshot
		}

		r.logger.Info("Fetched partial snapshot, trying next provider",
			"provider", provider.Name(),
			"symbol", symbol,
			"completeness", score,
		)
	}

	// If we have a partial snapshot, return it with a warning
	if bestSnapshot != nil {
		r.logger.Warn("No complete snapshot found, returning best partial",
			"symbol", symbol,
			"completeness", bestSnapshot.CompletenessScore(),
		)
		return bestSnapshot, allErrors
	}

	// All providers failed
	r.logger.Error("All providers failed to fetch snapshot",
		"symbol", symbol,
		"error_count", len(allErrors),
	)
	return nil, allErrors
}

// FetchSnapshotsBulkFromAny attempts to fetch multiple symbols using bulk operations when available
// Falls back to individual fetches if bulk is not supported
func (r *ProviderRegistry) FetchSnapshotsBulkFromAny(ctx context.Context, symbols []string, exchanges []string) (map[string]*StockSnapshot, []error) {
	var allErrors []error
	results := make(map[string]*StockSnapshot)

	// Try bulk fetch from first provider that supports it
	for _, provider := range r.providers {
		if !provider.IsAvailable(ctx) {
			continue
		}

		providerCtx, cancel := context.WithTimeout(ctx, 60*time.Second)
		snapshots, errs := provider.FetchSnapshotsBulk(providerCtx, symbols, exchanges)
		cancel()

		allErrors = append(allErrors, errs...)

		// Merge results
		for symbol, snapshot := range snapshots {
			if snapshot != nil && snapshot.IsComplete() {
				results[symbol] = snapshot
			}
		}

		// If we got most symbols, return early
		if len(results) >= len(symbols)*8/10 { // 80% success rate
			r.logger.Info("Bulk fetch successful",
				"provider", provider.Name(),
				"fetched", len(results),
				"total", len(symbols),
			)
			return results, allErrors
		}
	}

	// Fallback: fetch missing symbols individually
	missing := make(map[string]string) // symbol -> exchange
	for i, symbol := range symbols {
		if _, found := results[symbol]; !found {
			exchange := ""
			if i < len(exchanges) {
				exchange = exchanges[i]
			}
			missing[symbol] = exchange
		}
	}

	if len(missing) > 0 {
		r.logger.Info("Fetching missing symbols individually",
			"count", len(missing),
		)

		for symbol, exchange := range missing {
			snapshot, errs := r.FetchSnapshotFromAny(ctx, symbol, exchange)
			allErrors = append(allErrors, errs...)
			if snapshot != nil {
				results[symbol] = snapshot
			}
		}
	}

	return results, allErrors
}

