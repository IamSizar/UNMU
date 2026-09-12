// Command weekly_digest sends the halal-market weekly email: stocks that
// newly became Shariah-compliant this week, plus each recipient's own
// watchlist/portfolio compliance summary and top community posts. Meant
// to run on a weekly cron (Railway cron job / GitHub Actions schedule),
// the same way cmd/ingest_eodhd is meant to run on a daily one.
//
// Every send is best-effort per user: one bad address or template error
// never stops the rest of the batch. Skips users who disabled email,
// have no address (Firebase-only accounts before they set one), or would
// receive an empty digest.
//
// SHARIAH-REVIEW: "newly compliant" here means "flipped HALAL in the
// shariah_statuses history within the lookback window" — it does not
// re-validate the methodology itself. If admin-configured thresholds
// (see internal/shariah/rules.go) change, this digest reflects whatever
// the screener said at ingestion time, nothing more.
//
// Run:
//
//	cd backend && go run ./cmd/weekly_digest
package main

import (
	"database/sql"
	"fmt"
	"log"
	"strings"
	"time"

	"halalstocks/internal/config"
	"halalstocks/internal/db"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
)

const lookbackDays = 7

type newlyCompliantStock struct {
	Ticker string
	Name   string
	Grade  string
}

type watchedStock struct {
	Ticker string
	Name   string
	Status string
}

type topPost struct {
	AuthorName string
	Body       string
	Likes      int
}

// fatalf captures the error to Sentry (if configured), flushes so it
// actually gets sent before the process exits, then behaves exactly like
// log.Fatalf. Every log.Fatalf call site in this file that represents a
// real operational failure (not a config-once-at-startup nicety) should
// go through this instead — plain log.Fatalf calls os.Exit immediately,
// which would otherwise drop whatever Sentry hasn't sent yet.
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
	jobTags := map[string]string{"job": "weekly_digest"}

	database, err := db.Connect(cfg)
	if err != nil {
		fatalf(jobTags, "db connect: %v", err)
	}
	defer database.Close()
	if sentryEnabled {
		defer services.FlushErrorTracking(2 * time.Second)
	}

	userRepo := repositories.NewUserRepository(database)
	prefsRepo := repositories.NewNotificationPrefsRepository(database)
	portfolioRepo := repositories.NewPortfolioRepository(database)
	stockRepo := repositories.NewStockRepository(database)
	shariahRepo := repositories.NewShariahStatusRepository(database)
	emailSender := services.NewEmailSender()

	if emailSender == nil {
		fatalf(jobTags, "weekly_digest: no email transport configured (set RESEND_API_KEY or SMTP_HOST) — refusing to run a no-op batch")
	}

	sinceDate := time.Now().AddDate(0, 0, -lookbackDays)

	newlyCompliant, err := loadNewlyCompliant(database, sinceDate)
	if err != nil {
		fatalf(jobTags, "load newly-compliant stocks: %v", err)
	}
	log.Printf("Found %d newly-compliant stocks in the last %d days", len(newlyCompliant), lookbackDays)

	topPosts, err := loadTopPosts(database, sinceDate)
	if err != nil {
		log.Printf("WARN load top posts: %v (continuing without them)", err)
		services.CaptureError(err, jobTags)
	}

	users, err := userRepo.ListEmailable()
	if err != nil {
		fatalf(jobTags, "load users: %v", err)
	}
	log.Printf("Loaded %d emailable users", len(users))

	var sent, skipped, failed int
	for _, user := range users {
		prefs, err := prefsRepo.GetOrDefault(user.ID)
		if err != nil {
			log.Printf("WARN  user %d: load prefs: %v (skipping)", user.ID, err)
			skipped++
			continue
		}
		if !prefs.EmailEnabled {
			skipped++
			continue
		}

		watched, err := loadUserWatchedStocks(portfolioRepo, stockRepo, shariahRepo, user.ID)
		if err != nil {
			log.Printf("WARN  user %d: load watched stocks: %v", user.ID, err)
		}

		// Skip users with nothing to tell them — an empty digest is worse
		// than no digest, and every non-empty async surface must earn its
		// send (Section 5.8: never a blank/no-value screen).
		if len(newlyCompliant) == 0 && len(watched) == 0 && len(topPosts) == 0 {
			skipped++
			continue
		}

		name := "there"
		if user.Name.Valid && user.Name.String != "" {
			name = user.Name.String
		}
		subject, html, text := renderDigest(name, newlyCompliant, watched, topPosts)

		if err := emailSender.Send(user.Email, subject, html, text); err != nil {
			log.Printf("FAIL  user %d (%s): %v", user.ID, user.Email, err)
			services.CaptureError(err, jobTags)
			failed++
			continue
		}
		sent++
	}

	log.Printf("──────────────────────────────────────────")
	log.Printf("DONE — %d sent, %d skipped, %d failed", sent, skipped, failed)
}

