// Command ingest_eodhd pulls REAL fundamentals from EODHD for every stock
// already in the DB that EODHD covers, writes them to the `fundamentals`
// table (source="EODHD"), and re-runs the Shariah screening engine so each
// stock's Halal verdict reflects real financials.
//
// Stocks EODHD does NOT cover (the Gulf/MENA names + the mislabeled VAC) are
// skipped and left exactly as they are, so nothing breaks — they switch to
// real once a Gulf-capable second provider is added.
//
// Run:  STOCK_API_PROVIDER unaffected — this reads EODHD_API_KEY directly.
//   cd backend && go run ./cmd/ingest_eodhd
package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"halalstocks/internal/config"
	"halalstocks/internal/db"
	"halalstocks/internal/marketdata"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
)

// fatalf captures the error to Sentry (if configured), flushes so it
// actually gets sent before the process exits, then behaves like
// log.Fatalf. A plain log.Fatalf calls os.Exit immediately, which would
// otherwise drop whatever Sentry hasn't sent yet — this is the daily
// production screening job, so a failure here is worth knowing about.
// fatalf's own flush is load-bearing, not redundant with main()'s
// deferred FlushErrorTracking: log.Fatal calls os.Exit, which skips
// deferred functions entirely, so the defer only covers the normal-
// return path and this is the only flush that runs on a fatal exit.
func fatalf(tags map[string]string, format string, args ...any) {
	err := fmt.Errorf(format, args...)
	services.CaptureError(err, tags)
	services.FlushErrorTracking(2 * time.Second)
	log.Fatal(err)
}

func main() {
	// Intentionally NOT routed through fatalf/Sentry — Sentry has no DSN
	// to report to until config.Load() has already succeeded. This is the
	// one failure mode that can never be captured.
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	sentryEnabled := services.InitStandaloneErrorTracking()
	jobTags := map[string]string{"job": "ingest_eodhd"}

	if cfg.EODHDAPIKey == "" {
		fatalf(jobTags, "EODHD_API_KEY is not set in backend/.env")
	}

	database, err := db.Connect(cfg)
	if err != nil {
		fatalf(jobTags, "db connect: %v", err)
	}
	defer database.Close()
	if sentryEnabled {
		defer services.FlushErrorTracking(2 * time.Second)
	}

	stockRepo := repositories.NewStockRepository(database)
	fundRepo := repositories.NewFundamentalRepository(database)
	shariahRepo := repositories.NewShariahStatusRepository(database)
	notificationRepo := repositories.NewNotificationRepository(database)
	portfolioRepo := repositories.NewPortfolioRepository(database)

	// Compliance-drift push — this cron job is what actually changes a
	// stock's status in production, so it's where the drift alert has to
	// fire from. FCM is optional here exactly like everywhere else in the
	// app: if credentials aren't configured, DriftDetector still writes the
	// admin-visible notification row, it just skips the push fan-out.
	var notifier *services.Notifier
	if fcm, ferr := services.NewFCMSender(context.Background()); ferr == nil {
		userRepo := repositories.NewUserRepository(database)
		prefsRepo := repositories.NewNotificationPrefsRepository(database)
		pushTokenRepo := repositories.NewPushTokenRepository(database)
		notifier = services.NewNotifier(userRepo, prefsRepo, pushTokenRepo, fcm)
	} else {
		log.Printf("compliance-drift push disabled (FCM not configured): %v", ferr)
	}
	drift := services.NewDriftDetector(notificationRepo, portfolioRepo, notifier)

	// The per-stock loop lives in services.ScreeningRefresher so the daily
	// job runner in the API server shares it (docs/pulse/AUTODRAFT.md).
	refresher := &services.ScreeningRefresher{
		Stocks:   stockRepo,
		Funds:    fundRepo,
		Statuses: shariahRepo,
		Settings: repositories.NewAppSettingsRepository(database),
		Drift:    drift,
		Provider: marketdata.NewEODHDProvider(cfg.EODHDAPIKey),
	}
	stats, err := refresher.RefreshAll(context.Background())
	if err != nil {
		fatalf(jobTags, "%v", err)
	}

	log.Printf("──────────────────────────────────────────")
	log.Printf("DONE — %d real, %d skipped (left on demo), %d failed", stats.Real, stats.Skipped, stats.Failed)
}
