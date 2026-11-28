// eodhd_news.go — EODHD financial news feed (GET /api/news), used by the
// Pulse auto-draft job (docs/pulse/AUTODRAFT.md).
//
// EODHD accepts ONE ticker per request (`s`), so FetchNews makes one
// request per symbol and merges them. Cost: 5 API calls per request plus 5
// per ticker, about 10 calls per covered stock per day.
package marketdata

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// eodhdNewsURL is the news endpoint; a var so tests can point it at an
// httptest server.
var eodhdNewsURL = "https://eodhd.com/api/news"

// maxNewsLimit is EODHD's upper bound for `limit`.
const maxNewsLimit = 1000

// NewsArticle is one article from the feed.
type NewsArticle struct {
	PublishedAt time.Time
	Title       string
	Content     string
	Link        string
	Symbols     []string
	Tags        []string
	Polarity    float64 // EODHD sentiment, -1..1
}

// NewsQuery selects articles. Empty Symbols and Topic returns the general
// market feed. Limit applies per request, so per symbol.
type NewsQuery struct {
	Symbols []string // EODHD symbols, e.g. AAPL.US
	Topic   string
	From    time.Time
	Limit   int
}

// maxNewsSymbols caps the requests one FetchNews call makes.
const maxNewsSymbols = 40

type eodhdNewsItem struct {
	Date      string   `json:"date"`
	Title     string   `json:"title"`
	Content   string   `json:"content"`
	Link      string   `json:"link"`
	Symbols   []string `json:"symbols"`
	Tags      []string `json:"tags"`
	Sentiment *struct {
		Polarity float64 `json:"polarity"`
	} `json:"sentiment"`
}

// EODHDSymbols maps app tickers to EODHD symbols, dropping tickers EODHD
// does not cover.
func EODHDSymbols(tickers []string) []string {
	out := []string{}
	for _, t := range tickers {
		if s := eodhdSymbol(t); s != "" {
			out = append(out, s)
		}
	}
	return out
}

// FetchNews reads articles for q: one request per symbol (or one request
// for the general feed / topic when Symbols is empty). A failing symbol is
// skipped; an error is returned only when every request failed.
func (p *EODHDProvider) FetchNews(ctx context.Context, q NewsQuery) ([]NewsArticle, error) {
	if len(q.Symbols) == 0 {
		return p.fetchNewsOnce(ctx, q, "")
	}
	syms := q.Symbols
	if len(syms) > maxNewsSymbols {
		syms = syms[:maxNewsSymbols]
	}
	var all []NewsArticle
	var lastErr error
	for _, sym := range syms {
		got, err := p.fetchNewsOnce(ctx, q, sym)
		if err != nil {
			lastErr = err
			continue
		}
		all = append(all, got...)
	}
	if len(all) == 0 && lastErr != nil {
		return nil, lastErr
	}
	return all, nil
}

func (p *EODHDProvider) fetchNewsOnce(ctx context.Context, q NewsQuery, symbol string) ([]NewsArticle, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, newsURL(p.APIKey, q, symbol), nil)
	if err != nil {
		return nil, fmt.Errorf("building EODHD news request: %w", err)
	}
	resp, err := p.Client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("EODHD news %s: request failed: %v", symbol, withoutURL(err))
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 20<<20))
	if err != nil {
		return nil, fmt.Errorf("reading EODHD news: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("EODHD news %s: HTTP %d", symbol, resp.StatusCode)
	}
	return parseEODHDNews(body)
}

// withoutURL strips the request URL from an HTTP client error. A
// *url.Error prints the full URL, which carries api_token, so only its cause
// may reach logs, Sentry or job_runs.
func withoutURL(err error) error {
	var uerr *url.Error
	if errors.As(err, &uerr) {
		return uerr.Err
	}
	return err
}

func newsURL(apiKey string, q NewsQuery, symbol string) string {
	v := url.Values{}
	v.Set("api_token", apiKey)
	v.Set("fmt", "json")
	if symbol != "" {
		v.Set("s", symbol)
	}
	if q.Topic != "" {
		v.Set("t", q.Topic)
	}
	if !q.From.IsZero() {
		v.Set("from", q.From.UTC().Format("2006-01-02"))
	}
	limit := q.Limit
	if limit <= 0 || limit > maxNewsLimit {
		limit = 50
	}
	v.Set("limit", strconv.Itoa(limit))
	return eodhdNewsURL + "?" + v.Encode()
}

// parseEODHDNews decodes the feed. Articles with no link or title are
// dropped: a Pulse item must cite a real source.
func parseEODHDNews(body []byte) ([]NewsArticle, error) {
	var items []eodhdNewsItem
	if err := json.Unmarshal(body, &items); err != nil {
		return nil, fmt.Errorf("decoding EODHD news: %w", err)
	}
	out := make([]NewsArticle, 0, len(items))
	for _, it := range items {
		if strings.TrimSpace(it.Link) == "" || strings.TrimSpace(it.Title) == "" {
			continue
		}
		a := NewsArticle{
			Title: strings.TrimSpace(it.Title), Content: it.Content, Link: it.Link,
			Symbols: it.Symbols, Tags: it.Tags,
		}
		if t, err := time.Parse(time.RFC3339, it.Date); err == nil {
			a.PublishedAt = t
		}
		if it.Sentiment != nil {
			a.Polarity = it.Sentiment.Polarity
		}
		out = append(out, a)
	}
	return out, nil
}