// loadNewlyCompliant finds stocks that are HALAL as of a record inside the
// lookback window, where the most recent record BEFORE the window (if any)
// was NOT HALAL — i.e. an actual HARAM/DOUBTFUL→HALAL flip, or a brand-new
// listing that started HALAL. A stock that's simply been HALAL all along
// (its most recent pre-window record was already HALAL) is excluded.
func loadNewlyCompliant(database *sql.DB, since time.Time) ([]newlyCompliantStock, error) {
	rows, err := database.Query(`
		SELECT s.ticker, s.name, COALESCE(ss.grade, '')
		FROM shariah_statuses ss
		JOIN stocks s ON s.id = ss.stock_id
		WHERE ss.status = 'HALAL'
		  AND ss.as_of_date >= $1
		  AND ss.as_of_date = (
		      SELECT MAX(as_of_date) FROM shariah_statuses newest
		      WHERE newest.stock_id = ss.stock_id
		  )
		  AND NOT EXISTS (
		      SELECT 1 FROM shariah_statuses prior
		      WHERE prior.stock_id = ss.stock_id
		        AND prior.as_of_date < $1
		        AND prior.as_of_date = (
		            SELECT MAX(as_of_date) FROM shariah_statuses p2
		            WHERE p2.stock_id = ss.stock_id AND p2.as_of_date < $1
		        )
		        AND prior.status = 'HALAL'
		  )
		ORDER BY ss.as_of_date DESC
		LIMIT 10
	`, since)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []newlyCompliantStock
	for rows.Next() {
		var s newlyCompliantStock
		if err := rows.Scan(&s.Ticker, &s.Name, &s.Grade); err != nil {
			log.Printf("WARN scan newly-compliant row: %v", err)
			continue
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

func loadTopPosts(database *sql.DB, since time.Time) ([]topPost, error) {
	rows, err := database.Query(`
		SELECT author_name, body, likes
		FROM posts
		WHERE visibility = 'public' AND created_at >= $1
		ORDER BY likes DESC, created_at DESC
		LIMIT 3
	`, since)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []topPost
	for rows.Next() {
		var p topPost
		if err := rows.Scan(&p.AuthorName, &p.Body, &p.Likes); err != nil {
			log.Printf("WARN scan top-post row: %v", err)
			continue
		}
		if len(p.Body) > 140 {
			p.Body = p.Body[:140] + "…"
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func loadUserWatchedStocks(
	portfolioRepo *repositories.PortfolioRepository,
	stockRepo *repositories.StockRepository,
	shariahRepo *repositories.ShariahStatusRepository,
	userID int64,
) ([]watchedStock, error) {
	portfolios, err := portfolioRepo.GetUserPortfolio(userID)
	if err != nil {
		return nil, err
	}

	// Batch-load (2 queries total) instead of the previous 2-per-row N+1 —
	// this runs once per user inside the outer digest loop, so the old
	// pattern scaled to U x 2P queries across the whole batch.
	stockIDs := make([]int64, len(portfolios))
	for i, p := range portfolios {
		stockIDs[i] = p.StockID
	}
	// Unlike the old per-row fallback (which showed "UNKNOWN" for both "no
	// screening exists" and "a DB error happened," conflating the two), a
	// batch-load failure here is surfaced as a real error to the caller —
	// the outer digest loop already logs+captures it and simply sends that
	// user's digest without a watchlist section, rather than the digest
	// claiming a stock's status is UNKNOWN when it's actually just unknown
	// to this request.
	stocksByID, err := stockRepo.GetByIDs(stockIDs)
	if err != nil {
		return nil, fmt.Errorf("batch-load stocks: %w", err)
	}
	statusByID, err := shariahRepo.GetLatestStatusBatch(stockIDs)
	if err != nil {
		return nil, fmt.Errorf("batch-load statuses: %w", err)
	}

	var out []watchedStock
	for _, p := range portfolios {
		stock := stocksByID[p.StockID]
		if stock == nil {
			continue
		}
		status := "UNKNOWN" // genuinely no screening on record for this stock
		if s := statusByID[p.StockID]; s != nil {
			status = s.Status
		}
		out = append(out, watchedStock{Ticker: stock.Ticker, Name: stock.Name, Status: status})
		if len(out) >= 10 {
			break // keep the email scannable
		}
	}
	return out, nil
}

func renderDigest(name string, newlyCompliant []newlyCompliantStock, watched []watchedStock, posts []topPost) (subject, html, text string) {
	subject = "Your halal-market weekly digest"

	var htmlBuf, textBuf strings.Builder
	htmlBuf.WriteString(fmt.Sprintf("<h2>Salaam %s,</h2><p>Here's what changed in your halal-investing world this week.</p>", escapeHTML(name)))
	textBuf.WriteString(fmt.Sprintf("Salaam %s,\n\nHere's what changed in your halal-investing world this week.\n\n", name))

	if len(newlyCompliant) > 0 {
		htmlBuf.WriteString("<h3>Newly compliant this week</h3><ul>")
		textBuf.WriteString("NEWLY COMPLIANT THIS WEEK\n")
		for _, s := range newlyCompliant {
			grade := s.Grade
			if grade == "" {
				grade = "—"
			}
			htmlBuf.WriteString(fmt.Sprintf("<li><strong>%s</strong> — %s (Grade %s)</li>", escapeHTML(s.Ticker), escapeHTML(s.Name), escapeHTML(grade)))
			textBuf.WriteString(fmt.Sprintf("  - %s — %s (Grade %s)\n", s.Ticker, s.Name, grade))
		}
		htmlBuf.WriteString("</ul>")
		textBuf.WriteString("\n")
	}

	if len(watched) > 0 {
		htmlBuf.WriteString("<h3>Your watchlist &amp; portfolio</h3><ul>")
		textBuf.WriteString("YOUR WATCHLIST & PORTFOLIO\n")
		for _, s := range watched {
			htmlBuf.WriteString(fmt.Sprintf("<li>%s — <strong>%s</strong></li>", escapeHTML(s.Ticker), escapeHTML(s.Status)))
			textBuf.WriteString(fmt.Sprintf("  - %s — %s\n", s.Ticker, s.Status))
		}
		htmlBuf.WriteString("</ul>")
		textBuf.WriteString("\n")
	}

	if len(posts) > 0 {
		htmlBuf.WriteString("<h3>Top community posts this week</h3><ul>")
		textBuf.WriteString("TOP COMMUNITY POSTS THIS WEEK\n")
		for _, p := range posts {
			htmlBuf.WriteString(fmt.Sprintf("<li>%s (%d likes) — %s</li>", escapeHTML(p.AuthorName), p.Likes, escapeHTML(p.Body)))
			textBuf.WriteString(fmt.Sprintf("  - %s (%d likes) — %s\n", p.AuthorName, p.Likes, p.Body))
		}
		htmlBuf.WriteString("</ul>")
	}

	htmlBuf.WriteString("<p style=\"color:#888;font-size:12px\">You're receiving this because email notifications are enabled in your UNMU settings. You can turn them off anytime from your profile.</p>")
	textBuf.WriteString("\n—\nYou can turn off these emails anytime from your UNMU profile settings.")

	return subject, htmlBuf.String(), textBuf.String()
}

func escapeHTML(s string) string {
	r := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;")
	return r.Replace(s)
}
