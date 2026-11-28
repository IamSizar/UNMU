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
}

// buildDailyJobs registers each enabled job. A job whose keys are missing
// is skipped with a log line rather than failing start-up.
func buildDailyJobs(d dailyJobDeps) *services.DailyJobRunner {
	runner := services.NewDailyJobRunner(d.jobRuns)
	cfg := d.cfg
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
	if cfg.PulseAutodraftEnabled && cfg.AnthropicAPIKey == "" {
		log.Printf("[daily-jobs] PULSE_AUTODRAFT_ENABLED but ANTHROPIC_API_KEY not set: auto-draft off")
	} else if cfg.PulseAutodraftEnabled {
		drafter := &services.PulseAutoDrafter{
			News: eodhd, Store: d.pulseAdmin, Stocks: d.stocks,
			Writer: services.NewClaudePulseWriter(cfg.AnthropicAPIKey, cfg.PulseAutodraftModel),
			Now:    time.Now,
		}
		runner.Register(services.DailyJob{
			Name: services.JobPulseAutodraft, HourUTC: cfg.PulseAutodraftHourUTC, Run: drafter.Run,
		})
	}
	log.Printf("[daily-jobs] registered: %v", runner.Names())
	return runner
}
