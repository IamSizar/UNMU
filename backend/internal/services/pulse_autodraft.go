// pulse_autodraft.go — the daily Pulse auto-draft job (docs/pulse/AUTODRAFT.md).
//
// It gathers fresh EODHD news plus recent Sharia verdict changes, asks a
// PulseDraftWriter (Claude) to pick one story per free slot, checks every
// pick against the rules below, and saves the good ones as DRAFTS. People
// still verify, review and approve each item in the dashboard.
package services

import (
	"context"
	"fmt"
	"log"
	"sort"
	"strings"
	"time"

	"halalstocks/internal/marketdata"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
)

const (
	newsWindow          = 36 * time.Hour
	shariahChangeWindow = 7 * 24 * time.Hour
	maxDraftArticles    = 40
	maxArticleRunes     = 2000
	stockNewsLimit      = 8 // per ticker
	generalNewsLimit    = 40
	// ShariahDataSource is the source name on a Sharia-slot draft built from
	// our own screening data rather than a news article.
	ShariahDataSource = "UNMU Sharia screening"
	// noArticle is the article index a Sharia-slot pick uses when it is
	// built from screening changes.
	noArticle = -1
)

// pulseDayZone matches the app's "today" (handlers.pulseLocation).
var pulseDayZone = time.FixedZone("Asia/Baghdad", 3*60*60)

// pulseSlots is every slot, in display order.
var pulseSlots = []string{"global", "gulf", "sharia", "opportunity"}

// DraftArticle is one numbered article shown to the writer.
type DraftArticle struct {
	Index       int      `json:"index"`
	Title       string   `json:"title"`
	Content     string   `json:"content"`
	Source      string   `json:"source"`
	Link        string   `json:"link"`
	PublishedAt string   `json:"publishedAt"`
	Symbols     []string `json:"symbols"`
	Polarity    float64  `json:"sentiment"`
}

// PulseDraftRequest is everything the writer may use. Nothing else.
type PulseDraftRequest struct {
	Date           string                       `json:"date"`
	OpenSlots      []string                     `json:"openSlots"`
	Articles       []DraftArticle               `json:"articles"`
	ShariahChanges []repositories.ShariahChange `json:"shariahChanges"`
	CoveredTickers []string                     `json:"coveredTickers"`
}

// PulseDraft is one item the writer proposes.
type PulseDraft struct {
	Slot           string `json:"slot"`
	ArticleIndex   int    `json:"article_index"`
	Classification string `json:"classification"`
	TitleAr        string `json:"title_ar"`
	TitleEn        string `json:"title_en"`
	SummaryAr      string `json:"summary_ar"`
	SummaryEn      string `json:"summary_en"`
	DetailsAr      string `json:"details_ar"`
	DetailsEn      string `json:"details_en"`
	EvidenceAr     string `json:"evidence_ar"`
	EvidenceEn     string `json:"evidence_en"`
	StockTicker    string `json:"stock_ticker"`
}

// PulseDraftWriter turns a request into proposed drafts.
type PulseDraftWriter interface {
	WriteDrafts(ctx context.Context, req PulseDraftRequest) ([]PulseDraft, error)
}

type newsFetcher interface {
	FetchNews(ctx context.Context, q marketdata.NewsQuery) ([]marketdata.NewsArticle, error)
}

type autoDraftStore interface {
	TakenSlots(ctx context.Context, date string) (map[string]bool, error)
	CreateAutoDraft(ctx context.Context, in models.PulseItemInput) (*models.PulseAdminItem, error)
	RecentShariahChanges(ctx context.Context, since time.Time) ([]repositories.ShariahChange, error)
}

type stockLister interface {
	GetAll(limit, offset int) ([]*models.Stock, error)
}

// PulseAutoDrafter wires the job's dependencies.
type PulseAutoDrafter struct {
	News   newsFetcher
	Store  autoDraftStore
	Stocks stockLister
	Writer PulseDraftWriter
	Now    func() time.Time
}

// Run makes today's drafts and returns a one-line summary.
func (d *PulseAutoDrafter) Run(ctx context.Context) (string, error) {
	now := d.Now()
	date := now.In(pulseDayZone).Format("2006-01-02")
	taken, err := d.Store.TakenSlots(ctx, date)
	if err != nil {
		return "", err
	}
	open := openSlots(taken)
	if len(open) == 0 {
		return "all slots already have items for " + date, nil
	}
	req, stockIDs, err := d.buildRequest(ctx, now, date, open)
	if err != nil {
		return "", err
	}
	if len(req.Articles) == 0 && len(req.ShariahChanges) == 0 {
		return "no fresh news or Sharia changes; no drafts made", nil
	}
	drafts, err := d.Writer.WriteDrafts(ctx, req)
	if err != nil {
		return "", fmt.Errorf("writing drafts: %w", err)
	}
	return d.saveDrafts(ctx, req, drafts, stockIDs), nil
}

