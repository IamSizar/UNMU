package services

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"strconv"
	"time"

	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
)

// DriftDetector compares a stock's newly-computed Shariah status against
// its previous one and, when it actually changed, (a) writes an admin-
// visible notification row and (b) pushes an alert to every user who has
// the stock in their watchlist or portfolio.
//
// This used to live only inside IngestionService and only wrote the
// user-less notification row (part b never existed — see git history on
// createStatusChangeNotification), so a HALAL→HARAM flip went out to
// nobody. It's now a standalone type so both IngestionService (used by
// cmd/ingest_test) and the production cron job (cmd/ingest_eodhd) share
// the same, actually-notifying logic.
type DriftDetector struct {
	notificationRepo *repositories.NotificationRepository
	portfolioRepo    *repositories.PortfolioRepository // nullable — push skipped if nil
	notifier         *Notifier                         // nullable — push skipped if nil
}

func NewDriftDetector(
	notificationRepo *repositories.NotificationRepository,
	portfolioRepo *repositories.PortfolioRepository,
	notifier *Notifier,
) *DriftDetector {
	return &DriftDetector{
		notificationRepo: notificationRepo,
		portfolioRepo:    portfolioRepo,
		notifier:         notifier,
	}
}

// Check compares latest (the status on record before this ingestion run)
// against next (the freshly computed one) and fires notifications for any
// meaningful change. Safe to call with latest == nil (first-ever screen —
// nothing to compare against, so it's a no-op).
func (d *DriftDetector) Check(stock *models.Stock, latest, next *models.ShariahStatus) {
	if d == nil || latest == nil || next == nil {
		return
	}

	// Only notify on a genuine day-over-day change, not a same-day re-run
	// (ingestion can run more than once a day; we don't want to spam).
	latestDate := truncateToDate(latest.AsOfDate)
	nextDate := truncateToDate(next.AsOfDate)
	if latestDate.Equal(nextDate) {
		return
	}

	if latest.Status != next.Status {
		d.statusChanged(stock, latest.Status, next.Status)
	}

	if latest.PurificationRate.Valid && next.PurificationRate.Valid {
		change := next.PurificationRate.Float64 - latest.PurificationRate.Float64
		if change > 0.5 || change < -0.5 { // ignore noise-level drift
			d.purificationChanged(stock, latest.PurificationRate.Float64, next.PurificationRate.Float64)
		}
	}
}

func truncateToDate(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}

func (d *DriftDetector) statusChanged(stock *models.Stock, oldStatus, newStatus string) {
	if d.notificationRepo != nil {
		d.notificationRepo.Create(&models.Notification{
			StockID: sql.NullInt64{Int64: stock.ID, Valid: true},
			Type:    "STATUS_CHANGE",
			Title:   fmt.Sprintf("Sharia Status Changed: %s", stock.Ticker),
			Message: fmt.Sprintf("The Sharia status of %s has changed from %s to %s", stock.Name, oldStatus, newStatus),
		})
	}
	d.fanOut(stock, "compliance_status_change", map[string]string{
		"ticker": stock.Ticker, "oldStatus": oldStatus, "newStatus": newStatus,
	})
}

func (d *DriftDetector) purificationChanged(stock *models.Stock, oldRate, newRate float64) {
	if d.notificationRepo != nil {
		d.notificationRepo.Create(&models.Notification{
			StockID: sql.NullInt64{Int64: stock.ID, Valid: true},
			Type:    "PURIFICATION_CHANGE",
			Title:   fmt.Sprintf("Purification Rate Changed: %s", stock.Ticker),
			Message: fmt.Sprintf("The purification rate for %s has changed from %.2f%% to %.2f%%", stock.Name, oldRate, newRate),
		})
	}
	d.fanOut(stock, "purification_rate_change", map[string]string{
		"ticker":  stock.Ticker,
		"oldRate": strconv.FormatFloat(oldRate, 'f', 2, 64),
		"newRate": strconv.FormatFloat(newRate, 'f', 2, 64),
	})
}

func (d *DriftDetector) fanOut(stock *models.Stock, notifType string, params map[string]string) {
	if d.portfolioRepo == nil || d.notifier == nil {
		return
	}
	userIDs, err := d.portfolioRepo.GetUserIDsForStock(stock.ID)
	if err != nil {
		log.Printf("[drift] load watchers for stock %d: %v", stock.ID, err)
		return
	}
	if len(userIDs) == 0 {
		return
	}
	d.notifier.PushToUsers(context.Background(), userIDs, notifType, params)
}
