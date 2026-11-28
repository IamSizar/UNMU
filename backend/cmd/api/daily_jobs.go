// daily_jobs.go — builds the daily job runner (screening refresh, Pulse
// auto-draft). Kept out of main.go, which is already long.
// See docs/pulse/AUTODRAFT.md.
package main

import (
	"context"
	"log"
	"time"

	"halalstocks/internal/config"
	"halalstocks/internal/marketdata"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
)

// dailyJobDeps are the repos the daily jobs need.
type dailyJobDeps struct {
	cfg        *config.Config
	jobRuns    *repositories.JobRunRepository
	stocks     *repositories.StockRepository
	funds      *repositories.FundamentalRepository
	statuses   *repositories.ShariahStatusRepository
	settings   *repositories.AppSettingsRepository
	pulseAdmin *repositories.PulseAdminRepository
	drift      *services.DriftDetector
	// Store refunds (docs/payments/REFUNDS_PLAN.md).
	googlePlay  *services.GooglePlayVerifier
	storeGrants *repositories.StoreAccessGrantRepository
}

// buildDailyJobs registers each enabled job. A job whose keys are missing
// is skipped with a log line rather than failing start-up.
func buildDailyJobs(d dailyJobDeps) *services.DailyJobRunner {
	runner := services.NewDailyJobRunner(d.jobRuns)
	cfg := d.cfg
	registerStoreRefunds(runner, d)
	if cfg.EODHDAPIKey == "" {
		log.Printf("[daily-jobs] EODHD_API_KEY not set: no daily jobs")
		return runner
	}
	eodhd := marketdata.NewEODHDProvider(cfg.EODHDAPIKey)
	if cfg.DailyScreeningEnabled {
		refresher := &services.ScreeningRefresher{
			Stocks: d.stocks, Funds: d.funds, Statuses: d.statuses,
			Settings: d.settings, Drift: d.drift, Provider: eodhd,
		}
		runner.Register(services.DailyJob{
			Name: services.JobScreeningRefresh, HourUTC: cfg.DailyScreeningHourUTC,
			Run: func(ctx context.Context) (string, error) {
				stats, err := refresher.RefreshAll(ctx)
				return stats.String(), err
			},
		})
	}
	if cfg.PulseAutodraftEnabled {
		registerAutodraft(runner, d, eodhd)
	}
	log.Printf("[daily-jobs] registered: %v", runner.Names())
	return runner
}

// registerAutodraft adds the Pulse auto-draft job when GEMINI_API_KEY is set.
func registerAutodraft(runner *services.DailyJobRunner, d dailyJobDeps, eodhd *marketdata.EODHDProvider) {
	if d.cfg.GeminiAPIKey == "" {
		log.Printf("[daily-jobs] PULSE_AUTODRAFT_ENABLED but GEMINI_API_KEY not set: auto-draft off")
		return
	}
	writer, err := services.NewGeminiPulseWriter(context.Background(), d.cfg.GeminiAPIKey, d.cfg.PulseAutodraftModel)
	if err != nil {
		log.Printf("[daily-jobs] auto-draft off: %v", err)
		return
	}
	drafter := &services.PulseAutoDrafter{
		News: eodhd, Store: d.pulseAdmin, Stocks: d.stocks, Writer: writer, Now: time.Now,
	}
	runner.Register(services.DailyJob{
		Name: services.JobPulseAutodraft, HourUTC: d.cfg.PulseAutodraftHourUTC, Run: drafter.Run,
	})
}

// registerStoreRefunds adds the Google Play refund job when it is on and
// the Play service account is configured.
func registerStoreRefunds(runner *services.DailyJobRunner, d dailyJobDeps) {
	if !d.cfg.StoreRefundsEnabled {
		return
	}
	if d.googlePlay == nil {
		log.Printf("[daily-jobs] STORE_REFUNDS_ENABLED but Google Play is not configured: refund job off")
		return
	}
	sync := &services.GoogleRefundSync{Play: d.googlePlay, Revoker: d.storeGrants}
	runner.Register(services.DailyJob{
		Name: services.JobStoreRefunds, HourUTC: d.cfg.StoreRefundsHourUTC, Run: sync.Run,
	})
}