func openSlots(taken map[string]bool) []string {
	open := []string{}
	for _, s := range pulseSlots {
		if !taken[s] {
			open = append(open, s)
		}
	}
	return open
}

// buildRequest gathers news and Sharia changes for the writer.
func (d *PulseAutoDrafter) buildRequest(
	ctx context.Context, now time.Time, date string, open []string,
) (PulseDraftRequest, map[string]int, error) {
	req := PulseDraftRequest{Date: date, OpenSlots: open}
	stocks, err := d.Stocks.GetAll(screeningStockLimit, 0)
	if err != nil {
		return req, nil, fmt.Errorf("loading stocks: %w", err)
	}
	stockIDs := map[string]int{}
	for _, s := range stocks {
		stockIDs[strings.ToUpper(s.Ticker)] = int(s.ID)
		req.CoveredTickers = append(req.CoveredTickers, strings.ToUpper(s.Ticker))
	}
	articles, err := d.fetchArticles(ctx, now, req.CoveredTickers)
	if err != nil {
		return req, nil, err
	}
	req.Articles = articles
	req.ShariahChanges, err = d.Store.RecentShariahChanges(ctx, now.Add(-shariahChangeWindow))
	return req, stockIDs, err
}

// fetchArticles merges stock news and the general feed: deduplicated by
// link, inside the news window, newest first, capped. One failing source
// is logged and skipped; it is an error only when both fail.
func (d *PulseAutoDrafter) fetchArticles(ctx context.Context, now time.Time, tickers []string) ([]DraftArticle, error) {
	from := now.Add(-newsWindow)
	var all []marketdata.NewsArticle
	var stockErr error
	if syms := marketdata.EODHDSymbols(tickers); len(syms) > 0 {
		var got []marketdata.NewsArticle
		got, stockErr = d.News.FetchNews(ctx, marketdata.NewsQuery{Symbols: syms, From: from, Limit: stockNewsLimit})
		all = append(all, got...)
	}
	general, genErr := d.News.FetchNews(ctx, marketdata.NewsQuery{From: from, Limit: generalNewsLimit})
	if genErr != nil && (stockErr != nil || len(all) == 0) {
		return nil, fmt.Errorf("fetching news: %w", genErr)
	}
	if genErr != nil {
		log.Printf("[pulse-autodraft] WARN general news feed: %v", genErr)
	}
	return toDraftArticles(append(all, general...), from), nil
}

func toDraftArticles(in []marketdata.NewsArticle, from time.Time) []DraftArticle {
	seen := map[string]bool{}
	kept := []marketdata.NewsArticle{}
	for _, a := range in {
		if seen[a.Link] || (!a.PublishedAt.IsZero() && a.PublishedAt.Before(from)) {
			continue
		}
		seen[a.Link] = true
		kept = append(kept, a)
	}
	sort.SliceStable(kept, func(i, j int) bool { return kept[i].PublishedAt.After(kept[j].PublishedAt) })
	if len(kept) > maxDraftArticles {
		kept = kept[:maxDraftArticles]
	}
	out := make([]DraftArticle, len(kept))
	for i, a := range kept {
		out[i] = DraftArticle{
			Index: i, Title: a.Title, Content: clipRunes(a.Content, maxArticleRunes),
			Source: sourceHost(a.Link), Link: a.Link, PublishedAt: a.PublishedAt.UTC().Format(time.RFC3339),
			Symbols: a.Symbols, Polarity: a.Polarity,
		}
	}
	return out
}

// saveDrafts validates and stores each pick; returns the job summary.
func (d *PulseAutoDrafter) saveDrafts(
	ctx context.Context, req PulseDraftRequest, drafts []PulseDraft, stockIDs map[string]int,
) string {
	var made, rejected []string
	used := map[string]bool{}
	for _, dr := range drafts {
		in, err := draftToInput(dr, req, stockIDs, used)
		if err == nil {
			_, err = d.Store.CreateAutoDraft(ctx, in)
		}
		if err != nil {
			rejected = append(rejected, fmt.Sprintf("%s (%v)", dr.Slot, err))
			continue
		}
		used[dr.Slot] = true
		made = append(made, dr.Slot)
	}
	summary := fmt.Sprintf("%s: %d drafts [%s]", req.Date, len(made), strings.Join(made, ", "))
	if len(rejected) > 0 {
		summary += "; rejected: " + strings.Join(rejected, "; ")
	}
	return summary
}
