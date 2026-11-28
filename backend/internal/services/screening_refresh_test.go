package services

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"testing"

	_ "github.com/lib/pq"

	"halalstocks/internal/marketdata"
	"halalstocks/internal/repositories"
)

type rejectingFetcher struct{}

func (rejectingFetcher) FetchFundamentalsBatch([]string) ([]marketdata.FundamentalsFromAPI, error) {
	return nil, fmt.Errorf("%w: HTTP 401 on fundamentals", marketdata.ErrEODHDAuth)
}

// A rejected EODHD key must fail the run (not "succeeded, 0 refreshed").
// Needs a database with stocks: runs only when PULSE_TEST_DSN is set.
func TestRefreshFailsOnRejectedKey(t *testing.T) {
	dsn := os.Getenv("PULSE_TEST_DSN")
	if dsn == "" {
		t.Skip("PULSE_TEST_DSN not set")
	}
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	r := &ScreeningRefresher{
		Stocks:   repositories.NewStockRepository(db),
		Settings: repositories.NewAppSettingsRepository(db),
		Provider: rejectingFetcher{},
	}
	_, err = r.RefreshAll(context.Background())
	if !errors.Is(err, marketdata.ErrEODHDAuth) {
		t.Fatalf("want ErrEODHDAuth, got %v", err)
	}
}
